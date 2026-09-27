import from services.basketwiseTypes { RawListing, SearchRequest, MatchDecision, ResolvedQuery, PackageConstraint }
import from services.unitConversion { convert_to_base_unit }
import from services.groceryText {
    normalize_text, listing_tokens, contains_phrase, parse_pack_count, split_exclusions,
    parse_package as _parse_package_text
}

# Hybrid candidate matching. Order of evaluation:
#   1. deterministic hard rejections (brand, organic, explicit exclusions,
#      legacy variety safety rules, package quantity/dimension)
#   2. obvious deterministic positive (every required product term present)
#   3. partial product-term coverage -> needs_semantic_review (the coordinator
#      batches these into one semantic call when semantic mode is active;
#      otherwise they are rejected conservatively)
# Package text never boosts product-term coverage.

def:pub parse_package(text: str) -> tuple[float, str] {
    return _parse_package_text(text);
}

# Deterministic ResolvedQuery for callers that have only a SearchRequest.
def:pub deterministic_resolution(request: SearchRequest) -> ResolvedQuery {
    # Imported lazily: the server module loader otherwise sees a cycle.
    import from services.productInterpreter { interpret_deterministic, resolve_query }
    intent = interpret_deterministic(request.query, request.required_brand, request.organic_only);
    return resolve_query(request.query, intent, request.required_brand, request.required_size, request.organic_only, "deterministic");
}

def:pub package_matches(want: PackageConstraint, found_qty: float, found_unit: str, listing_size_text: str) -> bool {
    wanted = convert_to_base_unit(want.quantity, want.unit);
    found = convert_to_base_unit(found_qty, found_unit);
    if wanted is None or found is None {
        return False;
    }
    if wanted.dimension == "count" and found.dimension != "count" {
        # "12 pack" vs "12 x 12 fl oz": compare container counts exactly.
        packs = parse_pack_count(listing_size_text);
        return packs > 0.0 and abs(packs - wanted.quantity) < 0.001;
    }
    if wanted.dimension != found.dimension {
        return False;
    }
    if wanted.dimension == "count" {
        return abs(wanted.quantity - found.quantity) < 0.001;
    }
    # Exact requests allow 5% for label rounding; "around 1 lb" allows 15%.
    ratio = 0.15 if want.approximate else 0.05;
    tolerance = max(wanted.quantity * ratio, 0.001);
    return abs(wanted.quantity - found.quantity) <= tolerance;
}

def _reject(coverage: float, reason: str) -> MatchDecision {
    return MatchDecision(is_match=False, confidence=coverage, reason=reason);
}

# Legacy deterministic safety rules. Retained because tests show they catch
# real substitutions even when an LLM is unavailable; new concepts are handled
# generically through ResolvedQuery terms and exclusions instead of new lists.
def _legacy_variety_conflict(query_norm: str, title_norm: str) -> str {
    variant_terms: list[str] = [
        "honey nut", "chocolate", "almond", "powdered", "whole",
        "2 percent", "1 percent", "skim", "extra large", "jumbo"
    ];
    listing_only_variants: list[str] = ["honey nut", "chocolate", "almond", "powdered", "jumbo"];
    for variant in variant_terms {
        if variant in query_norm and variant not in title_norm {
            return "Listing variant differs from the requested product.";
        }
        if variant in title_norm and variant not in query_norm and variant in listing_only_variants {
            return "Listing has a different product variety.";
        }
    }
    if "egg" in query_norm {
        requested_class = _egg_class(query_norm);
        listed_class = _egg_class(title_norm);
        if requested_class != "" and listed_class != "" and requested_class != listed_class {
            return "Egg size class differs from the requested product.";
        }
    }
    return "";
}

def _egg_class(text: str) -> str {
    if "extra large" in text { return "extra large"; }
    if "jumbo" in text { return "jumbo"; }
    if "large" in text { return "large"; }
    if "medium" in text { return "medium"; }
    if "small" in text { return "small"; }
    return "";
}

# A term is present as a whole token, or as the head/tail of a retailer
# compound word ("almondmilk" contains "almond" and "milk"). Short terms
# (under 4 chars) must match whole tokens to avoid "egg" in "eggplant".
def _term_present(term: str, listed: list[str]) -> bool {
    if term in listed { return True; }
    if len(term) < 4 { return False; }
    for token in listed {
        if len(token) > len(term) + 2 and (token.startswith(term) or token.endswith(term)) { return True; }
    }
    return False;
}

def:pub match_resolved(resolved: ResolvedQuery, listing: RawListing) -> MatchDecision {
    listing_text = listing.product_name + " " + listing.brand;
    listed = listing_tokens(listing_text);
    required: list[str] = [];
    for term in resolved.identity_terms + resolved.descriptor_terms {
        if term not in required { required.append(term); }
    }
    matched = [t for t in required if _term_present(t, listed)];
    missing = [t for t in required if not _term_present(t, listed)];
    coverage = len(matched) / len(required) if len(required) > 0 else 0.0;
    identity_hits = [t for t in resolved.identity_terms if _term_present(t, listed)];

    # Bounded pre-filter: listings sharing no product identity term are never
    # considered, not even semantically.
    if len(identity_hits) == 0 or coverage < 0.34 {
        return _reject(coverage, "Product terms do not match the listing.");
    }

    if resolved.required_brand != "" {
        if normalize_text(resolved.required_brand) not in normalize_text(listing.brand) {
            return _reject(coverage, "Required brand does not match.");
        }
    }
    if resolved.organic_required and "organic" not in listed {
        return _reject(coverage, "Organic was required but is not stated in the listing.");
    }
    for phrase in resolved.exclusion_phrases {
        if contains_phrase(listing_text, phrase) {
            return _reject(coverage, "Listing contains an excluded attribute (" + phrase + ").");
        }
    }

    # Legacy rules see only the positive part of the query, so "not honey nut"
    # is never mistaken for a request FOR honey nut.
    (positive_query, _) = split_exclusions(resolved.raw_query);
    legacy = _legacy_variety_conflict(normalize_text(positive_query), normalize_text(listing.product_name));
    if legacy != "" {
        return _reject(coverage, legacy);
    }

    found_qty: float = 0.0;
    found_unit: str = "";
    if listing.size_text.strip() != "" {
        (found_qty, found_unit) = _parse_package_text(listing.size_text);
    }
    found_norm = convert_to_base_unit(found_qty, found_unit) if found_unit != "" else None;
    if len(resolved.packages) > 0 {
        if found_norm is None {
            return _reject(coverage, "Could not verify the listing package size.");
        }
        for want in resolved.packages {
            if not package_matches(want, found_qty, found_unit, listing.size_text) {
                return _reject(coverage, "Package size or measurement dimension differs from the requested size.");
            }
        }
    }

    base = MatchDecision(
        is_match=True,
        confidence=min(1.0, coverage),
        normalized_name=listing.product_name,
        normalized_quantity=found_norm.quantity if found_norm is not None else 0.0,
        normalized_unit=found_norm.unit if found_norm is not None else "",
        reason="Product terms match and all requested package constraints are satisfied."
    );
    if len(missing) == 0 {
        return base;
    }
    # Hard constraints passed but product identity is not verifiable from the
    # words alone. Not a match unless a semantic review accepts it.
    base.is_match = False;
    base.needs_semantic_review = True;
    base.missing_terms = missing;
    base.reason = "Listing does not state requested product terms: " + ", ".join(missing) + ".";
    return base;
}

# Backwards-compatible deterministic entry point.
def:pub match_listing(request: SearchRequest, listing: RawListing) -> MatchDecision {
    return match_resolved(deterministic_resolution(request), listing);
}
