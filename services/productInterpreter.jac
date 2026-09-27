import os;
import from concurrent.futures { ThreadPoolExecutor }
import from services.basketwiseTypes {
    ProductIntent, ResolvedQuery, PackageConstraint, SemanticCandidate, SemanticMatchResult
}
import from services.groceryText {
    normalize_text, split_exclusions, query_product_tokens, deterministic_search_term,
    phrase_tokens, requested_packages, singular
}

# ---------------------------------------------------------------------------
# Hybrid grocery interpretation.
#
#   raw query -> deterministic package parse (authoritative)
#             -> semantic ProductIntent (by llm, or deterministic)
#             -> grounding + merge with explicit filters -> ResolvedQuery
#
# The LLM only sees the grocery query text and the explicit brand/organic
# filters. It never sees location, credentials, retailer data, or prices.
# ---------------------------------------------------------------------------

glob _LLM_TIMEOUT_SECONDS: float = 20.0;
glob _EXECUTOR: ThreadPoolExecutor = ThreadPoolExecutor(max_workers=2);
glob _INTENT_CACHE: dict[str, ProductIntent] = {};
glob _USAGE: dict[str, int] = {"interpretation_calls": 0, "semantic_match_calls": 0, "semantic_candidates": 0};

# Test seams: a deterministic stand-in for each by-llm function. When set they
# replace the model call entirely (credentials are then not required).
glob _intent_provider: Callable[[str, str], ProductIntent] | None = None;
glob _judge_provider: Callable[[ProductIntent, str, list[SemanticCandidate]], list[SemanticMatchResult]] | None = None;

# ------------------------------- by llm() ----------------------------------

def llm_interpret_grocery_query(query: str, explicit_filters: str) -> ProductIntent by llm(temperature=0.0, max_tokens=400);
sem llm_interpret_grocery_query = "Interpret a shopper's free-text grocery request into a ProductIntent. Capture only what the shopper actually expressed: product identity, explicit brand, variety/flavor, form/cut/container, size class, other descriptors, and explicit exclusions ('not X', 'without X'). Do NOT invent constraints: 'milk' must stay just milk (not organic, not whole). Ignore package quantities and sizes such as '12 count', '2 lb', '1 gallon', '12 pack', '64 fl oz' - they are handled elsewhere. Approximate words like 'around' are not attributes.";
sem llm_interpret_grocery_query.query = "The shopper's grocery request, verbatim.";
sem llm_interpret_grocery_query.explicit_filters = "Explicit filters the shopper set in the form (brand, organic), or 'none'.";

def llm_judge_candidates(intent: ProductIntent, raw_query: str, candidates: list[SemanticCandidate]) -> list[SemanticMatchResult] by llm(temperature=0.0, max_tokens=1500);
sem llm_judge_candidates = "Decide, for EACH candidate retailer listing, whether it is the same product the shopper asked for. Reject listings with a materially different product, variety, flavor, cut, or form, or containing an excluded attribute. A listing may omit words that are implied (e.g. 'Chicken Breast Fillets' are boneless). Unrequested neutral words (brand names, 'Grade A', 'fresh') are fine. Ignore package size entirely. Return exactly one result per candidate, keyed by candidate_id.";
sem llm_judge_candidates.intent = "The interpreted shopper request.";
sem llm_judge_candidates.raw_query = "The shopper's original words.";
sem llm_judge_candidates.candidates = "Listings to judge, each with a stable candidate_id.";

# ----------------------------- configuration -------------------------------

def _load_local_env() {
    import os.path;
    if not os.path.isfile(".env") { return; }
    with open(".env", "r", encoding="utf-8") as env_file {
        for line in env_file {
            stripped = line.strip();
            if stripped == "" or stripped.startswith("#") or "=" not in stripped { continue; }
            pair = stripped.split("=", 1);
            key = pair[0].strip();
            value = pair[1].strip().strip("\"").strip("'");
            if key in ["PRODUCT_INTERPRETER", "LLM_MODEL", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY"] and os.environ.get(key, "") == "" {
                os.environ[key] = value;
            }
        }
    }
}

