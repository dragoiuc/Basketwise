import os;
import from services.basketwiseTypes { SearchRequest, SearchResponse, CompareMode, StockStatus, PriceType, ProductIntent, SemanticCandidate, SemanticMatchResult }
import from services.productInterpreter { set_intent_provider, set_judge_provider, clear_interpretation_cache, usage_snapshot }

# The regression baseline is the deterministic mock provider, independent of
# any local .env provider selection or credentials.
with entry {
    os.environ["GROCERY_DATA_PROVIDER"] = "mock";
    os.environ["PRODUCT_INTERPRETER"] = "deterministic";
}

def _reset_semantic {
    set_intent_provider(None);
    set_judge_provider(None);
    clear_interpretation_cache();
}

def _fixture_intent(query: str, filters: str) -> ProductIntent {
    q = query.lower();
    if "cheerios" in q {
        return ProductIntent(canonical_product="cheerios", exclusions=["honey nut"], retailer_search_term="cheerios");
    }
    if "yogurt" in q {
        return ProductIntent(canonical_product="greek yogurt", variety="strawberry", retailer_search_term="strawberry greek yogurt");
    }
    if "chicken" in q {
        return ProductIntent(canonical_product="chicken breast", form="boneless skinless", retailer_search_term="boneless skinless chicken breast");
    }
    if "coke" in q {
        return ProductIntent(canonical_product="coke zero", form="cans", retailer_search_term="coke zero");
    }
    if "milk" in q {
        return ProductIntent(canonical_product="milk", variety="whole", retailer_search_term="whole milk");
    }
    # Deliberately over-eager model output: must be grounded away.
    return ProductIntent(canonical_product="eggs", size_class="large", organic=True, attributes=["cage free"], retailer_search_term="large eggs");
}

# Oracle standing in for the batched semantic matcher in deterministic tests.
glob _judge_batches: list[int] = [];
def _fixture_judge(intent: ProductIntent, raw_query: str, candidates: list[SemanticCandidate]) -> list[SemanticMatchResult] {
    _judge_batches.append(len(candidates));
    out: list[SemanticMatchResult] = [];
    for c in reversed(candidates) {
        name = c.product_name.lower();
        ok = ("fillet" in name and "chicken breast" in name) or ("zero sugar" in name);
        out.append(SemanticMatchResult(candidate_id=c.candidate_id, is_semantic_match=ok, reason="fixture"));
    }
    return out;
}

def _semantic_search(query: str) -> SearchResponse {
    _reset_semantic();
    set_intent_provider(_fixture_intent);
    set_judge_provider(_fixture_judge);
    response = search_groceries(query=query, location_text="Ann Arbor, MI");
    _reset_semantic();
    return response;
}

def _search(request: SearchRequest) -> SearchResponse {
    return search_groceries(
        query=request.query,
        location_text=request.location_text,
        radius_miles=request.radius_miles,
        required_brand=request.required_brand,
        required_size=request.required_size,
        organic_only=request.organic_only,
        compare_mode="unit" if request.compare_mode == CompareMode.UNIT_PRICE else "checkout",
        include_membership_prices=request.include_membership_prices,
        include_coupons=request.include_coupons,
        quantity=request.quantity,
        max_results=request.max_results
    );
}

test "request boolean parser accepts true forms and rejects false or unknown forms" {
    assert parse_request_bool(True);
    assert parse_request_bool("true");
    assert parse_request_bool("True");
    assert parse_request_bool("1");
    assert not parse_request_bool(False);
    assert not parse_request_bool("false");
    assert not parse_request_bool("False");
    assert not parse_request_bool("0");
    assert not parse_request_bool("unknown");
}

test "full mock acceptance search returns valid twelve count eggs" {
    response = _search(SearchRequest(query="large eggs 12 count", location_text="Ann Arbor, MI", radius_miles=10.0));
    assert response.validation_error == "";
    assert response.is_demo_data;
    assert len(response.results) > 0;
    for result in response.results {
        assert result.is_demo_data;
        assert result.size_text == "12 count" or result.size_text == "1 dozen";
        assert result.stock_status == StockStatus.IN_STOCK;
        assert result.normalized_unit == "count";
        assert result.normalized_quantity == 12.0;
        assert result.unit_price > 0.0;
    }
}

test "large eggs twelve count excludes eighteen count and incompatible fixtures" {
    response = _search(SearchRequest(query="large eggs 12 count", location_text="Ann Arbor, MI"));
    for result in response.results {
        assert result.size_text != "18 ct";
        assert result.size_text != "2 lb";
        assert result.size_text != "64 fl oz";
        assert result.size_text != "family pack";
    }
}

