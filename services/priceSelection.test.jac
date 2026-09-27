import from services.basketwiseTypes { RawListing, SearchRequest, PriceType }
test "regular price is the default effective price" {
    request = SearchRequest(query="item", location_text="Ann Arbor, MI");
    listing = RawListing(store_id="s1", source="mock:test", product_name="Item", regular_price=5.00);
    (price, kind) = select_effective_price(listing, request);
    assert price == 5.00;
    assert kind == PriceType.REGULAR;
}

test "sale price wins when eligible and lower" {
    request = SearchRequest(query="item", location_text="Ann Arbor, MI");
    listing = RawListing(store_id="s1", source="mock:test", product_name="Item", regular_price=5.00, sale_price=3.50);
    (price, kind) = select_effective_price(listing, request);
    assert price == 3.50;
    assert kind == PriceType.SALE;
}

test "member price excluded by default and included by flag" {
    listing = RawListing(store_id="s1", source="mock:test", product_name="Item", regular_price=5.00, member_price=2.00);
    (off_price, off_kind) = select_effective_price(listing, SearchRequest(query="item", location_text="Ann Arbor, MI"));
    (on_price, on_kind) = select_effective_price(listing, SearchRequest(query="item", location_text="Ann Arbor, MI", include_membership_prices=True));
    assert off_price == 5.00;
    assert off_kind == PriceType.REGULAR;
    assert on_price == 2.00;
    assert on_kind == PriceType.MEMBER;
}

test "coupon price excluded by default and included by flag" {
    listing = RawListing(store_id="s1", source="mock:test", product_name="Item", regular_price=5.00, coupon_price=1.50);
    (off_price, off_kind) = select_effective_price(listing, SearchRequest(query="item", location_text="Ann Arbor, MI"));
    (on_price, on_kind) = select_effective_price(listing, SearchRequest(query="item", location_text="Ann Arbor, MI", include_coupons=True));
    assert off_price == 5.00;
    assert off_kind == PriceType.REGULAR;
    assert on_price == 1.50;
    assert on_kind == PriceType.COUPON;
}

test "lower eligible price wins deterministically" {
    listing = RawListing(store_id="s1", source="mock:test", product_name="Item", regular_price=6.00, sale_price=5.00, member_price=4.00, coupon_price=3.00);
    request = SearchRequest(query="item", location_text="Ann Arbor, MI", include_membership_prices=True, include_coupons=True);
    (price, kind) = select_effective_price(listing, request);
    assert price == 3.00;
    assert kind == PriceType.COUPON;
}
