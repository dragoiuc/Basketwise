import os;
import from services.basketwiseTypes { ProductIntent, RawListing, ResolvedQuery, SemanticCandidate, SemanticMatchResult }
import from services.groceryText { requested_packages, split_exclusions }
import from services.productMatching { match_resolved }
import from services.productInterpreter {
    resolve_query, interpret_deterministic, interpret_query, selected_interpreter, set_intent_provider,
    set_judge_provider, clear_interpretation_cache, judge_candidates
}

# Annex of semanticCorpus.jac (a module production code never imports, which
# avoids import cycles). Tests are credential-independent: semantic behavior
# is exercised with typed ProductIntent fixtures (the shape
# llm_interpret_grocery_query returns) fed through the same
# resolve_query/match_resolved pipeline used in production.
#   A. query interpretation / grounding
#   B. deterministic package parsing
#   C. candidate semantic compatibility
# (D. full search integration lives in searchCoordinator.test.jac.)

with entry {
    os.environ["PRODUCT_INTERPRETER"] = "deterministic";
}

def _listing(name: str, brand: str, size: str) -> RawListing {
    return RawListing(store_id="s", source="fixture", product_name=name, regular_price=1.0, brand=brand, size_text=size);
}

def _resolve_case(cc: CorpusCase) -> ResolvedQuery {
    return resolve_query(cc.query, cc.intent, "", "", False, "llm");
}

# ---------------- A. query interpretation / grounding ----------------

test "deterministic mode is the default and a key alone never enables llm" {
    saved = os.environ.get("PRODUCT_INTERPRETER", "");
    saved_key = os.environ.get("OPENAI_API_KEY", "");
    del os.environ["PRODUCT_INTERPRETER"];
    os.environ["OPENAI_API_KEY"] = "placeholder-not-a-real-key";
    mode = selected_interpreter();
    os.environ["OPENAI_API_KEY"] = saved_key;
    os.environ["PRODUCT_INTERPRETER"] = saved or "deterministic";
    assert mode == "deterministic";
}

test "deterministic interpretation splits explicit exclusions" {
    intent = interpret_deterministic("regular cheerios not honey nut", "", False);
    assert intent.canonical_product == "cheerio";
    assert intent.exclusions == ["honey nut"];
    assert intent.organic is None;
}

test "deterministic interpretation never invents organic" {
    assert interpret_deterministic("milk", "", False).organic is None;
    assert interpret_deterministic("organic milk", "", False).organic == True;
}

test "exclusion clause ends at package text" {
    (positive, exclusions) = split_exclusions("cheerios without honey nut 18 oz");
    assert exclusions == ["honey nut"];
    assert "18 oz" in positive;
}

test "llm cannot invent organic brand or descriptors for plain milk" {
    over_eager = ProductIntent(canonical_product="milk", brand="Horizon", variety="whole", organic=True, attributes=["lactose free"], retailer_search_term="organic whole milk");
    resolved = resolve_query("milk", over_eager, "", "", False, "llm");
    assert not resolved.organic_required;
    assert resolved.identity_terms == ["milk"];
    assert resolved.descriptor_terms == [];
    assert "organic" in resolved.dropped_terms;
    assert "whole" in resolved.dropped_terms;
    assert resolved.intent.organic is None;
}

test "llm exclusions must be grounded in the query" {
    intent = ProductIntent(canonical_product="cheerios", exclusions=["honey nut", "chocolate"]);
    resolved = resolve_query("regular cheerios not honey nut", intent, "", "", False, "llm");
    assert "honey nut" in resolved.exclusion_phrases;
    assert "chocolate" not in resolved.exclusion_phrases;
}

test "explicit ui filters outrank semantic intent" {
    intent = ProductIntent(canonical_product="eggs", brand="Other Farm", retailer_search_term="large eggs");
    resolved = resolve_query("large eggs", intent, "Wanted Farms", "18 ct", True, "llm");
    assert resolved.required_brand == "Wanted Farms";
    assert resolved.organic_required;
    assert any([p.source == "required_size" and p.quantity == 18.0 for p in resolved.packages]);
}

test "retailer search term drops package text and falls back when unusable" {
    good = resolve_query("large eggs 12 count", ProductIntent(canonical_product="eggs", size_class="large", retailer_search_term="large eggs"), "", "", False, "llm");
    assert good.search_term == "large eggs";
    leaky = resolve_query("large eggs 12 count", ProductIntent(canonical_product="eggs", retailer_search_term="large eggs 12 count"), "", "", False, "llm");
    assert leaky.search_term == "large eggs";
    empty = resolve_query("large eggs 12 count", ProductIntent(canonical_product="eggs"), "", "", False, "llm");
    assert empty.search_term == "large eggs";
    assert good.raw_query == "large eggs 12 count";
}

test "fixture intent provider is used once and cached for identical queries" {
    calls: list[str] = [];
    def provider(query: str, filters: str) -> ProductIntent {
        calls.append(query);
        return ProductIntent(canonical_product="eggs", size_class="large", retailer_search_term="large eggs");
    }
    clear_interpretation_cache();
    set_intent_provider(provider);
    a = interpret_query("large eggs 12 count", "", "", False);
    b = interpret_query("Large  Eggs 12 COUNT", "", "", False);
    set_intent_provider(None);
    clear_interpretation_cache();
    assert a.source == "llm" and b.source == "llm_cached";
    assert len(calls) == 1;
    assert a.interpretation_calls == 1 and b.interpretation_calls == 0;
}

