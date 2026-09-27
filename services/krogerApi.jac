import os;
import time;
import json;
import base64;
import urllib.parse;
import urllib.request;
import urllib.error;

import from services.basketwiseTypes { GeoPoint, Store, SearchRequest, RawListing, StockStatus }

# The Kroger API contract is based on live official calls verified 2026-09-27:
# OAuth: POST https://api.kroger.com/v1/connect/oauth2/token with client_credentials
# and scope=product.compact. Locations: GET /v1/locations with filter.zipCode.near,
# filter.radiusInMiles, filter.limit. Products: GET /v1/products with filter.term,
# filter.locationId, filter.limit. Products carry items[].size, inventory.stockLevel,
# price.regular/promo/effectiveDate and productPageURI. Credentials stay server-side.

glob _TOKEN: str = "";
glob _TOKEN_EXPIRES_AT: float = 0.0;
glob _HTTP_TIMEOUT: float = 20.0;
glob _KROGER_BASE: str = "https://api.kroger.com";

# Populate only the relevant Kroger environment keys from the ignored local .env
# when JacHammer starts from the project directory. Existing process variables win.
def _load_local_provider_env() {
    import os.path;
    path = ".env";
    if not os.path.isfile(path) { return; }
    with open(path, "r", encoding="utf-8") as env_file {
        for line in env_file {
            stripped = line.strip();
            if stripped != "" and not stripped.startswith("#") and "=" in stripped {
                pair = stripped.split("=", 1);
                key = pair[0].strip();
                value = pair[1].strip().strip("\"").strip("'");
                if key in ["GROCERY_DATA_PROVIDER", "KROGER_CLIENT_ID", "KROGER_CLIENT_SECRET"] and os.environ.get(key, "") == "" {
                    os.environ[key] = value;
                }
            }
        }
    }
}

def:pub credentials_present() -> bool {
    _load_local_provider_env();
    return os.environ.get("KROGER_CLIENT_ID", "") != "" and os.environ.get("KROGER_CLIENT_SECRET", "") != "";
}

# For testability, accepts a supplied live-shaped response fixture; no secret is returned/logged.
def:pub normalize_inventory_status(stock_level: str) -> StockStatus {
    if stock_level == "HIGH" or stock_level == "LOW" { return StockStatus.IN_STOCK; }
    if stock_level == "TEMPORARILY_OUT_OF_STOCK" { return StockStatus.OUT_OF_STOCK; }
    return StockStatus.UNKNOWN;
}

# One request primitive used only by this server-side adapter.
def _request_json(method: str, path: str, token: str, body: str) -> str {
    req = urllib.request.Request(
        _KROGER_BASE + path,
        data=body.encode("utf-8") if body != "" else None,
        headers={"Authorization": "Bearer " + token, "Accept": "application/json", "Content-Type": "application/x-www-form-urlencoded"},
        method=method
    );
    resp: any = urllib.request.urlopen(req, timeout=_HTTP_TIMEOUT);
    try {
        return str(resp.read().decode("utf-8"));
    } finally {
        resp.close();
    }
}

def _access_token() -> str {
    import time;
    _load_local_provider_env();
    now = time.time();
    if _TOKEN != "" and now < _TOKEN_EXPIRES_AT - 60.0 { return _TOKEN; }
    client_id = os.environ.get("KROGER_CLIENT_ID", "");
    client_secret = os.environ.get("KROGER_CLIENT_SECRET", "");
    if client_id == "" or client_secret == "" {
        raise Exception("Kroger credentials are missing. Add KROGER_CLIENT_ID and KROGER_CLIENT_SECRET in JacHammer Settings -> Environment.");
    }
    credentials = base64.b64encode((client_id + ":" + client_secret).encode("utf-8")).decode("ascii");
    req = urllib.request.Request(
        _KROGER_BASE + "/v1/connect/oauth2/token",
        data=urllib.parse.urlencode({"grant_type": "client_credentials", "scope": "product.compact"}).encode("utf-8"),
        headers={"Authorization": "Basic " + credentials, "Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"},
        method="POST"
    );
    try {
        token_resp: any = urllib.request.urlopen(req, timeout=_HTTP_TIMEOUT);
        try {
            token_data = json.loads(token_resp.read().decode("utf-8"));
        } finally {
            token_resp.close();
        }
    } except Exception {
        raise Exception("Kroger authentication failed. Check developer credentials and API access.");
    }
    token_value = token_data.get("access_token", "");
    if token_value == "" { raise Exception("Kroger authentication response did not contain an access token."); }
    ttl = int(token_data.get("expires_in", 1800));
    _TOKEN = token_value;
    _TOKEN_EXPIRES_AT = now + ttl;
    return _TOKEN;
}

