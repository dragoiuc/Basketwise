import from services.basketwiseTypes {
    SearchRequest, SearchResponse, SearchDiagnostics, GroceryResult, CompareMode, StockStatus,
    PriceType, GeoPoint, Store, RawListing, ResolvedQuery, MatchDecision, SemanticCandidate, SemanticMatchResult
}
import from services.locationProvider { geocode, discover_stores, selected_data_provider }
import from services.retailerAdapters { get_adapter, search_store }
import from services.productMatching { match_resolved, parse_package }
import from services.productInterpreter { interpret_query, judge_candidates, semantic_matching_available, describe_resolved }
import from services.priceSelection { select_effective_price }
import from services.unitConversion { compute_unit_price, convert_to_base_unit, dimension_for_unit }

# Pipeline:
#   free-text query -> semantic interpretation (once) -> retailer retrieval
#   -> hybrid product match (deterministic first, one batched semantic call
#   for ambiguous candidates) -> deterministic package validation
#   -> deterministic stock/price eligibility -> unit normalization -> ranking.
# The LLM never decides price, eligibility, units, stock, radius, or order.

glob SEMANTIC_CANDIDATE_CAP: int = 25;

def:pub parse_request_bool(value: str | bool | int) -> bool {
    normalized = str(value).strip().lower();
    return normalized == "true" or normalized == "1";
}

def _sort_key_checkout(result: GroceryResult) -> float { return result.effective_price; }
def _sort_key_unit(result: GroceryResult) -> float {
    if result.unit_price < 0.0 { return 999999999.0; }
    return result.unit_price;
}

def _dimension_for_result(result: GroceryResult) -> str {
    dimension = dimension_for_unit(result.normalized_unit);
    return "" if dimension == "unknown" else dimension;
}

def _expected_dimension(resolved: ResolvedQuery) -> str {
    # Prefer the explicit advanced size for the ranking dimension; matching
    # still enforces every package constraint.
    ordered = [p for p in resolved.packages if p.source == "required_size"] + [p for p in resolved.packages if p.source != "required_size"];
    for pkg in ordered {
        normalized = convert_to_base_unit(pkg.quantity, pkg.unit);
        if normalized is not None { return normalized.dimension; }
    }
    return "";
}

def _dominant_dimension(results: list[GroceryResult]) -> str {
    count_n: int = 0;
    mass_n: int = 0;
    volume_n: int = 0;
    for result in results {
        if result.unit_price < 0.0 { continue; }
        dimension = _dimension_for_result(result);
        if dimension == "count" { count_n += 1; }
        elif dimension == "mass" { mass_n += 1; }
        elif dimension == "volume" { volume_n += 1; }
    }
    if count_n == 0 and mass_n == 0 and volume_n == 0 { return ""; }
    if count_n >= mass_n and count_n >= volume_n { return "count"; }
    if mass_n >= volume_n { return "mass"; }
    return "volume";
}

def:pub price_type_label(price_type: PriceType) -> str {
    if price_type == PriceType.SALE { return "Sale"; }
    if price_type == PriceType.MEMBER { return "Member price"; }
    if price_type == PriceType.COUPON { return "Coupon price"; }
    return "Regular price";
}

def _build_result(store: Store, listing: RawListing, decision: MatchDecision, request: SearchRequest) -> GroceryResult {
    (effective_price, price_type) = select_effective_price(listing, request);
    unit_price = compute_unit_price(effective_price, decision.normalized_quantity);
    return GroceryResult(
        store=store,
        product_name=listing.product_name,
        brand=listing.brand,
        size_text=listing.size_text,
        effective_price=effective_price,
        price_type=price_type,
        stock_status=listing.stock_status,
        product_url=listing.product_url,
        observed_at=listing.observed_at,
        match_confidence=decision.confidence,
        match_reason=decision.reason,
        source=listing.source,
        normalized_quantity=decision.normalized_quantity,
        normalized_unit=decision.normalized_unit,
        unit_price=unit_price,
        is_demo_data=(store.chain_key == "mock"),
        price_label=price_type_label(price_type),
        is_regular_price=(price_type == PriceType.REGULAR),
        in_stock=(listing.stock_status == StockStatus.IN_STOCK),
        distance_label=("%.1f mi" % store.distance_miles) if store.distance_miles is not None else "Distance not provided",
        price_display="$%.2f" % effective_price,
        unit_price_display=("$%.3f / %s" % (unit_price, decision.normalized_unit)) if unit_price >= 0.0 else "",
        confidence_display="Match confidence %.0f percent" % (decision.confidence * 100.0)
    );
}

