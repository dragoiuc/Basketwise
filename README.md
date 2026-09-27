# Basketwise

Basketwise is a Jac full-stack app for comparing local grocery prices. Type an ordinary grocery request ("large eggs 12 count", "regular cheerios not honey nut") and a location. Basketwise works out which product you mean, searches retailer catalogs, rejects listings that are a materially different product, enforces package constraints, and ranks the valid prices.

## Hybrid architecture

The LLM interprets grocery language. Deterministic code enforces the facts.

```text
GroceryPriceFinder (client)
  -> search_groceries RPC (typed SearchResponse, browser-safe fields)
  -> request validation
  -> location provider (GROCERY_DATA_PROVIDER: mock | kroger)
  -> semantic interpretation, once per search      services/productInterpreter.jac
       deterministic package parse (authoritative)  services/groceryText.jac
       ProductIntent (by llm, or deterministic)
       grounding + merge -> ResolvedQuery
  -> retailer retrieval with ResolvedQuery.search_term
       (retries once with the original query if the term returns nothing)
  -> hybrid candidate matching                      services/productMatching.jac
       1. deterministic hard rejections: brand, organic, explicit exclusions,
          legacy variety rules, package quantity and dimension
       2. obvious deterministic positive: every product term present
       3. partial match -> needs_semantic_review -> ONE batched semantic call
  -> stock filtering, effective price (regular/sale/member/coupon)
  -> unit normalization (mass / volume / count)
  -> deterministic ranking
```

### ProductIntent (what the user wants)

`canonical_product`, `brand`, `variety`, `form`, `size_class`, `attributes[]`, `exclusions[]`, `organic` (`bool | None`), `retailer_search_term`, `semantic_notes`. It never holds price, stock, retailer, ranking, or package quantity.

### by llm() functions

- `llm_interpret_grocery_query(query, explicit_filters) -> ProductIntent`: one call per unique search, cached in memory per normalized query for the life of the process.
- `llm_judge_candidates(intent, raw_query, candidates) -> list[SemanticMatchResult]`: one batched call per search, used only when some candidates pass every hard constraint but do not state all the requested product terms. Capped at 25 candidates. Results are keyed by `candidate_id`, never by list position.

### How semantic and deterministic results merge

1. Explicit form controls (brand, package size, organic only, member and coupon eligibility) win.
2. Deterministically parsed package quantities (`12 count`, `1 dozen`, `12 x 12 fl oz`, `6 pack`, `around 1 lb`) win. The LLM is told to ignore sizes, and its output is never used for packages.
3. Semantic intent comes last and is grounded first: a descriptor, brand, organic flag, or exclusion from the LLM is enforced only if the user's own words support it. If you search "milk", you will not get "organic whole milk" just because the model suggested it. Anything dropped is recorded in `ResolvedQuery.dropped_terms`.
4. An approximate size ("around 1 lb") gets a ±15% tolerance. Exact sizes get ±5% for label rounding. Counts must match exactly.

### What the LLM does NOT do

It does not pick the cheapest price, decide member or coupon eligibility, do package arithmetic or unit conversion, decide whether $/oz is comparable to $/count, handle stock, apply the radius, or sort results. It also never receives location, credentials, retailer tokens, or prices. It sees only the query text and the explicit brand/organic filters.

## Configuration

| Variable | Values | Purpose |
|---|---|---|
| `GROCERY_DATA_PROVIDER` | `mock` (default), `kroger` | Retail data source |
| `KROGER_CLIENT_ID`, `KROGER_CLIENT_SECRET` | server-only | Kroger OAuth client credentials |
| `PRODUCT_INTERPRETER` | `deterministic` (default), `llm` | Semantic mode. A key alone never enables LLM mode. |
| `LLM_MODEL` | default `gpt-4o-mini` | Model used by `by llm()` (also read by `[byllm.model]` in `jac.toml`) |
| `OPENAI_API_KEY` | secret | Credential for OpenAI models |

In JacHammer, set these in **Settings -> Environment**, then restart the preview. `.env` is git-ignored. `.env.example` holds placeholders only.

### Fallback behavior (chosen and tested)

If `PRODUCT_INTERPRETER=llm` and the model call cannot be used, whether there is no credential, the request fails, it times out (20 s), or the structured output is invalid, the search still runs using deterministic interpretation. The response reports `interpretation_source = "deterministic_fallback"` along with a sanitized warning. Raw provider errors and keys never reach the browser. If the batched candidate review fails, ambiguous candidates are rejected (conservative).

### Diagnostics

`SearchDiagnostics` includes `interpretation_source` (`deterministic | llm | llm_cached | deterministic_fallback`), `interpretation_summary`, `search_term`, `search_term_fallbacks`, `interpretation_calls`, `semantic_match_calls`, and `semantic_candidates_evaluated`. The UI shows one small "Interpreted as" line above the results.

## Cost and latency

A typical LLM-mode search makes 1 interpretation call (0 on a cache hit) plus 0 or 1 batched candidate call. It never makes N calls for N listings. Deterministic mode makes no model calls.

## Retailers

- **Mock** (default): a fixed Ann Arbor coordinate, labeled demo stores, and fixture listings (eggs, milk, Cheerios, yogurt, chicken, soda), including one unsupported chain and one deliberately failing adapter.
- **Kroger** (implemented): OAuth client credentials (`product.compact`), `/v1/locations` ZIP-near discovery, and `/v1/products` search per store using the shared `search_term`. The location must be a five-digit ZIP. Kroger returns no ZIP centroid, so distance shows as "Distance not provided". All product understanding stays in shared services; the adapter only retrieves and normalizes listings.

## Run, check, test

```bash
jac install
jac start --dev main.jac
jac check main.jac
JAC_TEST_JOBS=0 jac test
```

The test suite is deterministic and needs no credentials. It forces `GROCERY_DATA_PROVIDER=mock` and `PRODUCT_INTERPRETER=deterministic`, and replaces both `by llm()` functions with typed fixtures through `set_intent_provider` / `set_judge_provider`.

- `services/semanticCorpus.jac`: a regression corpus of 36 grocery intents across 15 categories, each with positives, semantic negatives, and hard negatives. Its annex `semanticCorpus.test.jac` covers interpretation/grounding (A), package parsing (B), and candidate compatibility (C).
- `services/searchCoordinator.test.jac`: full search integration (D), including fallback, caching, batching, and browser-safe fields.
- `services/productMatching.test.jac`, `unitConversion.test.jac`, `priceSelection.test.jac`, `locationProvider.test.jac`: deterministic unit tests.

For a live semantic smoke check, set `PRODUCT_INTERPRETER=llm` and a model key, then call `interpret_query(...)` from a scratch script and inspect the returned `ResolvedQuery.intent`.

## Current limitations

- If every requested product word appears in a listing, it counts as a deterministic match, so listings with an extra unrequested flavor can pass. For example, "regular cheerios" matches "Strawberry Cheerios Protein". Only exclusions the user states ("not honey nut") are enforced for every listing.
- The legacy variety and egg-size rules in `productMatching.jac` are kept as deterministic safety nets. New concepts are not added to those lists.
- The mock geocoder maps any location to one Ann Arbor coordinate. Kroger mode needs a ZIP.
- The interpretation cache is per process and in memory only. There is no retry policy for provider calls.