test "broad large eggs search accepts multiple valid package sizes and classes" {
    response = _search(SearchRequest(query="large eggs", location_text="Ann Arbor, MI"));
    saw_12: bool = False;
    saw_18: bool = False;
    for result in response.results {
        if result.size_text == "12 count" { saw_12 = True; }
        if result.size_text == "18 ct" { saw_18 = True; }
        assert result.brand != "Farmstead Select";
        assert result.brand != "Basketwise Farms" or "Extra Large" not in result.product_name;
    }
    assert saw_12;
    assert saw_18;
}

test "checkout prices sort deterministically with sale first" {
    response = _search(SearchRequest(query="large eggs 12 count", location_text="Ann Arbor, MI", compare_mode=CompareMode.CHECKOUT_PRICE));
    prices = [r.effective_price for r in response.results];
    assert prices == sorted(prices);
    assert response.results[0].effective_price == 3.79;
    assert response.results[0].price_type == PriceType.SALE;
}

test "member and coupon eligibility change effective checkout ranking" {
    no_member = _search(SearchRequest(query="large eggs 12 count", location_text="Ann Arbor, MI"));
    with_member = _search(SearchRequest(query="large eggs 12 count", location_text="Ann Arbor, MI", include_membership_prices=True));
    with_coupon = _search(SearchRequest(query="large eggs 12 count", location_text="Ann Arbor, MI", include_coupons=True));
    assert no_member.results[0].brand == "Basketwise Farms";
    assert with_member.results[0].brand == "Value Club";
    assert with_member.results[0].effective_price == 3.49;
    assert with_coupon.results[0].brand == "Coupon Corner";
    assert with_coupon.results[0].effective_price == 2.99;
}

test "unit price mode places compatible count results first" {
    response = _search(SearchRequest(query="large eggs", location_text="Ann Arbor, MI", compare_mode=CompareMode.UNIT_PRICE));
    seen_incompatible: bool = False;
    previous_count_price: float = -1.0;
    saw_mass: bool = False;
    saw_volume: bool = False;
    saw_unknown: bool = False;
    for result in response.results {
        compatible = result.normalized_unit == "count" and result.unit_price >= 0.0;
        if compatible {
            assert not seen_incompatible;
            if previous_count_price >= 0.0 { assert result.unit_price >= previous_count_price; }
            previous_count_price = result.unit_price;
        } else {
            seen_incompatible = True;
            if result.normalized_unit == "oz" { saw_mass = True; }
            elif result.normalized_unit == "fl_oz" { saw_volume = True; }
            elif result.unit_price < 0.0 { saw_unknown = True; }
        }
    }
    assert saw_mass and saw_volume and saw_unknown;
}

test "out of stock entries are rejected" {
    response = _search(SearchRequest(query="large eggs 12 count", location_text="Ann Arbor, MI"));
    for result in response.results { assert result.stock_status == StockStatus.IN_STOCK; }
}

test "unsupported and failing adapters do not abort search" {
    response = _search(SearchRequest(query="large eggs 12 count", location_text="Ann Arbor, MI"));
    assert response.diagnostics.unsupported_stores >= 1;
    assert len(response.diagnostics.errors) >= 1;
    assert len(response.results) > 0;
}

test "empty query and empty location fail validation safely" {
    bad_query = search_groceries(query="", location_text="Ann Arbor, MI");
    bad_location = search_groceries(query="eggs", location_text="");
    assert bad_query.validation_error != "" and len(bad_query.results) == 0;
    assert bad_location.validation_error != "" and len(bad_location.results) == 0;
}

test "invalid comparison mode safely defaults to checkout" {
    response = search_groceries(query="large eggs 12 count", location_text="Ann Arbor, MI", compare_mode="unexpected");
    assert len(response.results) > 0;
    assert response.results[0].effective_price == 3.79;
}

test "max results is enforced" {
    response = _search(SearchRequest(query="large eggs 12 count", location_text="Ann Arbor, MI", max_results=1));
    assert len(response.results) == 1;
}

test "results carry browser safe price and stock projections" {
    response = _search(SearchRequest(query="large eggs 12 count", location_text="Ann Arbor, MI"));
    top = response.results[0];
    assert top.price_label == "Sale";
    assert not top.is_regular_price;
    assert top.in_stock;
    assert top.distance_label.endswith(" mi");
    assert top.price_display == "$3.79";
    assert top.unit_price_display == "$0.316 / count";
    assert top.confidence_display.startswith("Match confidence ");
}

test "deterministic mode reports deterministic interpretation and zero llm calls" {
    _reset_semantic();
    response = search_groceries(query="large eggs 12 count", location_text="Ann Arbor, MI");
    assert response.diagnostics.interpretation_source == "deterministic";
    assert response.diagnostics.interpretation_calls == 0;
    assert response.diagnostics.semantic_match_calls == 0;
    assert response.diagnostics.search_term == "large eggs";
}

