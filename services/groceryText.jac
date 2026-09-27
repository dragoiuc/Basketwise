import re;
import from services.basketwiseTypes { PackageConstraint }

# Deterministic grocery text utilities shared by interpretation and matching.
# Everything here is exact, explainable code: normalization, tokenization,
# explicit exclusion clauses ("not X"), and package parsing. No product-specific
# vocabulary lives here beyond package units and grammatical filler words.

glob PACKAGE_WORDS: list[str] = [
    "count", "counts", "ct", "dozen", "dozens", "pack", "packs", "pk", "each",
    "oz", "ounce", "ounces", "fl", "fluid", "lb", "lbs", "pound", "pounds",
    "g", "gram", "grams", "kg", "kilogram", "kilograms",
    "gallon", "gallons", "gal", "gals", "quart", "quarts", "qt",
    "pint", "pints", "pt", "ml", "milliliter", "milliliters",
    "liter", "liters", "litre", "litres", "l", "x"
];

# Grammatical filler plus words that denote the default variety.
glob FILLER_WORDS: list[str] = [
    "a", "an", "the", "of", "and", "with", "for", "some", "please",
    "regular", "original", "classic"
];

glob APPROX_WORDS: list[str] = ["around", "about", "approx", "approximately", "roughly", "nearly"];

# "no" is deliberately absent: "no salt added" is a requested attribute.
glob EXCLUSION_MARKERS: list[str] = ["not", "without", "except", "excluding"];

def:pub normalize_text(text: str) -> str {
    lowered: str = text.lower().replace("~", " around ").replace("%", " percent ").replace("_", " ");
    lowered = re.sub(r"(?<=\d)x(?=\d)", " x ", lowered);
    lowered = re.sub(r"[^a-z0-9.]+", " ", lowered);
    lowered = re.sub(r"(?<![0-9])\.|\.(?![0-9])", " ", lowered);
    return re.sub(r"\s+", " ", lowered).strip();
}

def:pub singular(token: str) -> str {
    # Conservative English singularization for grocery search tokens only.
    if len(token) > 4 and token.endswith("ies") {
        return token[:-3] + "y";
    }
    if (
        len(token) > 3
        and token.endswith("s")
        and not token.endswith("ss")
        and not token.endswith("us")
        and not token.endswith("is")
    ) {
        return token[:-1];
    }
    return token;
}

def _is_number(token: str) -> bool {
    return token.replace(".", "", 1).isdigit();
}

# Split a query into its positive text and explicit exclusion phrases.
# "regular cheerios not honey nut 18 oz" -> ("regular cheerios 18 oz", ["honey nut"]).
def:pub split_exclusions(text: str) -> tuple[str, list[str]] {
    tokens = normalize_text(text).split(" ");
    positive: list[str] = [];
    exclusions: list[str] = [];
    current: list[str] = [];
    in_exclusion: bool = False;
    for token in tokens {
        if token == "" { continue; }
        if token in EXCLUSION_MARKERS {
            if in_exclusion and len(current) > 0 { exclusions.append(" ".join(current)); }
            current = [];
            in_exclusion = True;
            continue;
        }
        if in_exclusion {
            ends_clause = _is_number(token) or token in PACKAGE_WORDS or token in APPROX_WORDS or len(current) >= 4;
            if not ends_clause {
                if token not in FILLER_WORDS { current.append(singular(token)); }
                continue;
            }
            if len(current) > 0 { exclusions.append(" ".join(current)); }
            current = [];
            in_exclusion = False;
        }
        positive.append(token);
    }
    if in_exclusion and len(current) > 0 { exclusions.append(" ".join(current)); }
    return (" ".join(positive), exclusions);
}

def _meaning_tokens(normalized: str, singularize: bool) -> list[str] {
    kept: list[str] = [];
    for token in normalized.split(" ") {
        if token == "" or token in PACKAGE_WORDS or token in FILLER_WORDS or token in APPROX_WORDS {
            continue;
        }
        if _is_number(token) { continue; }
        kept.append(singular(token) if singularize else token);
    }
    return kept;
}

# Product-meaning tokens of a shopper query (exclusion clauses removed).
def:pub query_product_tokens(query: str) -> list[str] {
    (positive, _) = split_exclusions(query);
    return _meaning_tokens(positive, True);
}

# Deterministic retailer search phrase: the positive query without package text.
def:pub deterministic_search_term(query: str) -> str {
    (positive, _) = split_exclusions(query);
    return " ".join(_meaning_tokens(positive, False));
}

# Token set used for listing-side membership checks (no exclusion parsing).
def:pub listing_tokens(text: str) -> list[str] {
    return [singular(t) for t in normalize_text(text).split(" ") if t != ""];
}

# Singularized, normalized key of a phrase, for token-level comparisons.
def:pub phrase_tokens(text: str) -> list[str] {
    return [singular(t) for t in normalize_text(text).split(" ") if t != "" and t not in FILLER_WORDS];
}

