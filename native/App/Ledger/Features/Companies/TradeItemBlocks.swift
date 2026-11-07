import SwiftUI
import GameCore
import Businesses
import Countries
import Simulation

/// The extra item page blocks of the item trade groups, in one place so `ItemPageView` has a single line for all of them.
struct TradeItemBlocks: View {
    var e: GameEngine
    var companyID: Int
    var itemID: String
    var price: Double
    var cur: Currency

    var body: some View {
        if let c = FoodRecipes.card(e.state, companyID: companyID, itemID: itemID, price: price, data: e.data) {
            FoodRecipeBlock(card: c, cur: cur)
        }
        IndustrialItemBlocks(engine: e, companyID: companyID, itemID: itemID, currency: cur)
        ProfessionalServiceBlock(companyID: companyID, itemID: itemID)
        AppointmentItemBlocks(engine: e, companyID: companyID, itemID: itemID, currency: cur)
        JobItemBlocks(engine: e, companyID: companyID, itemID: itemID, currency: cur)
        RentalUnitBlock(companyID: companyID, itemID: itemID)
        VenueItemBlock(companyID: companyID, itemID: itemID)
        TransportItemBlock(companyID: companyID, itemID: itemID)
        FinanceItemBlock(companyID: companyID, itemID: itemID, price: price, cur: cur)
    }
}