# Explicit mode selection. Default is deterministic: a key alone never enables
# the LLM. Unknown values are treated as deterministic with a diagnostic.
def:pub selected_interpreter() -> str {
    _load_local_env();
    return os.environ.get("PRODUCT_INTERPRETER", "deterministic").strip().lower() or "deterministic";
}

def:pub configured_model_name() -> str {
    _load_local_env();
    return os.environ.get("LLM_MODEL", "gpt-4o-mini").strip() or "gpt-4o-mini";
}

# Whether a credential for the configured model's provider is present. Never
# returns or logs the value itself.
def:pub model_credential_present() -> bool {
    model = configured_model_name().lower();
    if model.startswith("ollama/") or model.startswith("local:") or model.startswith("mock") { return True; }
    if model.startswith("claude") or model.startswith("anthropic/") { return os.environ.get("ANTHROPIC_API_KEY", "") != ""; }
    if model.startswith("gemini") { return os.environ.get("GEMINI_API_KEY", "") != "" or os.environ.get("GOOGLE_API_KEY", "") != ""; }
    return os.environ.get("OPENAI_API_KEY", "") != "";
}

def:pub set_intent_provider(provider: Callable[[str, str], ProductIntent] | None) { _intent_provider = provider; }
def:pub set_judge_provider(provider: Callable[[ProductIntent, str, list[SemanticCandidate]], list[SemanticMatchResult]] | None) { _judge_provider = provider; }
def:pub clear_interpretation_cache() { _INTENT_CACHE.clear(); }

def:pub usage_snapshot() -> dict[str, int] { return dict(_USAGE); }

def:pub semantic_matching_available() -> bool {
    if _judge_provider is not None { return True; }
    return selected_interpreter() == "llm" and model_credential_present();
}

# ------------------------- deterministic intent ----------------------------

# Generic, vocabulary-free interpretation: product words stay product words,
# "not X" clauses become exclusions, organic only when literally requested.
def:pub interpret_deterministic(query: str, required_brand: str, organic_only: bool) -> ProductIntent {
    (positive, exclusions) = split_exclusions(query);
    tokens = query_product_tokens(query);
    organic_asked = organic_only or "organic" in tokens;
    product = [t for t in tokens if t != "organic"];
    return ProductIntent(
        canonical_product=" ".join(product),
        brand=required_brand.strip(),
        exclusions=exclusions,
        organic=True if organic_asked else None,
        retailer_search_term=deterministic_search_term(query)
    );
}

# ------------------------------ grounding ----------------------------------

def _grounded(phrase: str, query_tokens: list[str]) -> bool {
    tokens = phrase_tokens(phrase);
    if len(tokens) == 0 { return False; }
    for token in tokens {
        if token not in query_tokens { return False; }
    }
    return True;
}

def _dedupe(items: list[str]) -> list[str] {
    seen: list[str] = [];
    for item in items {
        if item != "" and item not in seen { seen.append(item); }
    }
    return seen;
}

