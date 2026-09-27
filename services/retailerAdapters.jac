import from services.basketwiseTypes { RawListing, Store, StockStatus, SearchRequest }
import from services.krogerApi { search_kroger_store }

# Adapter contract: search_store(store, request) -> list[RawListing]. Each
# retailer can inspect complete search context without coordinator changes.

glob _MOCK_OBSERVED_AT: str = "2024-01-01T00:00:00Z";

def search_mock_store(store: Store, request: SearchRequest) -> list[RawListing] {
    # Fixed demonstration data only. Never represented as live retailer pricing.
    return [
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Large Eggs, Grade A", regular_price=4.29, brand="Basketwise Farms", size_text="12 count", sale_price=3.79, product_url="https://example-mock-store.test/products/large-eggs-12ct", observed_at=_MOCK_OBSERVED_AT),
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Large Eggs, Grade A", regular_price=7.49, brand="Basketwise Farms", size_text="18 ct", product_url="https://example-mock-store.test/products/large-eggs-18ct", observed_at=_MOCK_OBSERVED_AT),
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Cage-Free Extra Large Eggs", regular_price=5.19, brand="Basketwise Farms", size_text="12 count", product_url="https://example-mock-store.test/products/xl-eggs-12ct", observed_at=_MOCK_OBSERVED_AT),
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Large Eggs, Grade A", regular_price=4.49, brand="Farmstead Select", size_text="12 count", stock_status=StockStatus.OUT_OF_STOCK, product_url="https://example-mock-store.test/products/farmstead-large-eggs", observed_at=_MOCK_OBSERVED_AT),
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Large Eggs, Grade A", regular_price=4.99, member_price=3.49, brand="Value Club", size_text="12 count", product_url="https://example-mock-store.test/products/value-club-large-eggs", observed_at=_MOCK_OBSERVED_AT),
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Large Eggs, Grade A", regular_price=5.49, coupon_price=2.99, brand="Coupon Corner", size_text="12 count", product_url="https://example-mock-store.test/products/coupon-large-eggs", observed_at=_MOCK_OBSERVED_AT),
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Large Eggs, Grade A", regular_price=4.69, brand="Market Basket", size_text="1 dozen", product_url="https://example-mock-store.test/products/dozen-eggs", observed_at=_MOCK_OBSERVED_AT),
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Large Eggs, Grade A", regular_price=4.59, brand="Unknown Size Co", size_text="family pack", product_url="https://example-mock-store.test/products/unknown-size-eggs", observed_at=_MOCK_OBSERVED_AT),
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Large Eggs, Grade A", regular_price=8.99, brand="Bulk Basket", size_text="2 lb", product_url="https://example-mock-store.test/products/eggs-by-weight", observed_at=_MOCK_OBSERVED_AT),
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Large Eggs, Grade A", regular_price=6.99, brand="Liquid Metric", size_text="64 fl oz", product_url="https://example-mock-store.test/products/eggs-by-volume", observed_at=_MOCK_OBSERVED_AT),
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Whole Milk", regular_price=3.79, brand="Dairy Lane", size_text="1 gallon", product_url="https://example-mock-store.test/products/whole-milk-gallon", observed_at=_MOCK_OBSERVED_AT),
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Whole Milk", regular_price=2.29, brand="Dairy Lane", size_text="half gallon", product_url="https://example-mock-store.test/products/whole-milk-half-gallon", observed_at=_MOCK_OBSERVED_AT),
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Cheerios Original", regular_price=5.99, brand="Cheerios", size_text="18 oz", product_url="https://example-mock-store.test/products/cheerios-original-18oz", observed_at=_MOCK_OBSERVED_AT),
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Honey Nut Cheerios", regular_price=5.49, brand="Cheerios", size_text="18 oz", product_url="https://example-mock-store.test/products/cheerios-honey-nut-18oz", observed_at=_MOCK_OBSERVED_AT),
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Chocolate Milk", regular_price=4.19, brand="Dairy Lane", size_text="1 gallon", product_url="https://example-mock-store.test/products/chocolate-milk-gallon", observed_at=_MOCK_OBSERVED_AT),
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Strawberry Greek Yogurt", regular_price=1.29, brand="Hillside", size_text="5.3 oz", product_url="https://example-mock-store.test/products/strawberry-greek-yogurt", observed_at=_MOCK_OBSERVED_AT),
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Vanilla Greek Yogurt", regular_price=1.19, brand="Hillside", size_text="5.3 oz", product_url="https://example-mock-store.test/products/vanilla-greek-yogurt", observed_at=_MOCK_OBSERVED_AT),
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Strawberry Lowfat Yogurt", regular_price=0.89, brand="Hillside", size_text="6 oz", product_url="https://example-mock-store.test/products/strawberry-yogurt", observed_at=_MOCK_OBSERVED_AT),
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Boneless Skinless Chicken Breast", regular_price=8.98, brand="Prairie Poultry", size_text="2 lb", product_url="https://example-mock-store.test/products/bs-chicken-breast-2lb", observed_at=_MOCK_OBSERVED_AT),
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Bone-In Split Chicken Breast", regular_price=5.98, brand="Prairie Poultry", size_text="2 lb", product_url="https://example-mock-store.test/products/bone-in-chicken-breast", observed_at=_MOCK_OBSERVED_AT),
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Boneless Skinless Chicken Thighs", regular_price=6.49, brand="Prairie Poultry", size_text="2 lb", product_url="https://example-mock-store.test/products/bs-chicken-thighs", observed_at=_MOCK_OBSERVED_AT),
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Chicken Breast Fillets", regular_price=9.49, brand="Farm Fresh", size_text="2 lb", product_url="https://example-mock-store.test/products/chicken-breast-fillets", observed_at=_MOCK_OBSERVED_AT),
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Coca-Cola Zero Sugar Cans", regular_price=7.99, brand="Coca-Cola", size_text="12 x 12 fl oz", product_url="https://example-mock-store.test/products/coke-zero-12pk", observed_at=_MOCK_OBSERVED_AT),
        RawListing(store_id=store.store_id, source="mock:" + store.chain_key, product_name="Diet Coke Cans", regular_price=7.49, brand="Coca-Cola", size_text="12 x 12 fl oz", product_url="https://example-mock-store.test/products/diet-coke-12pk", observed_at=_MOCK_OBSERVED_AT),
    ];
}

glob _ADAPTER_REGISTRY: dict[str, str] = {"mock": "mock", "kroger": "kroger", "failing_demo": "fail"};

def:pub list_registered_chain_keys() -> list[str] {
    return list(_ADAPTER_REGISTRY.keys());
}

def:pub get_adapter(chain_key: str) -> str | None {
    if chain_key in _ADAPTER_REGISTRY { return _ADAPTER_REGISTRY[chain_key]; }
    return None;
}

def:pub search_store(store: Store, request: SearchRequest) -> list[RawListing] {
    adapter = get_adapter(store.chain_key);
    if adapter == "mock" { return search_mock_store(store, request); }
    if adapter == "kroger" { return search_kroger_store(store, request); }
    if adapter == "fail" { raise Exception("Deliberate demo adapter failure fixture."); }
    return [];
}