def:pub contains_phrase(haystack: str, phrase: str) -> bool {
    hay_tokens = phrase_tokens(haystack);
    needle = phrase_tokens(phrase);
    if len(needle) == 0 { return False; }
    hay = " " + " ".join(hay_tokens) + " ";
    return (" " + " ".join(needle) + " ") in hay;
}

def:pub is_approximate(text: str) -> bool {
    for token in normalize_text(text).split(" ") {
        if token in APPROX_WORDS { return True; }
    }
    return False;
}

def:pub canonical_package_unit(unit: str) -> str {
    normalized = normalize_text(unit);
    if normalized in ["ct", "count", "counts", "pack", "packs", "pk", "each"] { return "count"; }
    if normalized in ["fl oz", "fluid ounce", "fluid ounces"] { return "fl_oz"; }
    if normalized in ["oz", "ounce", "ounces"] { return "oz"; }
    if normalized in ["lb", "lbs", "pound", "pounds"] { return "lb"; }
    if normalized in ["g", "gram", "grams"] { return "g"; }
    if normalized in ["kg", "kilogram", "kilograms"] { return "kg"; }
    if normalized in ["gal", "gals", "gallon", "gallons"] { return "gallon"; }
    if normalized in ["qt", "quart", "quarts"] { return "quart"; }
    if normalized in ["pt", "pint", "pints"] { return "pint"; }
    if normalized in ["ml", "milliliter", "milliliters"] { return "ml"; }
    if normalized in ["l", "liter", "liters", "litre", "litres"] { return "liter"; }
    return "";
}

glob _UNIT_PATTERN: str = r"fl\s*oz|fluid\s+ounces?|oz|ounces?|lbs?|pounds?|kg|kilograms?|g|grams?|gallons?|gals?|quarts?|qt|pints?|pt|ml|milliliters?|liters?|litres?|l|counts?|ct|packs?|pk|each";

# Parse a single grocery package expression. A zero quantity / empty unit means
# no recognizable package was found. Multipacks normalize to the total amount.
def:pub parse_package(text: str) -> tuple[float, str] {
    normalized = normalize_text(text);
    if normalized == "" {
        return (0.0, "");
    }
    if "half gallon" in normalized {
        return (0.5, "gallon");
    }
    if re.search(r"(^|\s)gallon(\s|$)", normalized) and not re.search(r"\d", normalized) {
        return (1.0, "gallon");
    }

    dozen = re.search(r"(\d+(?:\.\d+)?)\s+dozens?\b", normalized);
    if dozen {
        return (float(dozen.group(1)) * 12.0, "count");
    }

    multi = re.search(
        r"(\d+(?:\.\d+)?)\s*x\s*(\d+(?:\.\d+)?)\s*(" + _UNIT_PATTERN + r")\b",
        normalized
    );
    if multi {
        unit = canonical_package_unit(multi.group(3));
        if unit != "" {
            return (float(multi.group(1)) * float(multi.group(2)), unit);
        }
    }

    size = re.search(r"(\d+(?:\.\d+)?)\s*(" + _UNIT_PATTERN + r")\b", normalized);
    if size {
        unit = canonical_package_unit(size.group(2));
        if unit != "" {
            return (float(size.group(1)), unit);
        }
    }
    return (0.0, "");
}

# Number of containers in a package, when stated: "12 x 12 fl oz" -> 12,
# "12 pack" -> 12, "12 ct" -> 12, "1 dozen" -> 12. Zero when not stated.
def:pub parse_pack_count(text: str) -> float {
    normalized = normalize_text(text);
    multi = re.search(r"(\d+(?:\.\d+)?)\s*x\s*(\d+(?:\.\d+)?)\s*(" + _UNIT_PATTERN + r")\b", normalized);
    if multi { return float(multi.group(1)); }
    dozen = re.search(r"(\d+(?:\.\d+)?)\s+dozens?\b", normalized);
    if dozen { return float(dozen.group(1)) * 12.0; }
    count = re.search(r"(\d+(?:\.\d+)?)\s*(counts?|ct|packs?|pk|each)\b", normalized);
    if count { return float(count.group(1)); }
    return 0.0;
}

# Deterministic, authoritative package constraints from the query and the
# explicit advanced size field. The LLM never contributes to these.
def:pub requested_packages(query: str, required_size: str) -> list[PackageConstraint] {
    constraints: list[PackageConstraint] = [];
    (positive, _) = split_exclusions(query);
    (qty, unit) = parse_package(positive);
    if unit != "" and qty > 0.0 {
        constraints.append(PackageConstraint(quantity=qty, unit=unit, approximate=is_approximate(positive), source="query"));
    }
    if required_size.strip() != "" {
        (sqty, sunit) = parse_package(required_size);
        if sunit != "" and sqty > 0.0 {
            constraints.append(PackageConstraint(quantity=sqty, unit=sunit, approximate=is_approximate(required_size), source="required_size"));
        }
    }
    return constraints;
}