# Merge semantic intent with deterministic facts and explicit controls.
# Precedence: explicit UI filters > deterministic packages > grounded intent.
# Descriptors, brand, organic, and exclusions from the LLM are kept only when
# the shopper's own words support them, so the model cannot invent hard
# constraints ("milk" never becomes "organic whole milk").
def:pub resolve_query(
    query: str, intent: ProductIntent, required_brand: str, required_size: str,
    organic_only: bool, source: str
) -> ResolvedQuery {
    (positive, det_exclusions) = split_exclusions(query);
    positive_tokens = phrase_tokens(positive);
    all_query_tokens = phrase_tokens(query);
    packages = requested_packages(query, required_size);
    dropped: list[str] = [];

    if source == "deterministic" or source == "deterministic_fallback" {
        identity = [t for t in query_product_tokens(query) if t != "organic"];
        search_term = deterministic_search_term(query);
        return ResolvedQuery(
            raw_query=query,
            intent=intent,
            packages=packages,
            required_brand=required_brand.strip(),
            organic_required=organic_only or "organic" in positive_tokens,
            identity_terms=identity,
            descriptor_terms=[],
            exclusion_phrases=det_exclusions,
            source=source,
            search_term=search_term if search_term != "" else query
        );
    }

    # Identity: grounded canonical words; ungrounded synonyms remain in the
    # intent for the semantic matcher but are not enforced token-by-token.
    identity: list[str] = [];
    for token in phrase_tokens(intent.canonical_product) {
        if token in positive_tokens and token != "organic" { identity.append(token); }
    }
    if len(identity) == 0 {
        identity = [t for t in query_product_tokens(query) if t != "organic"];
    }

    descriptors: list[str] = [];
    for phrase in [intent.variety, intent.form, intent.size_class] + intent.attributes {
        if phrase.strip() == "" { continue; }
        if _grounded(phrase, positive_tokens) {
            for token in phrase_tokens(phrase) {
                if token not in identity and token != "organic" { descriptors.append(token); }
            }
        } else {
            dropped.append(phrase);
        }
    }

    brand_terms: list[str] = [];
    if intent.brand.strip() != "" {
        if _grounded(intent.brand, positive_tokens) {
            brand_terms = [t for t in phrase_tokens(intent.brand) if t not in identity];
        } else {
            dropped.append("brand:" + intent.brand);
        }
    }

    exclusions = list(det_exclusions);
    for phrase in intent.exclusions {
        if _grounded(phrase, all_query_tokens) {
            exclusions.append(" ".join(phrase_tokens(phrase)));
        } else {
            dropped.append("exclude:" + phrase);
        }
    }

    organic_required = organic_only or "organic" in positive_tokens;
    if intent.organic == True and not organic_required { dropped.append("organic"); }

    grounded_intent = ProductIntent(
        canonical_product=intent.canonical_product,
        brand=intent.brand if len(brand_terms) > 0 or intent.brand.strip() == "" else "",
        variety=intent.variety if intent.variety not in dropped else "",
        form=intent.form if intent.form not in dropped else "",
        size_class=intent.size_class if intent.size_class not in dropped else "",
        attributes=[a for a in intent.attributes if a not in dropped],
        exclusions=_dedupe(exclusions),
        organic=True if organic_required else None,
        retailer_search_term=intent.retailer_search_term,
        semantic_notes=intent.semantic_notes
    );

    # Search term must be free of package text and non-empty; otherwise use
    # the deterministic phrase. The raw query is always kept separately.
    term: str = intent.retailer_search_term.strip();
    if term != "" {
        term = " ".join([t for t in normalize_text(term).split(" ") if t != ""]);
        (_, term_exclusions) = split_exclusions(term);
        if len(term_exclusions) > 0 or len(requested_packages(term, "")) > 0 { term = ""; }
    }
    if term == "" { term = deterministic_search_term(query); }
    if term == "" { term = query; }

    return ResolvedQuery(
        raw_query=query,
        intent=grounded_intent,
        packages=packages,
        required_brand=required_brand.strip(),
        organic_required=organic_required,
        identity_terms=_dedupe(identity),
        descriptor_terms=_dedupe(descriptors + brand_terms),
        exclusion_phrases=_dedupe(exclusions),
        source=source,
        search_term=term,
        dropped_terms=dropped
    );
}

# ------------------------------ entry point --------------------------------

def _explicit_filters_text(required_brand: str, organic_only: bool) -> str {
    parts: list[str] = [];
    if required_brand.strip() != "" { parts.append("brand=" + required_brand.strip()); }
    if organic_only { parts.append("organic=required"); }
    return ", ".join(parts) if len(parts) > 0 else "none";
}

def _call_intent_model(query: str, filters: str) -> ProductIntent {
    if _intent_provider is not None { return _intent_provider(query, filters); }
    future = _EXECUTOR.submit(llm_interpret_grocery_query, query, filters);
    return future.result(timeout=_LLM_TIMEOUT_SECONDS);
}

def _valid_intent(value: any) -> bool {
    return isinstance(value, ProductIntent) and value.canonical_product.strip() != "";
}

