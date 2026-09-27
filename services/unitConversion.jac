"""Deterministic unit normalization for mass, volume, and count dimensions."""

obj UnitQuantity {
    has quantity: float;
    has unit: str;
    has dimension: str;
}

glob _MASS_TO_OZ: dict[str, float] = {
    "oz": 1.0,
    "lb": 16.0,
    "g": 0.035274,
    "kg": 35.274
};

glob _VOLUME_TO_FLOZ: dict[str, float] = {
    "fl_oz": 1.0,
    "fl oz": 1.0,
    "pint": 16.0,
    "quart": 32.0,
    "gallon": 128.0,
    "ml": 0.033814,
    "l": 33.814,
    "liter": 33.814
};

glob _COUNT_UNITS: list[str] = ["each", "count", "pack", "ct"];

def:pub dimension_for_unit(unit: str) -> str {
    normalized = unit.strip().lower();
    if normalized in _MASS_TO_OZ { return "mass"; }
    if normalized in _VOLUME_TO_FLOZ { return "volume"; }
    if normalized in _COUNT_UNITS { return "count"; }
    return "unknown";
}

def:pub convert_to_base_unit(quantity: float, unit: str) -> UnitQuantity | None {
    normalized_unit = unit.strip().lower();
    dimension = dimension_for_unit(normalized_unit);

    if dimension == "mass" {
        return UnitQuantity(quantity=quantity * _MASS_TO_OZ[normalized_unit], unit="oz", dimension="mass");
    }
    if dimension == "volume" {
        return UnitQuantity(quantity=quantity * _VOLUME_TO_FLOZ[normalized_unit], unit="fl_oz", dimension="volume");
    }
    if dimension == "count" {
        return UnitQuantity(quantity=quantity, unit="count", dimension="count");
    }
    return None;
}

def:pub units_compatible(unit_a: str, unit_b: str) -> bool {
    dim_a = dimension_for_unit(unit_a);
    dim_b = dimension_for_unit(unit_b);
    return dim_a != "unknown" and dim_b != "unknown" and dim_a == dim_b;
}

def:pub compute_unit_price(effective_price: float, normalized_quantity: float) -> float {
    if normalized_quantity <= 0.0 { return -1.0; }
    return effective_price / normalized_quantity;
}
