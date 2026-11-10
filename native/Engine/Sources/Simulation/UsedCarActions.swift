import Foundation
import GameCore
import Businesses

public extension GameEngine {
    @discardableResult
    mutating func setUsedCarPrice(companyID: Int, carID: Int, price: Double) -> SettingResult {
        var ok = false
        update { s, _, _ in ok = UsedCarDealer.setPrice(&s, companyID: companyID, carID: carID, price: price) }
        return ok ? .applied : .refused("That car is no longer in your yard, or the price is not valid.")
    }

    func usedCarQuote(companyID: Int, carID: Int, price: Double) -> UsedCarQuote? {
        UsedCarDealer.quote(state, companyID: companyID, carID: carID, price: price, data: data)
    }

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

    @discardableResult
    mutating func setUsedCarAutoRepair(companyID: Int, on: Bool) -> SettingResult {
        var ok = false
        update { s, _, _ in ok = UsedCarDealer.setAutoRepair(&s, companyID: companyID, on: on) }
        return ok ? .applied : .refused("Only a used car dealer has repair orders.")
    }

    func usedCarAutoRepair(companyID: Int) -> Bool { state.company(companyID).map { UsedCarDealer.autoRepair($0) } ?? true }

    func usedCarLot(companyID: Int) -> UsedCarLot? {
        state.company(companyID).flatMap { $0.type == UsedCarDealer.tradeID ? UsedCarDealer.lot($0) : nil }
    }

    func usedCarBuyers(companyID: Int) -> [UsedCarBuyerRecord] {
        state.company(companyID).map { UsedCarDealer.buyerRecords(state, $0) } ?? []
    }

    func usedCarSales(companyID: Int) -> [UsedCarSale] {
        state.company(companyID).map { UsedCarDealer.sales($0) } ?? []
    }
}