# Fetch a store's listings using the interpreted search term. If that term
# returns nothing while differing from the original query, retry once with the
# original query so semantic term generation can never reduce recall to zero.
def _fetch_listings(store: Store, request: SearchRequest, resolved: ResolvedQuery, diagnostics: SearchDiagnostics) -> list[RawListing] {
    term = resolved.search_term.strip();
    request.search_term = term;
    listings = search_store(store, request);
    if len(listings) == 0 and term != "" and term != request.query.strip() {
        request.search_term = request.query;
        listings = search_store(store, request);
        diagnostics.search_term_fallbacks += 1;
    }
    request.search_term = term;
    return listings;
}

def:pub search_groceries(
    query: str,
    location_text: str,
    radius_miles: float = 10.0,
    required_brand: str = "",
    required_size: str = "",
    organic_only: bool = False,
    compare_mode: str = "checkout",
    include_membership_prices: bool = False,
    include_coupons: bool = False,
    quantity: int = 1,
    max_results: int = 20
) -> SearchResponse {
    organic_flag = parse_request_bool(organic_only);
    member_flag = parse_request_bool(include_membership_prices);
    coupon_flag = parse_request_bool(include_coupons);
    mode = CompareMode.UNIT_PRICE if compare_mode == "unit" else CompareMode.CHECKOUT_PRICE;
    request = SearchRequest(
        query=query,
        location_text=location_text,
        radius_miles=radius_miles,
        required_brand=required_brand,
        required_size=required_size,
        organic_only=organic_flag,
        compare_mode=mode,
        include_membership_prices=member_flag,
        include_coupons=coupon_flag,
        quantity=int(quantity),
        max_results=int(max_results)
    );
    diagnostics = SearchDiagnostics();
    if request.query.strip() == "" {
        return SearchResponse(query=request.query, location_text=request.location_text, diagnostics=diagnostics, validation_error="Product query is required.");
    }
    if request.location_text.strip() == "" {
        return SearchResponse(query=request.query, location_text=request.location_text, diagnostics=diagnostics, validation_error="Location is required.");
    }

    radius = float(request.radius_miles);
    if radius <= 0.0 { radius = 10.0; }
    if radius > 50.0 { radius = 50.0; }
    result_limit = int(request.max_results);
    if result_limit <= 0 { result_limit = 20; }
    if result_limit > 100 { result_limit = 100; }

    center: GeoPoint | None = None;
    stores: list[Store] = [];
    try {
        if selected_data_provider() == "mock" {
            center = geocode(request.location_text);
        } elif len(request.location_text.strip()) == 5 and request.location_text.strip().isdigit() {
            center = None;
        } else {
            raise Exception("Kroger live search requires a five-digit ZIP code as the location.");
        }
        stores = discover_stores(request.location_text, center, radius);
    } except Exception as e {
        provider_error = str(e);
        if provider_error.startswith("GROCERY_DATA_PROVIDER=") or provider_error.startswith("Unsupported GROCERY_DATA_PROVIDER") or provider_error.startswith("Kroger live search requires") or provider_error.startswith("Kroger credentials are missing") or provider_error.startswith("Kroger authentication") {
            diagnostics.errors.append(provider_error);
            return SearchResponse(query=request.query, location_text=request.location_text, diagnostics=diagnostics, validation_error="Location provider configuration error: " + provider_error);
        }
        diagnostics.errors.append("Location provider failed.");
        return SearchResponse(query=request.query, location_text=request.location_text, diagnostics=diagnostics, validation_error="Location service is unavailable. Check the location provider configuration.");
    }
    diagnostics.stores_discovered = len(stores);

    # One semantic interpretation per search (cached per normalized query).
    resolved = interpret_query(request.query, request.required_brand, request.required_size, request.organic_only);
    diagnostics.interpretation_source = resolved.source;
    diagnostics.interpretation_calls = resolved.interpretation_calls;
    diagnostics.search_term = resolved.search_term;
    diagnostics.interpretation_summary = describe_resolved(resolved);
    if resolved.note != "" { diagnostics.warnings.append(resolved.note); }

    accepted: list[GroceryResult] = [];
    pending: list[tuple[Store, RawListing, MatchDecision]] = [];
    rejection_reasons: list[str] = [];

    for store in stores {
        adapter = get_adapter(store.chain_key);
        if adapter is None {
            diagnostics.unsupported_stores += 1;
            diagnostics.warnings.append(f"{store.name}: retailer '{store.chain_key}' is not supported.");
            continue;
        }

        listings: list[RawListing] = [];
        try {
            listings = _fetch_listings(store, request, resolved, diagnostics);
            diagnostics.stores_searched += 1;
        } except Exception {
            diagnostics.errors.append(f"{store.name}: retailer adapter failed.");
            continue;
        }

        for listing in listings {
            diagnostics.listings_seen += 1;
            if listing.stock_status != StockStatus.IN_STOCK or listing.regular_price < 0.0 {
                diagnostics.listings_rejected += 1;
                continue;
            }
            decision = match_resolved(resolved, listing);
            if decision.is_match {
                accepted.append(_build_result(store, listing, decision, request));
                diagnostics.listings_accepted += 1;
            } elif decision.needs_semantic_review {
                pending.append((store, listing, decision));
            } else {
                diagnostics.listings_rejected += 1;
                if decision.reason not in rejection_reasons { rejection_reasons.append(decision.reason); }
            }
        }
    }

    # Ambiguous candidates: one batched semantic call, capped and keyed by id.
    if len(pending) > 0 {
        decisions: dict[str, SemanticMatchResult] = {};
        reviewed = pending[:SEMANTIC_CANDIDATE_CAP];
        if semantic_matching_available() {
            candidates: list[SemanticCandidate] = [];
            idx: int = 0;
            for (store, listing, _) in reviewed {
                candidates.append(SemanticCandidate(candidate_id="c" + str(idx), product_name=listing.product_name, brand=listing.brand, size_text=listing.size_text));
                idx += 1;
            }
            try {
                decisions = judge_candidates(resolved, candidates);
                diagnostics.semantic_match_calls = 1;
                diagnostics.semantic_candidates_evaluated = len(candidates);
            } except Exception {
                diagnostics.warnings.append("Semantic candidate review unavailable; ambiguous listings were rejected.");
            }
        }
        idx2: int = 0;
        for (store, listing, decision) in pending {
            key = "c" + str(idx2);
            idx2 += 1;
            verdict: SemanticMatchResult | None = decisions[key] if key in decisions else None;
            if verdict is not None and verdict.is_semantic_match {
                decision.is_match = True;
                decision.reason = "Semantic match: " + str(verdict.reason);
                accepted.append(_build_result(store, listing, decision, request));
                diagnostics.listings_accepted += 1;
            } else {
                diagnostics.listings_rejected += 1;
                reason: str = decision.reason;
                if verdict is not None { reason = "Semantic review rejected: " + str(verdict.reason); }
                if reason not in rejection_reasons { rejection_reasons.append(reason); }
            }
        }
    }
    for reason in rejection_reasons[:4] { diagnostics.warnings.append(reason); }

    ranked: list[GroceryResult] = [];
    if request.compare_mode == CompareMode.UNIT_PRICE {
        expected = _expected_dimension(resolved);
        if expected == "" { expected = _dominant_dimension(accepted); }
        compatible: list[GroceryResult] = [];
        incompatible: list[GroceryResult] = [];
        for result in accepted {
            if result.unit_price >= 0.0 and expected != "" and _dimension_for_result(result) == expected {
                compatible.append(result);
            } else {
                incompatible.append(result);
            }
        }
        compatible = sorted(compatible, key=_sort_key_unit);
        incompatible = sorted(incompatible, key=_sort_key_checkout);
        ranked = compatible + incompatible;
    } else {
        ranked = sorted(accepted, key=_sort_key_checkout);
    }
    ranked = ranked[:result_limit];

    return SearchResponse(
        query=request.query,
        location_text=request.location_text,
        resolved_location=center,
        results=ranked,
        diagnostics=diagnostics,
        is_demo_data=(len(ranked) > 0 and all([r.is_demo_data for r in ranked]))
    );
}
