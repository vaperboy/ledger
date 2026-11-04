import Foundation
import GameCore
import Businesses

/// The used car dealer's yard (rework of 4 Nov 2026): one price, quote and repair order per car, the lot, the buyers and the sales.
public extension GameEngine {
    /// Set the asking price of one car, in company currency units.
    @discardableResult
    mutating func setUsedCarPrice(companyID: Int, carID: Int, price: Double) -> SettingResult {
        var ok = false
        update { s, _, _ in ok = UsedCarDealer.setPrice(&s, companyID: companyID, carID: carID, price: price) }
        return ok ? .applied : .refused("That car is no longer in your yard, or the price is not valid.")
    }

    /// Live profit or loss and the weekly sale chance of a car at `price` (price - buy price - repairs - holding).
    func usedCarQuote(companyID: Int, carID: Int, price: Double) -> UsedCarQuote? {
        UsedCarDealer.quote(state, companyID: companyID, carID: carID, price: price, data: data)
    }

    /// What the repair of a quoted car would cost, who would do it and how long it takes.
    func usedCarRepairOffer(companyID: Int, carID: Int) -> UsedCarRepairOffer? {
        UsedCarDealer.repairOffer(state, companyID: companyID, carID: carID, data: data)
    }

    @discardableResult
    mutating func sendUsedCarToRepair(companyID: Int, carID: Int) -> SettingResult {
        var ok = false
        update { s, d, _ in ok = UsedCarDealer.sendToRepair(&s, companyID: companyID, carID: carID, data: d) }
        return ok ? .applied : .refused("That car has no repair waiting, or it is already at the garage.")
    }

    @discardableResult
    mutating func sellUsedCarAsIs(companyID: Int, carID: Int) -> SettingResult {
        var ok = false
        update { s, _, _ in ok = UsedCarDealer.sellAsIs(&s, companyID: companyID, carID: carID) }
        return ok ? .applied : .refused("That car has no repair waiting, or it is already at the garage.")
    }

    /// On (default): every repair quote is sent to the garage at once. Off: you decide car by car.
    @discardableResult
    mutating func setUsedCarAutoRepair(companyID: Int, on: Bool) -> SettingResult {
        var ok = false
        update { s, _, _ in ok = UsedCarDealer.setAutoRepair(&s, companyID: companyID, on: on) }
        return ok ? .applied : .refused("Only a used car dealer has repair orders.")
    }

    func usedCarAutoRepair(companyID: Int) -> Bool { state.company(companyID).map { UsedCarDealer.autoRepair($0) } ?? true }

    /// Lot spaces from the premises, and how many cars stand on them.
    func usedCarLot(companyID: Int) -> UsedCarLot? {
        state.company(companyID).flatMap { $0.type == UsedCarDealer.tradeID ? UsedCarDealer.lot($0) : nil }
    }

    /// Track record of whoever buys cars for the dealer (hired buyers, the manager, you).
    func usedCarBuyers(companyID: Int) -> [UsedCarBuyerRecord] {
        state.company(companyID).map { UsedCarDealer.buyerRecords(state, $0) } ?? []
    }

    /// The last cars sold, with what each really made.
    func usedCarSales(companyID: Int) -> [UsedCarSale] {
        state.company(companyID).map { UsedCarDealer.sales($0) } ?? []
    }
}
