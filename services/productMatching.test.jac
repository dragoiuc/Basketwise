import from services.basketwiseTypes { RawListing, SearchRequest }
def _eggs(size: str) -> RawListing {
    return RawListing(store_id="s1", source="mock:test", product_name="Large Eggs, Grade A", regular_price=4.29, brand="Basketwise Farms", size_text=size);
}

test "embedded query package size matches exact 12 count listing" {
    request = SearchRequest(query="large eggs 12 count", location_text="Ann Arbor, MI");
    decision = match_listing(request, _eggs("12 count"));
    assert decision.is_match;
    assert decision.normalized_quantity == 12.0;
    assert decision.normalized_unit == "count";
}

test "embedded query package size rejects 18 count listing" {
    request = SearchRequest(query="large eggs 12 count", location_text="Ann Arbor, MI");
    assert not match_listing(request, _eggs("18 ct")).is_match;
}

test "explicit required size is also enforced" {
    request = SearchRequest(query="large eggs", location_text="Ann Arbor, MI", required_size="12 ct");
    assert match_listing(request, _eggs("12 count")).is_match;
    assert not match_listing(request, _eggs("18 count")).is_match;
}

test "punctuation and plural normalization do not prevent eggs matching" {
    request = SearchRequest(query="Large eggs,", location_text="Ann Arbor, MI");
    assert match_listing(request, _eggs("12 count")).is_match;
}

test "large eggs without size accepts both package counts" {
    request = SearchRequest(query="large eggs", location_text="Ann Arbor, MI");
    assert match_listing(request, _eggs("12 count")).is_match;
    assert match_listing(request, _eggs("18 count")).is_match;
}

test "capitalization whitespace percent and package aliases normalize" {
    request = SearchRequest(query="  2%   MILK, 1 gal  ", location_text="Ann Arbor, MI");
    listing = RawListing(store_id="s1", source="mock:test", product_name="2 percent Milk", regular_price=3.79, brand="Dairy Lane", size_text="1 gallon");
    assert match_listing(request, listing).is_match;
}

test "wrong product is rejected" {
    request = SearchRequest(query="whole milk 1 gallon", location_text="Ann Arbor, MI");
    eggs = RawListing(store_id="s1", source="mock:test", product_name="Large Eggs, Grade A", regular_price=4.29, brand="Farm", size_text="12 count");
    assert not match_listing(request, eggs).is_match;
}

test "gallon query rejects half gallon listing" {
    request = SearchRequest(query="whole milk 1 gallon", location_text="Ann Arbor, MI");
    half = RawListing(store_id="s1", source="mock:test", product_name="Whole Milk", regular_price=2.29, brand="Dairy Lane", size_text="half gallon");
    assert not match_listing(request, half).is_match;
}

test "requested brand is enforced" {
    request = SearchRequest(query="large eggs", location_text="Ann Arbor, MI", required_brand="Wanted Farms");
    assert not match_listing(request, _eggs("12 count")).is_match;
}

test "organic requirement is enforced" {
    request = SearchRequest(query="eggs", location_text="Ann Arbor, MI", organic_only=True);
    assert not match_listing(request, _eggs("12 count")).is_match;
}

test "wrong product variety is rejected" {
    request = SearchRequest(query="large eggs", location_text="Ann Arbor, MI");
    listing = RawListing(store_id="s1", source="mock:test", product_name="Cage-Free Extra Large Eggs", regular_price=5.19, brand="Farm", size_text="12 count");
    assert not match_listing(request, listing).is_match;
}

test "wrong cheerios variety is rejected" {
    request = SearchRequest(query="Cheerios Original 18 oz", location_text="Ann Arbor, MI");
    listing = RawListing(store_id="s1", source="mock:test", product_name="Honey Nut Cheerios", regular_price=5.49, brand="Cheerios", size_text="18 oz");
    assert not match_listing(request, listing).is_match;
}

test "unknown package size is rejected when size was requested" {
    request = SearchRequest(query="large eggs 12 count", location_text="Ann Arbor, MI");
    assert not match_listing(request, _eggs("family pack")).is_match;
}

test "12 count package parses" {
    (qty, unit) = parse_package("12 count");
    assert qty == 12.0;
    assert unit == "count";
}

test "12 ct alias parses" {
    (qty, unit) = parse_package("12 ct");
    assert qty == 12.0;
    assert unit == "count";
}

test "1 dozen normalizes to 12 count" {
    (qty, unit) = parse_package("1 dozen");
    assert qty == 12.0;
    assert unit == "count";
    request = SearchRequest(query="large eggs 1 dozen", location_text="Ann Arbor, MI");
    assert match_listing(request, _eggs("12 ct")).is_match;
}

test "18 count package parses" {
    (qty, unit) = parse_package("18 count");
    assert qty == 18.0;
    assert unit == "count";
}

test "1 gallon package parses" {
    (qty, unit) = parse_package("1 gallon");
    assert qty == 1.0;
    assert unit == "gallon";
}

test "64 fluid ounces package parses" {
    (qty, unit) = parse_package("64 fl oz");
    assert qty == 64.0;
    assert unit == "fl_oz";
}

test "fl_oz alias parses" {
    (qty, unit) = parse_package("64 fl_oz");
    assert qty == 64.0;
    assert unit == "fl_oz";
}

test "2 pounds package parses" {
    (qty, unit) = parse_package("2 lb");
    assert qty == 2.0;
    assert unit == "lb";
}

test "lbs alias parses" {
    (qty, unit) = parse_package("2 lbs");
    assert qty == 2.0;
    assert unit == "lb";
}

test "16 ounces package parses" {
    (qty, unit) = parse_package("16 oz");
    assert qty == 16.0;
    assert unit == "oz";
}

test "multi-pack 12 x 12 fl oz normalizes to total fluid ounces" {
    (qty, unit) = parse_package("12 x 12 fl oz");
    assert qty == 144.0;
    assert unit == "fl_oz";
    request = SearchRequest(query="soda 12 x 12 fl oz", location_text="Ann Arbor, MI");
    listing = RawListing(store_id="s1", source="mock:test", product_name="Soda", regular_price=8.0, brand="Fizzy", size_text="12 x 12 fl oz");
    decision = match_listing(request, listing);
    assert decision.is_match;
    assert abs(decision.normalized_quantity - 144.0) < 0.01;
}

test "6 pack normalizes to count" {
    (qty, unit) = parse_package("6 pack");
    assert qty == 6.0;
    assert unit == "count";
}