test "llm mode without credential falls back explicitly with a diagnostic" {
    _reset_semantic();
    saved = {k: os.environ.get(k, "") for k in ["PRODUCT_INTERPRETER", "OPENAI_API_KEY", "LLM_MODEL"]};
    os.environ["PRODUCT_INTERPRETER"] = "llm";
    os.environ["OPENAI_API_KEY"] = "";
    os.environ["LLM_MODEL"] = "gpt-4o-mini";
    response = search_groceries(query="large eggs 12 count", location_text="Ann Arbor, MI");
    for (k, v) in saved.items() { os.environ[k] = v; }
    assert response.diagnostics.interpretation_source == "deterministic_fallback";
    assert any(["Semantic interpretation unavailable" in w for w in response.diagnostics.warnings]);
    assert len(response.results) > 0;
    for r in response.results { assert r.normalized_quantity == 12.0; }
}

test "failing semantic model falls back without failing the search" {
    _reset_semantic();
    def boom(query: str, filters: str) -> ProductIntent { raise Exception("provider exploded sk-secret"); }
    set_intent_provider(boom);
    response = search_groceries(query="large eggs 12 count", location_text="Ann Arbor, MI");
    _reset_semantic();
    assert response.diagnostics.interpretation_source == "deterministic_fallback";
    assert len(response.results) > 0;
    for w in response.diagnostics.warnings { assert "sk-secret" not in w and "exploded" not in w; }
}

test "semantic eggs regression keeps 12 count large and ignores invented organic" {
    response = _semantic_search("large eggs 12 count");
    assert response.diagnostics.interpretation_source == "llm";
    assert response.diagnostics.interpretation_calls == 1;
    assert len(response.results) > 0;
    for r in response.results {
        assert r.normalized_quantity == 12.0 and r.normalized_unit == "count";
        assert "Extra Large" not in r.product_name;
    }
    assert response.results[0].effective_price == 3.79;
}

test "semantic exclusion rejects honey nut cheerios" {
    response = _semantic_search("regular cheerios not honey nut");
    names = [r.product_name for r in response.results];
    assert "Cheerios Original" in names;
    assert "Honey Nut Cheerios" not in names;
}

test "semantic variety restricts strawberry greek yogurt" {
    response = _semantic_search("strawberry greek yogurt");
    names = [r.product_name for r in response.results];
    assert names == ["Strawberry Greek Yogurt", "Strawberry Greek Yogurt"];
}

test "form constraint rejects bone-in and thighs but batch review accepts fillets" {
    _judge_batches.clear();
    response = _semantic_search("boneless skinless chicken breast");
    names = [r.product_name for r in response.results];
    assert "Boneless Skinless Chicken Breast" in names;
    assert "Chicken Breast Fillets" in names;
    assert "Bone-In Split Chicken Breast" not in names;
    assert "Boneless Skinless Chicken Thighs" not in names;
    assert response.diagnostics.semantic_match_calls == 1;
    assert len(_judge_batches) == 1;
    assert response.diagnostics.semantic_candidates_evaluated == _judge_batches[0];
}

test "coke zero 12 pack cans matches container count and rejects diet coke" {
    response = _semantic_search("Coke Zero 12 pack cans");
    names = [r.product_name for r in response.results];
    assert names == ["Coca-Cola Zero Sugar Cans", "Coca-Cola Zero Sugar Cans"];
    assert abs(response.results[0].normalized_quantity - 144.0) < 0.01;
}

test "whole milk 1 gallon still relies on deterministic gallon comparison" {
    response = _semantic_search("whole milk 1 gallon");
    assert len(response.results) == 2;
    for r in response.results {
        assert r.product_name == "Whole Milk";
        assert r.size_text == "1 gallon";
        assert abs(r.normalized_quantity - 128.0) < 0.01;
    }
}

test "identical queries reuse the cached interpretation" {
    _reset_semantic();
    set_intent_provider(_fixture_intent);
    before = usage_snapshot()["interpretation_calls"];
    first = search_groceries(query="strawberry greek yogurt", location_text="Ann Arbor, MI");
    second = search_groceries(query="  Strawberry Greek Yogurt ", location_text="Ann Arbor, MI");
    after = usage_snapshot()["interpretation_calls"];
    _reset_semantic();
    assert first.diagnostics.interpretation_source == "llm";
    assert second.diagnostics.interpretation_source == "llm_cached";
    assert after - before == 1;
}

test "deterministic mode rejects ambiguous candidates conservatively" {
    _reset_semantic();
    response = search_groceries(query="boneless skinless chicken breast", location_text="Ann Arbor, MI");
    names = [r.product_name for r in response.results];
    assert names == ["Boneless Skinless Chicken Breast", "Boneless Skinless Chicken Breast"];
    assert response.diagnostics.semantic_match_calls == 0;
}
