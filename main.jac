import from services.searchCoordinator { search_groceries }
import ".styles.global.css";
import from .components.GroceryPriceFinder { GroceryPriceFinder }

def:pub app() -> JsxElement {
    return <GroceryPriceFinder />;
}