test "invalid structured output falls back to deterministic" {
    def empty_intent(query: str, filters: str) -> ProductIntent { return ProductIntent(); }
    clear_interpretation_cache();
    set_intent_provider(empty_intent);
    resolved = interpret_query("large eggs 12 count", "", "", False);
    set_intent_provider(None);
    assert resolved.source == "deterministic_fallback";
    assert resolved.note != "";
}

test "only query text and relevant filters reach the interpreter" {
    seen: list[str] = [];
    def spy(query: str, filters: str) -> ProductIntent {
        seen.append(query + "|" + filters);
        return ProductIntent(canonical_product="eggs");
    }
    clear_interpretation_cache();
    set_intent_provider(spy);
    _ = interpret_query("eggs", "Farm", "12 ct", True);
    set_intent_provider(None);
    clear_interpretation_cache();
    assert seen == ["eggs|brand=Farm, organic=required"];
}

# ---------------- B. deterministic package parsing -------------------

test "corpus package constraints are deterministic and independent of intent" {
    for cc in CORPUS {
        packages = requested_packages(cc.query, "");
        if cc.package_unit == "" {
            assert len(packages) == 0, cc.query;
        } else {
            assert len(packages) == 1, cc.query;
            assert packages[0].unit == cc.package_unit, cc.query;
            assert abs(packages[0].quantity - cc.package_qty) < 0.001, cc.query;
            assert packages[0].approximate == cc.approximate, cc.query;
        }
        resolved = _resolve_case(cc);
        assert len(resolved.packages) == len(packages), cc.query;
    }
}

test "approximate weight uses a wider but bounded tolerance" {
    intent = ProductIntent(canonical_product="ground beef", variety="90/10");
    resolved = resolve_query("ground beef 90/10 around 1 lb", intent, "", "", False, "llm");
    assert resolved.packages[0].approximate;
    assert match_resolved(resolved, _listing("Ground Beef 90/10", "Ranch", "1.1 lb")).is_match;
    assert not match_resolved(resolved, _listing("Ground Beef 90/10", "Ranch", "2 lb")).is_match;
    exact = resolve_query("ground beef 90/10 1 lb", intent, "", "", False, "llm");
    assert not match_resolved(exact, _listing("Ground Beef 90/10", "Ranch", "1.1 lb")).is_match;
}

# ---------------- C. candidate semantic compatibility ----------------

test "semantic corpus positives match deterministically or flag for review" {
    for cc in CORPUS {
        resolved = _resolve_case(cc);
        for (name, brand, size) in cc.positives {
            decision = match_resolved(resolved, _listing(name, brand, size));
            assert decision.is_match or decision.needs_semantic_review, cc.query + " -> " + name + ": " + decision.reason;
        }
    }
}

test "semantic corpus negatives are never accepted deterministically" {
    for cc in CORPUS {
        resolved = _resolve_case(cc);
        for (name, brand, size) in cc.negatives {
            decision = match_resolved(resolved, _listing(name, brand, size));
            assert not decision.is_match, cc.query + " accepted " + name;
        }
    }
}

test "hard negatives are rejected without semantic review" {
    for cc in CORPUS {
        resolved = _resolve_case(cc);
        for (name, brand, size) in cc.hard_negatives {
            decision = match_resolved(resolved, _listing(name, brand, size));
            assert not decision.is_match and not decision.needs_semantic_review, cc.query + " -> " + name + ": " + decision.reason;
        }
    }
}

test "corpus is broad enough" {
    assert len(CORPUS) >= 30;
    categories: list[str] = [];
    for cc in CORPUS {
        if cc.category not in categories { categories.append(cc.category); }
    }
    for needed in ["eggs", "dairy milk", "plant milk", "cereal", "soda", "yogurt", "bread", "broth", "cheese", "chicken", "ground beef", "produce", "frozen", "pasta rice", "canned"] {
        assert needed in categories, needed;
    }
}

test "batched judge decisions are keyed by candidate id not position" {
    def judge(intent: ProductIntent, raw: str, candidates: list[SemanticCandidate]) -> list[SemanticMatchResult] {
        return [SemanticMatchResult(candidate_id=c.candidate_id, is_semantic_match=(c.candidate_id == "b"), reason="x") for c in reversed(candidates)] + [SemanticMatchResult(candidate_id="zzz", is_semantic_match=True, reason="bogus")];
    }
    set_judge_provider(judge);
    resolved = resolve_query("eggs", ProductIntent(canonical_product="eggs"), "", "", False, "llm");
    decisions = judge_candidates(resolved, [SemanticCandidate(candidate_id="a", product_name="A"), SemanticCandidate(candidate_id="b", product_name="B")]);
    set_judge_provider(None);
    assert not decisions["a"].is_semantic_match;
    assert decisions["b"].is_semantic_match;
    assert "zzz" not in decisions;
}
