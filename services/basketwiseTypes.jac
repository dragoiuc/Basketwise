"""Shared typed domain objects for the Basketwise grocery search backend.

These objects cross the client/server wire directly (see jac-fullstack-patterns):
server functions return them, and the client receives hydrated typed instances.
"""

enum CompareMode {
    CHECKOUT_PRICE,
    UNIT_PRICE
}

enum PriceType {
    REGULAR,
    SALE,
    MEMBER,
    COUPON
}

enum StockStatus {
    IN_STOCK,
    OUT_OF_STOCK,
    UNKNOWN
}

obj SearchRequest {
    has query: str;
    has location_text: str;
    has radius_miles: float = 10.0;

    has quantity: int = 1;
    has required_brand: str = "";
    has required_size: str = "";
    has organic_only: bool = False;

    has compare_mode: CompareMode = CompareMode.CHECKOUT_PRICE;

    has include_membership_prices: bool = False;
    has include_coupons: bool = False;

    has max_results: int = 20;

    # Retailer-facing search term. Empty means "use query". Set by the
    # coordinator from the resolved ProductIntent; the raw query is kept.
    has search_term: str = "";
}

# ---------------------------------------------------------------------------
# Semantic grocery interpretation (server-side only).
#
# ProductIntent describes WHAT the user wants. It never carries price,
# inventory, unit price, retailer, ranking, or package quantities: explicit
# package constraints are parsed deterministically into PackageConstraint.
# ---------------------------------------------------------------------------

obj ProductIntent {
    has canonical_product: str = "";
    has brand: str = "";
    has variety: str = "";
    has form: str = "";
    has size_class: str = "";
    has attributes: list[str] = [];
    has exclusions: list[str] = [];
    has organic: bool | None = None;
    has retailer_search_term: str = "";
    has semantic_notes: str = "";
}

sem ProductIntent = "The grocery product a shopper is asking for, described by meaning only. Never includes price, store, stock, ranking, or package quantity/size.";
sem ProductIntent.canonical_product = "Short generic product identity in lowercase, using the shopper's own words where possible, e.g. 'eggs', 'chicken breast', 'almond milk', 'greek yogurt', 'cheerios', 'coke zero'. Keep branded product names (Cheerios, Coke Zero) when they ARE the product.";
sem ProductIntent.brand = "Brand only if the shopper explicitly named one, else empty string. Never guess a brand.";
sem ProductIntent.variety = "Flavor/variety/type explicitly requested (e.g. 'whole', 'strawberry', 'vanilla', '90/10'), else empty string. Words like 'regular' or 'original' mean the default variety: leave empty.";
sem ProductIntent.form = "Physical form/cut/container explicitly requested (e.g. 'boneless skinless', 'ground', 'cans', 'shredded', 'frozen'), else empty string.";
sem ProductIntent.size_class = "Grade or size class that is part of the product identity (e.g. 'large' for eggs, 'baby' for spinach), not a package quantity. Empty if not stated.";
sem ProductIntent.attributes = "Other explicitly requested descriptors (dietary, preparation, nutrition), e.g. ['unsweetened'], ['low sodium'], ['gluten free']. Only words the shopper actually expressed. Empty list if none.";
sem ProductIntent.exclusions = "Things the shopper explicitly does NOT want, e.g. 'not honey nut' -> ['honey nut']. Empty list if none.";
sem ProductIntent.organic = "true only if the shopper asked for organic; null if organic was not mentioned. Never infer organic.";
sem ProductIntent.retailer_search_term = "Concise catalog search phrase (2-5 words) for retailer product search, WITHOUT package quantities or sizes, e.g. 'large eggs', 'honey nut free cheerios' is wrong; use 'cheerios'.";
sem ProductIntent.semantic_notes = "Optional one-line note about ambiguity (e.g. 'approximate weight requested'). Empty if nothing notable.";

# A deterministically parsed package requirement. approximate=True means the
# shopper said 'around'/'about'/'~', so a wider tolerance is applied.
obj PackageConstraint {
    has quantity: float;
    has unit: str;
    has approximate: bool = False;
    has source: str = "query";
}

