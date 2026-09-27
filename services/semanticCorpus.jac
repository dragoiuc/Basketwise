import from services.basketwiseTypes { ProductIntent }

# Grocery semantic regression corpus. Each case pairs a raw query with the
# typed ProductIntent a well-behaved interpreter should return, the package
# constraint deterministic code must parse, and candidate listings:
#   positives      - must match, or be flagged for semantic review
#   negatives      - must never be accepted without a semantic decision
#   hard_negatives - must be rejected by deterministic rules alone
# The corpus exists to expose generalization failures; the implementation is
# not tuned to its product words.

obj CorpusCase {
    has category: str;
    has query: str;
    has intent: ProductIntent;
    has package_qty: float = 0.0;
    has package_unit: str = "";
    has approximate: bool = False;
    has positives: list[tuple[str, str, str]] = [];
    has negatives: list[tuple[str, str, str]] = [];
    has hard_negatives: list[tuple[str, str, str]] = [];
}

def _pi(product: str, variety: str = "", form: str = "", size_class: str = "", attributes: list[str] = [], exclusions: list[str] = [], brand: str = "", organic: bool | None = None, term: str = "") -> ProductIntent {
    return ProductIntent(canonical_product=product, brand=brand, variety=variety, form=form, size_class=size_class, attributes=attributes, exclusions=exclusions, organic=organic, retailer_search_term=term);
}

