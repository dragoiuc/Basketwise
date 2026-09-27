test "mock provider is the safe default" {
    assert validate_selected_provider("mock", "", "") == "mock";
    assert validate_selected_provider(" MOCK ", "", "") == "mock";
}

test "Kroger requires credentials and never falls back silently" {
    message = "";
    try {
        _ = validate_selected_provider("kroger", "", "");
    } except Exception as e {
        message = str(e);
    }
    assert "KROGER_CLIENT_ID" in message;
    assert "mock" not in message;
}

test "Kroger provider accepts credentials for the live adapter" {
    assert validate_selected_provider("kroger", "fixture-client", "fixture-secret") == "kroger";
}

test "unknown provider is rejected" {
    message = "";
    try {
        _ = validate_selected_provider("unknown", "", "");
    } except Exception as e {
        message = str(e);
    }
    assert "Unsupported GROCERY_DATA_PROVIDER" in message;
}

test "Haversine distance is zero at identical coordinates" {
    point = GeoPoint(latitude=42.2808, longitude=-83.7430);
    assert distance_miles(point, point) < 0.001;
}

test "Haversine distance is deterministic for nearby Ann Arbor points" {
    center = GeoPoint(latitude=42.2808, longitude=-83.7430);
    nearby = GeoPoint(latitude=42.2908, longitude=-83.7330);
    miles = distance_miles(center, nearby);
    assert miles > 0.0;
    assert miles < 1.0;
}

test "radius helper includes an in-radius store and excludes out-of-radius and unknown distance" {
    near_store = Store(store_id="near", chain_key="mock", name="Nearby", address="A", latitude=42.0, longitude=-83.0, distance_miles=2.5);
    far_store = Store(store_id="far", chain_key="mock", name="Far", address="B", latitude=43.0, longitude=-83.0, distance_miles=12.0);
    unknown_store = Store(store_id="unknown", chain_key="kroger", name="Unknown", address="C", latitude=42.0, longitude=-83.0);
    assert within_radius(near_store, 10.0);
    assert not within_radius(far_store, 10.0);
    assert not within_radius(unknown_store, 10.0);
}
