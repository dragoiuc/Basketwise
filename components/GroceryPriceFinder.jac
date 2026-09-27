import from .ui.button { Button }
import from .ui.card { Card, CardContent, CardDescription, CardHeader, CardTitle }
import from .ui.field { Field, FieldDescription, FieldLabel }
import from .ui.input { Input }
import from .ui.checkbox { Checkbox }
import from .ui.badge { Badge }
import from .ui.skeleton { Skeleton }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" {
    Search01Icon, Location01Icon, ShoppingBag01Icon, InformationCircleIcon,
    Alert01Icon, ArrowUpRight01Icon
}
sv import from services.basketwiseTypes { SearchResponse }
sv import from services.searchCoordinator { search_groceries }

def:pub GroceryPriceFinder() -> JsxElement {
    has product_query: str = "";
    has location_text: str = "";
    has radius: str = "10";
    has compare_mode: str = "checkout";
    has brand: str = "";
    has package_size: str = "";
    has organic_only: bool = False;
    has members_allowed: bool = False;
    has coupons_allowed: bool = False;

    has attempted_search: bool = False;
    has loading: bool = False;
    has validation_error: str = "";
    has search_error: str = "";
    has response: SearchResponse | None = None;

    def update_product(e: ChangeEvent) { product_query = e.target.value; }
    def update_location(e: ChangeEvent) { location_text = e.target.value; }
    def update_radius(e: ChangeEvent) { radius = e.target.value; }
    def update_brand(e: ChangeEvent) { brand = e.target.value; }
    def update_size(e: ChangeEvent) { package_size = e.target.value; }

    async def run_search -> None {
        response = None;
        search_error = "";
        if product_query.strip() == "" {
            validation_error = "Enter a grocery item to search for.";
            attempted_search = True;
            return;
        }
        if location_text.strip() == "" {
            validation_error = "Enter a location to search near.";
            attempted_search = True;
            return;
        }

        validation_error = "";
        attempted_search = True;
        loading = True;

        mode = "unit" if compare_mode == "unit" else "checkout";

        try {
            result = await search_groceries(
                query=product_query,
                location_text=location_text,
                radius_miles=float(radius),
                required_brand=brand,
                required_size=package_size,
                organic_only=organic_only,
                compare_mode=mode,
                include_membership_prices=members_allowed,
                include_coupons=coupons_allowed
            );
            response = result;
        } except Exception {
            search_error = "Search provider is unavailable. Check the selected data provider configuration and try again.";
        } finally {
            loading = False;
        }
    }

    async def handle_submit(e: FormEvent) {
        e.preventDefault();
        await run_search();
    }

    return <main className="min-h-svh bg-muted/40 text-foreground">
        <header className="border-b bg-background/90">
            <div className="mx-auto flex h-16 w-full max-w-6xl items-center justify-between px-5 sm:px-8">
                <div className="flex items-center gap-3">
                    <div className="flex size-9 items-center justify-center rounded-xl bg-primary text-primary-foreground shadow-sm">
                        <HugeiconsIcon icon={ShoppingBag01Icon} strokeWidth={2} className="size-5" />
                    </div>
                    <span className="text-base font-semibold tracking-tight">Basketwise</span>
                </div>
                <span className="hidden text-sm text-muted-foreground sm:block">Local grocery price finder</span>
            </div>
        </header>
        <div className="mx-auto flex w-full max-w-6xl flex-col gap-8 px-5 pb-12 pt-9 sm:px-8 sm:pt-12">
            <section className="flex flex-col gap-3">
                <div className="inline-flex w-fit items-center gap-2 rounded-full border bg-background px-3 py-1 text-xs font-medium text-muted-foreground">
                    <span className="size-2 rounded-full bg-primary" />
                    Compare local grocery prices
                </div>
                <h1 className="max-w-3xl text-balance text-4xl font-semibold leading-[1.1] tracking-tight sm:text-5xl">Find your groceries for less.</h1>
                <p className="max-w-2xl text-base leading-relaxed text-muted-foreground">Search nearby stores for the item you need. Compare package prices and unit costs in one place.</p>
            </section>

            <Card className="overflow-hidden border-border/80 bg-card shadow-sm">
                <CardHeader className="border-b bg-background/70 px-5 py-5 sm:px-7">
                    <CardTitle>What are you shopping for?</CardTitle>
                    <CardDescription>Start with any grocery item and the location you want to shop near.</CardDescription>
                </CardHeader>
                <CardContent className="px-5 py-6 sm:px-7 sm:py-7">
                    <form onSubmit={handle_submit} className="flex flex-col gap-6">
                        <div className="grid gap-5 md:grid-cols-2">
                            <Field>
                                <FieldLabel htmlFor="product-query">Product</FieldLabel>
                                <div className="relative">
                                    <HugeiconsIcon icon={Search01Icon} strokeWidth={2} className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
                                    <Input id="product-query" value={product_query} onChange={update_product} placeholder="e.g. large eggs, 12 count" className="h-11 pl-9" />
                                </div>
                                <FieldDescription>Any grocery query, including brand or size.</FieldDescription>
                            </Field>
                            <Field>
                                <FieldLabel htmlFor="location">Your location</FieldLabel>
                                <div className="relative">
                                    <HugeiconsIcon icon={Location01Icon} strokeWidth={2} className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
                                    <Input id="location" value={location_text} onChange={update_location} placeholder="Address, ZIP code, or city and state" className="h-11 pl-9" />
                                </div>
                                <FieldDescription>Used to find stores within your search radius.</FieldDescription>
                            </Field>
                        </div>

                        <div className="grid gap-5 sm:grid-cols-2">
                            <Field>
                                <FieldLabel htmlFor="radius">Search radius</FieldLabel>
                                <select id="radius" value={radius} onChange={update_radius} className="h-11 w-full rounded-md border border-input bg-background px-3 text-sm shadow-sm outline-none focus-visible:ring-2 focus-visible:ring-ring">
                                    <option value="5">5 miles</option>
                                    <option value="10">10 miles</option>
                                    <option value="15">15 miles</option>
                                    <option value="25">25 miles</option>
                                    <option value="50">50 miles</option>
                                </select>
                            </Field>
                            <Field>
                                <FieldLabel htmlFor="compare-mode">Compare by</FieldLabel>
                                <select id="compare-mode" value={compare_mode} onChange={lambda (e: ChangeEvent) { compare_mode = e.target.value; }} className="h-11 w-full rounded-md border border-input bg-background px-3 text-sm shadow-sm outline-none focus-visible:ring-2 focus-visible:ring-ring">
                                    <option value="checkout">Lowest total price</option>
                                    <option value="unit">Lowest unit price</option>
                                </select>
                            </Field>
                        </div>

                        <div className="rounded-xl border bg-muted/30 p-4 sm:p-5">
                            <div className="mb-4">
                                <h2 className="text-sm font-semibold">Refine your search</h2>
                                <p className="mt-1 text-sm text-muted-foreground">Optional details help identify the right product.</p>
                            </div>
                            <div className="grid gap-4 sm:grid-cols-2">
                                <Field>
                                    <FieldLabel htmlFor="brand">Brand</FieldLabel>
                                    <Input id="brand" value={brand} onChange={update_brand} placeholder="Any brand" className="bg-background" />
                                </Field>
                                <Field>
                                    <FieldLabel htmlFor="package-size">Package size</FieldLabel>
                                    <Input id="package-size" value={package_size} onChange={update_size} placeholder="e.g. 18 oz or 1 gallon" className="bg-background" />
                                </Field>
                            </div>
                            <div className="mt-5 flex flex-wrap gap-x-7 gap-y-3">
                                <label className="flex cursor-pointer items-center gap-2.5 text-sm">
                                    <Checkbox checked={organic_only} onCheckedChange={lambda (v: bool) { organic_only = v; }} />
                                    Organic only
                                </label>
                                <label className="flex cursor-pointer items-center gap-2.5 text-sm">
                                    <Checkbox checked={members_allowed} onCheckedChange={lambda (v: bool) { members_allowed = v; }} />
                                    Include member prices
                                </label>
                                <label className="flex cursor-pointer items-center gap-2.5 text-sm">
                                    <Checkbox checked={coupons_allowed} onCheckedChange={lambda (v: bool) { coupons_allowed = v; }} />
                                    Include coupons
                                </label>
                            </div>
                        </div>

                        {validation_error != "" and <div className="flex items-center gap-2 rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive">
                            <HugeiconsIcon icon={Alert01Icon} strokeWidth={2} className="size-4 shrink-0" />
                            {validation_error}
                        </div>}

                        <div className="flex flex-col gap-3 border-t pt-5 sm:flex-row sm:items-center sm:justify-between">
                            <p className="text-xs text-muted-foreground">Results marked Demo data are fixture prices, not live store prices.</p>
                            <Button type="submit" className="h-11 w-full gap-2 shadow-sm sm:w-auto sm:px-6" disabled={loading}>
                                <HugeiconsIcon icon={Search01Icon} strokeWidth={2} className="size-4" />
                                {"Searching..." if loading else "Find cheapest"}
                            </Button>
                        </div>
                    </form>
                </CardContent>
            </Card>

            <section aria-live="polite" className="flex flex-col gap-4">
                <div className="flex flex-wrap items-end justify-between gap-2">
                    <div className="flex items-center gap-2.5">
                        <h2 className="text-xl font-semibold tracking-tight">Nearby price results</h2>
                        {response is not None and response.is_demo_data and <Badge variant="secondary">Demo data</Badge>}
                    </div>
                    <p className="mt-1 text-sm text-muted-foreground">Matched listings, ranked by your selected comparison.</p>
                </div>
                {response is not None and response.diagnostics.interpretation_summary != "" and <p className="text-xs text-muted-foreground">
                    Interpreted as: {response.diagnostics.interpretation_summary} ({response.diagnostics.interpretation_source})
                </p>}

                {if loading {
                    <Card className="border-border/80 bg-card shadow-sm">
                        <CardContent className="flex flex-col gap-4 px-6 py-8">
                            <Skeleton className="h-4 w-1/3" />
                            <Skeleton className="h-16 w-full" />
                            <Skeleton className="h-16 w-full" />
                            <Skeleton className="h-16 w-full" />
                        </CardContent>
                    </Card>
                    skip;
                }}

                {if not loading and response is not None and response.validation_error != "" {
                    <Card className="border-destructive/30 bg-card shadow-sm">
                        <CardContent className="flex items-center gap-3 px-6 py-8 text-destructive">
                            <HugeiconsIcon icon={Alert01Icon} strokeWidth={2} className="size-5 shrink-0" />
                            <p className="text-sm">{response.validation_error}</p>
                        </CardContent>
                    </Card>
                    skip;
                }}

                {if not loading and response is not None and response.validation_error == "" and len(response.results) == 0 {
                    <Card className="border-border/80 bg-card shadow-sm">
                        <CardContent className="flex min-h-52 flex-col items-center justify-center px-6 py-10 text-center">
                            <div className="mb-4 flex size-12 items-center justify-center rounded-2xl bg-primary/10 text-primary">
                                <HugeiconsIcon icon={InformationCircleIcon} strokeWidth={2} className="size-6" />
                            </div>
                            <h3 className="text-base font-semibold">No matching demo listings nearby</h3>
                            <p className="mt-2 max-w-xl text-sm leading-relaxed text-muted-foreground">
                                No listing near {response.location_text} could be confidently matched to "{response.query}". Try widening the radius or removing an optional filter.
                            </p>
                            {len(response.diagnostics.warnings) > 0 and <div className="mt-5 flex flex-col gap-1 rounded-lg border bg-muted/40 px-4 py-3 text-left text-xs leading-relaxed text-muted-foreground">
                                {for warning in response.diagnostics.warnings {
                                    <p key={warning}>{warning}</p>
                                }}
                            </div>}
                        </CardContent>
                    </Card>
                    skip;
                }}

                {if not loading and response is not None and response.validation_error == "" and len(response.results) > 0 {
                    <div className="flex flex-col gap-3">
                        {len(response.diagnostics.errors) > 0 and <div className="flex items-start gap-2 rounded-lg border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-sm text-amber-700 dark:text-amber-400">
                            <HugeiconsIcon icon={Alert01Icon} strokeWidth={2} className="mt-0.5 size-4 shrink-0" />
                            <div className="flex flex-col gap-0.5">
                                <span className="font-medium">Some stores could not be searched</span>
                                {for err in response.diagnostics.errors {
                                    <span key={err} className="text-xs">{err}</span>
                                }}
                            </div>
                        </div>}
                        {for result in response.results {
                            <Card key={result.source + result.store.store_id + result.product_name + result.brand + result.size_text + result.product_url} className="border-border/80 bg-card shadow-sm transition-shadow hover:shadow-md">
                                <CardContent className="flex flex-col gap-3 px-5 py-5 sm:flex-row sm:items-start sm:justify-between">
                                    <div className="flex flex-col gap-1.5">
                                        <div className="flex flex-wrap items-center gap-2">
                                            <span className="text-base font-semibold">{result.product_name}</span>
                                            {result.brand != "" and <Badge variant="outline">{result.brand}</Badge>}
                                            {result.is_demo_data and <Badge variant="secondary">Demo data</Badge>}
                                        </div>
                                        <span className="text-sm text-muted-foreground">{result.store.name} - {result.distance_label} - {result.size_text}</span>
                                        <span className="text-xs text-muted-foreground">Observed {result.observed_at}</span>
                                        {result.product_url != "" and <a href={result.product_url} target="_blank" rel="noreferrer" className="inline-flex w-fit items-center gap-1 text-xs font-medium text-primary hover:underline">
                                            View source
                                            <HugeiconsIcon icon={ArrowUpRight01Icon} strokeWidth={2} className="size-3" />
                                        </a>}
                                    </div>
                                    <div className="flex flex-col items-start gap-1 sm:items-end">
                                        <span className="text-xl font-semibold tabular-nums">{result.price_display}</span>
                                        <Badge variant={"secondary" if result.is_regular_price else "default"}>{result.price_label}</Badge>
                                        {result.unit_price_display != "" and <span className="text-xs text-muted-foreground">{result.unit_price_display}</span>}
                                        <span className={"text-xs " + ("text-emerald-600 dark:text-emerald-400" if result.in_stock else "text-muted-foreground")}>
                                            {"In stock" if result.in_stock else "Unavailable"}
                                        </span>
                                        <span className="text-xs text-muted-foreground">{result.confidence_display}</span>
                                    </div>
                                </CardContent>
                            </Card>
                        }}
                    </div>
                    skip;
                }}

                {if not loading and search_error != "" {
                    <Card className="border-destructive/30 bg-card shadow-sm">
                        <CardContent className="flex items-center gap-3 px-6 py-8 text-destructive">
                            <HugeiconsIcon icon={Alert01Icon} strokeWidth={2} className="size-5 shrink-0" />
                            <p className="text-sm">{search_error}</p>
                        </CardContent>
                    </Card>
                    skip;
                }}

                {if not loading and response is None {
                    <Card className="border-border/80 bg-card shadow-sm">
                        <CardContent className="flex min-h-52 flex-col items-center justify-center px-6 py-10 text-center">
                            <div className="mb-4 flex size-12 items-center justify-center rounded-2xl bg-primary/10 text-primary">
                                <HugeiconsIcon icon={InformationCircleIcon} strokeWidth={2} className="size-6" />
                            </div>
                            <h3 className="text-base font-semibold">Your comparison starts here</h3>
                            <p className="mt-2 max-w-xl text-sm leading-relaxed text-muted-foreground">
                                Enter a product and location above, then search to see ranked demo grocery prices.
                            </p>
                        </CardContent>
                    </Card>
                    skip;
                }}
            </section>
            <footer className="border-t pt-5 text-xs text-muted-foreground">
                Store adapters are designed to fail independently; unsupported providers can be added without changing comparison logic.
            </footer>
        </div>
    </main>;
}
