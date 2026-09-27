import from services.basketwiseTypes { RawListing, SearchRequest, PriceType }

# Deterministic effective-price selection.
# Regular price is eligible by default. A lower sale price is used when
# present. Member and coupon prices are only considered when the request
# explicitly allows them - never fabricated as generally available.
def:pub select_effective_price(listing: RawListing, request: SearchRequest) -> tuple[float, PriceType] {
    price = listing.regular_price;
    price_type = PriceType.REGULAR;

    if listing.sale_price >= 0.0 and listing.sale_price < price {
        price = listing.sale_price;
        price_type = PriceType.SALE;
    }

    if (
        request.include_membership_prices
        and listing.member_price >= 0.0
        and listing.member_price < price
    ) {
        price = listing.member_price;
        price_type = PriceType.MEMBER;
    }

    if (
        request.include_coupons
        and listing.coupon_price >= 0.0
        and listing.coupon_price < price
    ) {
        price = listing.coupon_price;
        price_type = PriceType.COUPON;
    }

    return (price, price_type);
}
