import Foundation
import GameCore

public enum ItemHooks {
    public static func weekly(_ s: inout GameState, _ i: Int, data: GameData) {
        RetailItems.weekly(&s, i, data: data)
        IndustrialItems.weekly(&s, i, data: data)
        ProfessionalServices.weekly(&s, i, data: data)
        AppointmentServices.weekly(&s, i, data: data)
        JobContracts.weekly(&s, i, data: data)
        RentalUnits.weekly(&s, i, data: data)
        TransportItems.weekly(&s, i, data: data)
        VenueItems.weekly(&s, i, data: data)
        FinanceItems.weekly(&s, i, data: data)
        let co = s.companies[i]
        if co.status == .open, ItemTradeGroups.food.contains(co.type) { _ = FoodRecipes.apply(&s, companyID: co.id, data: data, trades: ItemTradeGroups.food) }
        SupplyAutoPick.fillItems(&s, i, data: data)
    }

    public static func cogsFactor(_ s: GameState, companyID: Int, data: GameData) -> Double {
        RetailItems.cogsFactor(s, companyID: companyID, data: data) * VenueItems.cogsFactor(s, companyID: companyID, data: data)
    }
}
