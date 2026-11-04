import SwiftUI
import GameCore
import Businesses
import Countries

/// The extra item page blocks of the item waves, in one place so `ItemPageView` has a single line for all of them.
/// Each wave adds its block here when it lands.
struct WaveItemBlocks: View {
    var e: GameEngine
    var companyID: Int
    var itemID: String
    var price: Double
    var cur: Currency

    var body: some View {
        if let c = Wave3Recipes.card(e.state, companyID: companyID, itemID: itemID, price: price, data: e.data) {
            Wave3RecipeBlock(card: c, cur: cur)
        }
        Wave4ItemBlocks(engine: e, companyID: companyID, itemID: itemID, currency: cur)
        Wave5ServiceBlock(companyID: companyID, itemID: itemID)
        Wave6ItemBlocks(engine: e, companyID: companyID, itemID: itemID, currency: cur)
        Wave8UnitBlock(companyID: companyID, itemID: itemID)
    }
}