def _haversine_miles(lat1: float, lon1: float, lat2: float, lon2: float) -> float {
    import math;
    r1 = math.radians(lat1);
    r2 = math.radians(lat2);
    dlat = r2 - r1;
    dlon = math.radians(lon2 - lon1);
    hav = math.sin(dlat / 2.0) ** 2 + math.cos(r1) * math.cos(r2) * math.sin(dlon / 2.0) ** 2;
    return 3958.7613 * 2.0 * math.asin(min(1.0, math.sqrt(hav)));
}

# Official ZIP-near discovery returns candidate stores and coordinates, but no
# ZIP centroid. Keep returned candidates and leave distance unknown: do not
# fabricate a ZIP origin or claim independent distance validation.
def:pub discover_kroger_stores(zip_code: str, radius_miles: float) -> list[Store] {
    zip_value = zip_code.strip();
    if len(zip_value) != 5 or not zip_value.isdigit() { raise ValueError("Kroger live search requires a five-digit ZIP code."); }
    token = _access_token();
    query = urllib.parse.urlencode({"filter.zipCode.near": zip_code, "filter.radiusInMiles": str(max(1, int(round(radius_miles)))), "filter.limit": "50"});
    payload = json.loads(_request_json("GET", "/v1/locations?" + query, token, ""));
    stores: list[Store] = [];
    for raw in payload.get("data", []) {
        geo = raw.get("geolocation") or {};
        addr = raw.get("address") or {};
        loc_id = str(raw.get("locationId", ""));
        lat = geo.get("latitude");
        lon = geo.get("longitude");
        if loc_id == "" or lat is None or lon is None { continue; }
        stores.append(Store(
            store_id=loc_id,
            chain_key="kroger",
            name=str(raw.get("name", "Kroger")),
            address=str(addr.get("addressLine1", "")) + ", " + str(addr.get("city", "")) + ", " + str(addr.get("state", "")) + " " + str(addr.get("zipCode", "")),
            latitude=float(str(lat)),
            longitude=float(str(lon)),
            distance_miles=None
        ));
    }
    return stores;
}

def:pub search_kroger_store(store: Store, request: SearchRequest) -> list[RawListing] {
    token = _access_token();
    # Shared interpretation supplies the term; no Kroger-specific semantics here.
    term = request.search_term.strip() if request.search_term.strip() != "" else request.query;
    query = urllib.parse.urlencode({"filter.term": term, "filter.locationId": store.store_id, "filter.limit": "50"});
    payload = json.loads(_request_json("GET", "/v1/products?" + query, token, ""));
    records: list[RawListing] = [];
    observed = str(time.time());
    for product in payload.get("data", []) {
        for item in product.get("items", []) {
            status = normalize_inventory_status(str((item.get("inventory") or {}).get("stockLevel", "UNKNOWN")));
            price_blob = item.get("price") or {};
            regular = price_blob.get("regular");
            if regular is None { continue; }
            sale = price_blob.get("promo");
            uri = str(product.get("productPageURI", ""));
            product_url = "https://www.kroger.com" + uri if uri.startswith("/") else "";
            records.append(RawListing(
                store_id=store.store_id,
                source="kroger:" + str(product.get("upc", product.get("productId", ""))),
                product_name=str(product.get("description", "")),
                regular_price=float(str(regular)),
                brand=str(product.get("brand", "")),
                size_text=str(item.get("size", "")),
                sale_price=float(str(sale)) if sale is not None else -1.0,
                stock_status=status,
                product_url=product_url,
                observed_at=observed
            ));
        }
    }
    return records;
}