# The single resolved representation used by matching. Precedence:
# explicit UI filters > deterministic package parse > grounded semantic intent.
obj ResolvedQuery {
    has raw_query: str;
    has intent: ProductIntent = ProductIntent();
    has packages: list[PackageConstraint] = [];

    # Hard constraints from explicit controls.
    has required_brand: str = "";
    has organic_required: bool = False;

    # Grounded matching terms derived from the intent.
    has identity_terms: list[str] = [];
    has descriptor_terms: list[str] = [];
    has exclusion_phrases: list[str] = [];

    # "deterministic" | "llm" | "llm_cached" | "deterministic_fallback"
    has source: str = "deterministic";
    has search_term: str = "";
    has dropped_terms: list[str] = [];
    has note: str = "";
    has interpretation_calls: int = 0;
}

obj SemanticCandidate {
    has candidate_id: str;
    has product_name: str;
    has brand: str = "";
    has size_text: str = "";
}

sem SemanticCandidate = "A retailer listing to judge. Package size is shown for context only; package size is verified separately and must not affect the decision.";
sem SemanticCandidate.candidate_id = "Stable id; copy it exactly into the result.";

obj SemanticMatchResult {
    has candidate_id: str;
    has is_semantic_match: bool;
    has reason: str = "";
}

sem SemanticMatchResult = "Decision for one candidate listing.";
sem SemanticMatchResult.candidate_id = "The candidate_id of the listing being judged, copied exactly.";
sem SemanticMatchResult.is_semantic_match = "true if the listing is the same kind of product the shopper asked for, with no materially different variety, flavor, cut, form, or excluded attribute; false otherwise.";
sem SemanticMatchResult.reason = "Very short justification (under 15 words).";

obj GeoPoint {
    has latitude: float;
    has longitude: float;
}

obj Store {
    has store_id: str;
    has chain_key: str;
    has name: str;
    has address: str;

    has latitude: float;
    has longitude: float;
    has distance_miles: float | None = None;
}

obj RawListing {
    has store_id: str;
    has source: str;
    has product_name: str;
    has regular_price: float;

    has brand: str = "";
    has size_text: str = "";
    has sale_price: float = -1.0;
    has member_price: float = -1.0;
    has coupon_price: float = -1.0;
    has stock_status: StockStatus = StockStatus.IN_STOCK;
    has product_url: str = "";
    has observed_at: str = "";
}

obj MatchDecision {
    has is_match: bool;
    has confidence: float;

    has normalized_name: str = "";

    # Quantity after parsing/conversion, e.g. 1 gallon -> 128 "fl_oz".
    has normalized_quantity: float = 0.0;
    has normalized_unit: str = "";

    has reason: str = "";

    # Hybrid matching: hard constraints passed but product identity could not
    # be verified deterministically, so a batched semantic review may decide.
    has needs_semantic_review: bool = False;
    has missing_terms: list[str] = [];
}

obj GroceryResult {
    has store: Store;
    has product_name: str;
    has brand: str;
    has size_text: str;
    has effective_price: float;
    has price_type: PriceType;
    has stock_status: StockStatus;
    has product_url: str;
    has observed_at: str;
    has match_confidence: float;
    has match_reason: str;
    has source: str;

    has normalized_quantity: float = 0.0;
    has normalized_unit: str = "";
    has unit_price: float = -1.0;
    has is_demo_data: bool = False;

    # Browser-safe projections of the server-side enums. The client renders
    # these plain values and never references PriceType/StockStatus.
    has price_label: str = "Regular price";
    has is_regular_price: bool = True;
    has in_stock: bool = True;
    has distance_label: str = "";
    has price_display: str = "";
    has unit_price_display: str = "";
    has confidence_display: str = "";
}

obj SearchDiagnostics {
    has stores_discovered: int = 0;
    has stores_searched: int = 0;
    has unsupported_stores: int = 0;

    has listings_seen: int = 0;
    has listings_rejected: int = 0;
    has listings_accepted: int = 0;

    has errors: list[str] = [];
    has warnings: list[str] = [];

    # Semantic interpretation diagnostics (sanitized: no prompts, no keys).
    # interpretation_source: "deterministic" | "llm" | "llm_cached" |
    # "deterministic_fallback".
    has interpretation_source: str = "deterministic";
    has interpretation_summary: str = "";
    has search_term: str = "";
    has search_term_fallbacks: int = 0;
    has interpretation_calls: int = 0;
    has semantic_match_calls: int = 0;
    has semantic_candidates_evaluated: int = 0;
}

obj SearchResponse {
    has query: str;
    has location_text: str;

    has resolved_location: GeoPoint | None = None;

    has results: list[GroceryResult] = [];
    has diagnostics: SearchDiagnostics = SearchDiagnostics();

    has is_demo_data: bool = False;
    has validation_error: str = "";
}
