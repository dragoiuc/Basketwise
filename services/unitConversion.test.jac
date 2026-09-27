test "gallon converts to 128 fluid ounces" {
    result = convert_to_base_unit(1.0, "gallon");
    assert result is not None;
    assert result.unit == "fl_oz";
    assert result.dimension == "volume";
    assert abs(result.quantity - 128.0) < 0.001;
}

test "pounds convert to ounces" {
    result = convert_to_base_unit(2.0, "lb");
    assert result is not None;
    assert result.unit == "oz";
    assert result.dimension == "mass";
    assert abs(result.quantity - 32.0) < 0.001;
}

test "count converts unchanged" {
    result = convert_to_base_unit(12.0, "count");
    assert result is not None;
    assert result.unit == "count";
    assert result.dimension == "count";
    assert result.quantity == 12.0;
}

test "aliases and dimensions work" {
    assert units_compatible("fl oz", "gallon");
    assert units_compatible("lb", "oz");
    assert units_compatible("ct", "pack");
    assert not units_compatible("oz", "count");
    assert dimension_for_unit("count") == "count";
    assert dimension_for_unit("oz") == "mass";
    assert dimension_for_unit("fl_oz") == "volume";
}

test "unknown unit has no conversion" {
    assert convert_to_base_unit(2.0, "furlong") is None;
}

test "unit price returns unknown for invalid quantity" {
    assert compute_unit_price(5.0, 0.0) == -1.0;
    assert compute_unit_price(5.0, -1.0) == -1.0;
}

test "unit price is deterministic" {
    assert abs(compute_unit_price(4.0, 128.0) - (4.0 / 128.0)) < 0.0001;
}