# One interpretation per search. Returns a ResolvedQuery whose f"source" says
# honestly where the intent came from and whose f"note" is a sanitized reason
# when the LLM was requested but unavailable.
def:pub interpret_query(query: str, required_brand: str, required_size: str, organic_only: bool) -> ResolvedQuery {
    mode = selected_interpreter();
    det_intent = interpret_deterministic(query, required_brand, organic_only);
    use_llm = mode == "llm" or _intent_provider is not None;
    if not use_llm {
        resolved = resolve_query(query, det_intent, required_brand, required_size, organic_only, "deterministic");
        if mode != "deterministic" {
            resolved.note = "Unknown PRODUCT_INTERPRETER value; using deterministic interpretation.";
        }
        return resolved;
    }

    if _intent_provider is None and not model_credential_present() {
        resolved = resolve_query(query, det_intent, required_brand, required_size, organic_only, "deterministic_fallback");
        resolved.note = "Semantic interpretation unavailable: no model credential configured. Using deterministic matching.";
        return resolved;
    }

    filters = _explicit_filters_text(required_brand, organic_only);
    cache_key = normalize_text(query) + "|" + filters;
    if cache_key in _INTENT_CACHE {
        return resolve_query(query, _INTENT_CACHE[cache_key], required_brand, required_size, organic_only, "llm_cached");
    }

    calls: int = 0;
    try {
        _USAGE["interpretation_calls"] = _USAGE["interpretation_calls"] + 1;
        calls = 1;
        intent = _call_intent_model(query, filters);
        if not _valid_intent(intent) {
            raise ValueError("invalid intent");
        }
        _INTENT_CACHE[cache_key] = intent;
        resolved = resolve_query(query, intent, required_brand, required_size, organic_only, "llm");
        resolved.interpretation_calls = calls;
        return resolved;
    } except Exception {
        resolved = resolve_query(query, det_intent, required_brand, required_size, organic_only, "deterministic_fallback");
        resolved.note = "Semantic interpretation unavailable: the model request failed, timed out, or returned invalid output. Using deterministic matching.";
        resolved.interpretation_calls = calls;
        return resolved;
    }
}

# One batched semantic review for all ambiguous candidates of a search.
# Returns decisions keyed by candidate_id; missing ids mean "no decision".
def:pub judge_candidates(resolved: ResolvedQuery, candidates: list[SemanticCandidate]) -> dict[str, SemanticMatchResult] {
    decisions: dict[str, SemanticMatchResult] = {};
    if len(candidates) == 0 { return decisions; }
    _USAGE["semantic_match_calls"] = _USAGE["semantic_match_calls"] + 1;
    _USAGE["semantic_candidates"] = _USAGE["semantic_candidates"] + len(candidates);
    results: list[SemanticMatchResult] = [];
    if _judge_provider is not None {
        results = _judge_provider(resolved.intent, resolved.raw_query, candidates);
    } else {
        future = _EXECUTOR.submit(llm_judge_candidates, resolved.intent, resolved.raw_query, candidates);
        results = future.result(timeout=_LLM_TIMEOUT_SECONDS);
    }
    valid_ids = [c.candidate_id for c in candidates];
    for result in results {
        if isinstance(result, SemanticMatchResult) and result.candidate_id in valid_ids {
            decisions[result.candidate_id] = result;
        }
    }
    return decisions;
}

def:pub describe_resolved(resolved: ResolvedQuery) -> str {
    parts: list[str] = ["product=" + " ".join(resolved.identity_terms)];
    if len(resolved.descriptor_terms) > 0 { parts.append("descriptors=" + ", ".join(resolved.descriptor_terms)); }
    if len(resolved.exclusion_phrases) > 0 { parts.append("excluding=" + ", ".join(resolved.exclusion_phrases)); }
    if resolved.organic_required { parts.append("organic"); }
    for pkg in resolved.packages {
        parts.append(("~" if pkg.approximate else "") + str(pkg.quantity) + " " + pkg.unit);
    }
    return "; ".join(parts);
}
