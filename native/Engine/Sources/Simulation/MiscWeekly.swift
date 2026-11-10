import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Events

enum MiscWeekly {
    static func run(_ s: inout GameState, data: GameData, context: FinanceContext) {
        StaffProfile.trackWeek(&s)
        ContractTalk.weekly(&s, data: data)
        PremisesExtras.weekly(&s, data: data)
        OwnerHours.adjustWeek(&s, data: data)
        Luxury.ownerWeek(&s)
        Luxury.riskChecks(&s, data: data)
        StaffPerks.weekly(&s, data: data)
        StaffExpenses.weekly(&s, data: data)
        FixedTerm.weekly(&s, data: data)
        StaffPromises.weekly(&s, data: data)
        PromiseReminders.weekly(&s, data: data)
        Giving.weekly(&s, data: data)
        Ambitions.weekly(&s, data: data)
        Stories.weekly(&s, data: data)
        Press.weekly(&s, data: data)
        WeatherEvents.weekly(&s, data: data)
        PlayerSupply.weekly(&s)
        Shipments.weekly(&s, data: data)
        StockInsurance.weekly(&s, data: data)
    }

    static func monthly(_ s: inout GameState, data: GameData, context: FinanceContext) {
        Suppliers.monthly(&s)
        Agency.monthly(&s, data: data)
    }
}