glob CORPUS: list[CorpusCase] = [
    # eggs
    CorpusCase(category="eggs", query="large eggs 12 count", intent=_pi("eggs", size_class="large", term="large eggs"), package_qty=12.0, package_unit="count",
        positives=[("Large Eggs, Grade A", "Farm", "12 ct"), ("Grade A Large White Eggs", "Farm", "1 dozen")],
        hard_negatives=[("Cage-Free Extra Large Eggs", "Farm", "12 count"), ("Large Eggs, Grade A", "Farm", "18 ct"), ("Jumbo Eggs", "Farm", "12 ct")]),
    CorpusCase(category="eggs", query="brown eggs 18 ct", intent=_pi("eggs", variety="brown", term="brown eggs"), package_qty=18.0, package_unit="count",
        positives=[("Large Brown Eggs", "Farm", "18 count")],
        negatives=[("Large White Eggs", "Farm", "18 count")],
        hard_negatives=[("Large Brown Eggs", "Farm", "12 count")]),
    # dairy milk
    CorpusCase(category="dairy milk", query="whole milk 1 gallon", intent=_pi("milk", variety="whole", term="whole milk"), package_qty=1.0, package_unit="gallon",
        positives=[("Whole Milk", "Dairy", "1 gal"), ("Vitamin D Whole Milk", "Dairy", "128 fl oz")],
        hard_negatives=[("Chocolate Milk", "Dairy", "1 gallon"), ("Whole Milk", "Dairy", "half gallon"), ("2% Reduced Fat Milk", "Dairy", "1 gallon")]),
    CorpusCase(category="dairy milk", query="organic horizon whole milk gallon", intent=_pi("milk", brand="Horizon", variety="whole", organic=True, term="horizon organic whole milk"), package_qty=1.0, package_unit="gallon",
        positives=[("Horizon Organic Whole Milk", "Horizon", "1 gallon")],
        hard_negatives=[("Whole Milk", "Dairy Lane", "1 gallon"), ("Horizon Organic Whole Milk", "Horizon", "half gallon")]),
    CorpusCase(category="dairy milk", query="skim milk half gallon", intent=_pi("milk", variety="skim", term="skim milk"), package_qty=0.5, package_unit="gallon",
        positives=[("Fat Free Skim Milk", "Dairy", "half gallon")],
        hard_negatives=[("Whole Milk", "Dairy", "half gallon")]),
    CorpusCase(category="dairy milk", query="milk", intent=_pi("milk", term="milk"),
        positives=[("Whole Milk", "Dairy", "1 gallon"), ("Organic 2% Milk", "Horizon", "half gallon")],
        hard_negatives=[("Chocolate Milk", "Dairy", "1 gallon"), ("Unsweetened Almond Milk", "Silk", "64 fl oz")]),
    # plant milk
    CorpusCase(category="plant milk", query="unsweetened vanilla almond milk", intent=_pi("almond milk", variety="vanilla", attributes=["unsweetened"], term="unsweetened vanilla almond milk"),
        positives=[("Unsweetened Vanilla Almondmilk", "Silk", "64 fl oz"), ("Almond Milk Unsweetened Vanilla", "Blue Diamond", "64 fl oz")],
        negatives=[("Original Almond Milk", "Silk", "64 fl oz"), ("Vanilla Almond Milk", "Silk", "64 fl oz")],
        hard_negatives=[("Whole Milk", "Dairy", "1 gallon")]),
    CorpusCase(category="plant milk", query="oat milk 64 fl oz", intent=_pi("oat milk", term="oat milk"), package_qty=64.0, package_unit="fl_oz",
        positives=[("Original Oat Milk", "Oatly", "64 fl oz")],
        negatives=[("Whole Milk", "Dairy", "64 fl oz")],
        hard_negatives=[("Original Oat Milk", "Oatly", "32 fl oz")]),
    # cereal
    CorpusCase(category="cereal", query="regular cheerios not honey nut", intent=_pi("cheerios", exclusions=["honey nut"], term="cheerios"),
        positives=[("Cheerios Original", "Cheerios", "18 oz"), ("Cheerios Heart Healthy Cereal", "General Mills", "12 oz")],
        hard_negatives=[("Honey Nut Cheerios", "Cheerios", "18 oz")]),
    CorpusCase(category="cereal", query="honey nut cheerios 18 oz", intent=_pi("cheerios", variety="honey nut", term="honey nut cheerios"), package_qty=18.0, package_unit="oz",
        positives=[("Honey Nut Cheerios", "Cheerios", "18 oz")],
        hard_negatives=[("Cheerios Original", "Cheerios", "18 oz")]),
    CorpusCase(category="cereal", query="frosted flakes", intent=_pi("frosted flakes", term="frosted flakes"),
        positives=[("Frosted Flakes Cereal", "Kellogg's", "13.5 oz")],
        negatives=[("Corn Flakes", "Kellogg's", "12 oz")]),
    # soda
    CorpusCase(category="soda", query="Coke Zero 12 pack cans", intent=_pi("coke zero", form="cans", term="coke zero"), package_qty=12.0, package_unit="count",
        positives=[("Coke Zero Cans", "Coca-Cola", "12 x 12 fl oz"), ("Coca-Cola Zero Sugar Cans", "Coca-Cola", "12 pk")],
        negatives=[("Diet Coke Cans", "Coca-Cola", "12 x 12 fl oz"), ("Coca-Cola Classic Cans", "Coca-Cola", "12 x 12 fl oz")],
        hard_negatives=[("Coke Zero Cans", "Coca-Cola", "8 x 12 fl oz")]),
    CorpusCase(category="soda", query="Coke Zero 12 x 12 fl oz", intent=_pi("coke zero", term="coke zero"), package_qty=144.0, package_unit="fl_oz",
        positives=[("Coke Zero", "Coca-Cola", "12 x 12 fl oz")],
        hard_negatives=[("Coke Zero", "Coca-Cola", "2 liter")]),
    CorpusCase(category="soda", query="diet coke 2 liter", intent=_pi("diet coke", term="diet coke"), package_qty=2.0, package_unit="liter",
        positives=[("Diet Coke Bottle", "Coca-Cola", "2 L")],
        negatives=[("Coca-Cola Zero Sugar", "Coca-Cola", "2 L")]),
    # yogurt
    CorpusCase(category="yogurt", query="strawberry greek yogurt", intent=_pi("greek yogurt", variety="strawberry", term="strawberry greek yogurt"),
        positives=[("Strawberry Greek Yogurt", "Hillside", "5.3 oz"), ("Greek Nonfat Yogurt Strawberry", "Chobani", "5.3 oz")],
        negatives=[("Strawberry Lowfat Yogurt", "Hillside", "6 oz"), ("Vanilla Greek Yogurt", "Hillside", "5.3 oz")],
        hard_negatives=[("Whole Milk", "Dairy", "1 gallon")]),
    CorpusCase(category="yogurt", query="plain greek yogurt 32 oz", intent=_pi("greek yogurt", variety="plain", term="plain greek yogurt"), package_qty=32.0, package_unit="oz",
        positives=[("Plain Nonfat Greek Yogurt", "Fage", "32 oz")],
        negatives=[("Vanilla Greek Yogurt", "Fage", "32 oz")],
        hard_negatives=[("Plain Nonfat Greek Yogurt", "Fage", "5.3 oz")]),
    # bread
    CorpusCase(category="bread", query="gluten free sandwich bread", intent=_pi("sandwich bread", attributes=["gluten free"], term="gluten free sandwich bread"),
        positives=[("Gluten Free White Sandwich Bread", "Canyon", "18 oz")],
        negatives=[("White Sandwich Bread", "Wonder", "20 oz")]),
    CorpusCase(category="bread", query="whole wheat bread 24 oz", intent=_pi("bread", variety="whole wheat", term="whole wheat bread"), package_qty=24.0, package_unit="oz",
        positives=[("100% Whole Wheat Bread", "Nature's Own", "24 oz")],
        negatives=[("White Bread", "Wonder", "24 oz")],
        hard_negatives=[("100% Whole Wheat Bread", "Nature's Own", "16 oz")]),
    # broth
    CorpusCase(category="broth", query="low sodium chicken broth", intent=_pi("chicken broth", attributes=["low sodium"], term="low sodium chicken broth"),
        positives=[("Low Sodium Chicken Broth", "Swanson", "32 oz")],
        negatives=[("Chicken Broth", "Swanson", "32 oz"), ("Low Sodium Beef Broth", "Swanson", "32 oz")]),
    CorpusCase(category="broth", query="vegetable broth 32 oz", intent=_pi("vegetable broth", term="vegetable broth"), package_qty=32.0, package_unit="oz",
        positives=[("Organic Vegetable Broth", "Pacific", "32 oz")],
        negatives=[("Chicken Broth", "Swanson", "32 oz")]),
    # cheese
    CorpusCase(category="cheese", query="shredded sharp cheddar 8 oz", intent=_pi("cheddar", variety="sharp", form="shredded", term="shredded sharp cheddar"), package_qty=8.0, package_unit="oz",
        positives=[("Sharp Cheddar Shredded Cheese", "Tillamook", "8 oz")],
        negatives=[("Sharp Cheddar Cheese Block", "Tillamook", "8 oz"), ("Mild Cheddar Shredded Cheese", "Kraft", "8 oz")]),
    CorpusCase(category="cheese", query="fresh mozzarella", intent=_pi("mozzarella", form="fresh", term="fresh mozzarella"),
        positives=[("Fresh Mozzarella Ball", "BelGioioso", "8 oz")],
        negatives=[("Shredded Low-Moisture Mozzarella", "Kraft", "8 oz")]),
    # chicken
    CorpusCase(category="chicken", query="boneless skinless chicken breast 2 lb", intent=_pi("chicken breast", form="boneless skinless", term="boneless skinless chicken breast"), package_qty=2.0, package_unit="lb",
        positives=[("Boneless Skinless Chicken Breast", "Prairie", "2 lb"), ("Chicken Breast Fillets", "Farm", "32 oz")],
        negatives=[("Bone-In Split Chicken Breast", "Prairie", "2 lb")],
        hard_negatives=[("Boneless Skinless Chicken Breast", "Prairie", "3 lb")]),
    CorpusCase(category="chicken", query="chicken thighs", intent=_pi("chicken thighs", term="chicken thighs"),
        positives=[("Boneless Skinless Chicken Thighs", "Prairie", "2 lb")],
        negatives=[("Boneless Skinless Chicken Breast", "Prairie", "2 lb")]),
    # ground beef
    CorpusCase(category="ground beef", query="ground beef 90/10 around 1 lb", intent=_pi("ground beef", variety="90/10", term="90/10 ground beef"), package_qty=1.0, package_unit="lb", approximate=True,
        positives=[("90/10 Lean Ground Beef", "Ranch", "1 lb"), ("Ground Beef 90% Lean 10% Fat", "Ranch", "16 oz")],
        negatives=[("80/20 Ground Beef", "Ranch", "1 lb")],
        hard_negatives=[("90/10 Lean Ground Beef", "Ranch", "3 lb")]),
    CorpusCase(category="ground beef", query="80/20 ground chuck 2 lb", intent=_pi("ground chuck", variety="80/20", term="80/20 ground chuck"), package_qty=2.0, package_unit="lb",
        positives=[("80/20 Ground Chuck", "Ranch", "2 lb")],
        negatives=[("90/10 Ground Chuck", "Ranch", "2 lb")]),
    # produce
    CorpusCase(category="produce", query="baby spinach 5 oz", intent=_pi("spinach", size_class="baby", term="baby spinach"), package_qty=5.0, package_unit="oz",
        positives=[("Organic Baby Spinach", "Earthbound", "5 oz")],
        negatives=[("Spinach Bunch", "Farm", "5 oz")],
        hard_negatives=[("Organic Baby Spinach", "Earthbound", "16 oz")]),
    CorpusCase(category="produce", query="organic bananas", intent=_pi("bananas", organic=True, term="organic bananas"),
        positives=[("Organic Bananas", "Farm", "each")],
        hard_negatives=[("Bananas", "Farm", "each")]),
    CorpusCase(category="produce", query="gala apples 3 lb", intent=_pi("apples", variety="gala", term="gala apples"), package_qty=3.0, package_unit="lb",
        positives=[("Gala Apples Bag", "Orchard", "3 lb")],
        negatives=[("Honeycrisp Apples", "Orchard", "3 lb")]),
    # frozen
    CorpusCase(category="frozen", query="frozen broccoli florets 12 oz", intent=_pi("broccoli florets", form="frozen", term="frozen broccoli florets"), package_qty=12.0, package_unit="oz",
        positives=[("Frozen Broccoli Florets", "Birds Eye", "12 oz")],
        negatives=[("Fresh Broccoli Crowns", "Farm", "12 oz")]),
    CorpusCase(category="frozen", query="pepperoni frozen pizza", intent=_pi("pizza", variety="pepperoni", form="frozen", term="pepperoni frozen pizza"),
        positives=[("Pepperoni Frozen Pizza", "DiGiorno", "27.5 oz")],
        negatives=[("Four Cheese Frozen Pizza", "DiGiorno", "27.5 oz")]),
    # pasta / rice
    CorpusCase(category="pasta rice", query="spaghetti 16 oz", intent=_pi("spaghetti", term="spaghetti"), package_qty=16.0, package_unit="oz",
        positives=[("Spaghetti Pasta", "Barilla", "16 oz"), ("Thin Spaghetti", "Barilla", "1 lb")],
        negatives=[("Penne Rigate", "Barilla", "16 oz")]),
    CorpusCase(category="pasta rice", query="jasmine rice 2 lb", intent=_pi("rice", variety="jasmine", term="jasmine rice"), package_qty=2.0, package_unit="lb",
        positives=[("Thai Jasmine Rice", "Mahatma", "2 lb")],
        negatives=[("Long Grain White Rice", "Mahatma", "2 lb")]),
    # canned
    CorpusCase(category="canned", query="no salt added black beans 15 oz", intent=_pi("black beans", attributes=["no salt added"], term="no salt added black beans"), package_qty=15.0, package_unit="oz",
        positives=[("No Salt Added Black Beans", "Bush's", "15 oz")],
        negatives=[("Black Beans", "Bush's", "15 oz")]),
    CorpusCase(category="canned", query="diced tomatoes not fire roasted", intent=_pi("diced tomatoes", exclusions=["fire roasted"], term="diced tomatoes"),
        positives=[("Diced Tomatoes", "Hunt's", "14.5 oz")],
        hard_negatives=[("Fire Roasted Diced Tomatoes", "Muir Glen", "14.5 oz")]),
    CorpusCase(category="canned", query="chunk light tuna in water", intent=_pi("tuna", variety="chunk light", form="in water", term="chunk light tuna in water"),
        positives=[("Chunk Light Tuna in Water", "StarKist", "5 oz")],
        negatives=[("Solid White Albacore Tuna in Water", "StarKist", "5 oz")])
];
