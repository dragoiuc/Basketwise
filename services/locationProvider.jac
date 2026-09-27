import os;
import from services.basketwiseTypes { GeoPoint, Store }
import from services.krogerApi { discover_kroger_stores, credentials_present }

# Explicit location-provider selection. Default is mock. Kroger's documented
# API contract needs an authenticated developer account in this environment;
# the live adapter remains unavailable until its current contract is verified.
# A credential or API key alone never switches the active provider.

glob _MOCK_STORES: list[dict] = [
    {"store_id": "mock-1", "chain_key": "mock", "name": "Basketwise Market - Downtown", "address": "100 Main St", "lat_offset": 0.01, "lon_offset": 0.01},
    {"store_id": "mock-2", "chain_key": "mock", "name": "Basketwise Market - Westside", "address": "450 West Ave", "lat_offset": -0.03, "lon_offset": 0.02},
    {"store_id": "mock-3", "chain_key": "unsupported_chain", "name": "Regional Grocer", "address": "77 River Rd", "lat_offset": 0.02, "lon_offset": -0.015},
    {"store_id": "mock-fail", "chain_key": "failing_demo", "name": "Demo Adapter Failure Fixture", "address": "11 Test Way", "lat_offset": 0.015, "lon_offset": -0.01},
];

def:pub selected_data_provider() -> str {
    return os.environ.get("GROCERY_DATA_PROVIDER", "mock").strip().lower();
}

def:pub validate_selected_provider(provider_name: str, client_id: str, client_secret: str) -> str {
    provider = provider_name.strip().lower();
    if provider == "mock" {
        return "mock";
    }
    if provider == "kroger" {
        if client_id == "" or client_secret == "" {
            raise Exception("GROCERY_DATA_PROVIDER=kroger requires KROGER_CLIENT_ID and KROGER_CLIENT_SECRET.");
        }
        return "kroger";
    }
    raise Exception("Unsupported GROCERY_DATA_PROVIDER. Choose 'mock' or 'kroger'.");
}

def _validate_data_provider() {
    provider = selected_data_provider();
    id_present = credentials_present();
    secret_present = credentials_present();
    _ = validate_selected_provider(provider, "present" if id_present else "", "present" if secret_present else "");
}

def:pub distance_miles(a: GeoPoint, b: GeoPoint) -> float {
    import math;
    lat1 = math.radians(a.latitude);
    lat2 = math.radians(b.latitude);
    dlat = lat2 - lat1;
    dlon = math.radians(b.longitude - a.longitude);
    hav = math.sin(dlat / 2.0) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2.0) ** 2;
    return 3958.7613 * 2.0 * math.asin(min(1.0, math.sqrt(hav)));
}

def:pub geocode(location_text: str) -> GeoPoint {
    if location_text.strip() == "" { raise ValueError("Location text is required."); }
    _validate_data_provider();
    if selected_data_provider() != "mock" {
        raise Exception("Kroger location search requires ZIP-based store discovery; no ZIP centroid is provided by Kroger.");
    }
    return GeoPoint(latitude=42.2808, longitude=-83.7430);
}

def:pub discover_stores(location_text: str, center: GeoPoint | None, radius_miles: float) -> list[Store] {
    _validate_data_provider();
    if selected_data_provider() == "kroger" {
        return discover_kroger_stores(location_text, radius_miles);
    }
    if center is None { raise Exception("Mock location center is required."); }
    return _discover_mock_stores(center, radius_miles);
}

def:pub within_radius(store: Store, radius_miles: float) -> bool {
    if store.distance_miles is None { return False; }
    return store.distance_miles <= radius_miles;
}

def _discover_mock_stores(center: GeoPoint, radius_miles: float) -> list[Store] {
    _validate_data_provider();
    if selected_data_provider() != "mock" {
        return [];
    }
    stores: list[Store] = [];
    for fixture in _MOCK_STORES {
        store_point = GeoPoint(
            latitude=center.latitude + (fixture["lat_offset"] as float),
            longitude=center.longitude + (fixture["lon_offset"] as float)
        );
        distance = distance_miles(center, store_point);
        if distance <= radius_miles {
            stores.append(Store(
                store_id=fixture["store_id"] as str,
                chain_key=fixture["chain_key"] as str,
                name=fixture["name"] as str,
                address=fixture["address"] as str,
                latitude=store_point.latitude,
                longitude=store_point.longitude,
                distance_miles=distance
            ));
        }
    }
    return stores;
}
