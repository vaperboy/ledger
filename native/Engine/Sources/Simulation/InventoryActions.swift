import Foundation
import GameCore
import Businesses
import Finance

public extension GameEngine {
    var inventoryItems: [InventoryItem] { PlayerInventory.items(state) }
    var inventoryWorth: Double { PlayerInventory.value(state) }
    var inventoryHeldTotal: Double { PlayerInventory.heldTotal(state) }
    var homeCurrencyCode: String { PlayerInventory.homeCurrency(state, data) }

    func inventoryItem(_ id: String) -> InventoryItem? { PlayerInventory.item(state, id: id) }
    func inventoryHeld(dealID: String) -> Double { PlayerInventory.holds(state)[dealID] ?? 0 }
    func inventoryRepairOffers(itemID: String) -> [InventoryRepairOffer] { PlayerInventory.repairOffers(state, id: itemID) }
    func inventoryListingPayload(itemID: String) -> JSONValue? { PlayerInventory.listingPayload(state, id: itemID, data: data) }
    func inventoryListingProblem(itemID: String) -> String? { PlayerInventory.canList(state, id: itemID) }
    func inventorySuggestedPrice(itemID: String) -> Double { PlayerInventory.suggestedPrice(state, id: itemID) }
    func inventoryStockProblem(itemID: String, companyID: Int) -> String? { PlayerInventory.canStock(state, id: itemID, companyID: companyID) }
    func inventoryCanKeepLuxury(itemID: String) -> Bool { PlayerInventory.canKeepLuxury(state, id: itemID) }
    func vehicleSaleProblem(companyID: Int, vehicleID: Int) -> String? { PlayerInventory.canMoveVehicle(state, companyID: companyID, vehicleID: vehicleID, data: data) }
    func unitSaleProblem(companyID: Int, equipmentID: String, unitID: Int) -> String? { PlayerInventory.canMoveUnit(state, companyID: companyID, equipmentID: equipmentID, unitID: unitID) }
    func luxurySaleProblem(pieceID: Int) -> String? { PlayerInventory.canMoveLuxury(state, pieceID: pieceID) }
    func serverAmount(_ internalAmount: Double, currency: String) -> Double { PlayerInventory.toServer(internalAmount, currency: currency, state, data) }
    func internalAmount(_ serverAmount: Double, currency: String) -> Double { PlayerInventory.fromServer(serverAmount, currency: currency, state, data) }

    private func settingResult(_ r: InventoryResult) -> SettingResult {
        if case .refused(let why) = r { return .refused(why) }
        return .applied
    }

    @discardableResult
    mutating func startInventoryRepair(itemID: String, shopID: Int) -> SettingResult {
        var r: InventoryResult = .refused("Not done.")
        update { s, _, _ in r = PlayerInventory.startRepair(&s, id: itemID, shopID: shopID) }
        return settingResult(r)
    }

    @discardableResult
    mutating func moveVehicleToInventory(companyID: Int, vehicleID: Int) -> SettingResult {
        var r: InventoryResult = .refused("Not done.")
        update { s, d, _ in r = PlayerInventory.takeVehicle(&s, companyID: companyID, vehicleID: vehicleID, data: d) }
        return settingResult(r)
    }

    @discardableResult
    mutating func moveUnitToInventory(companyID: Int, equipmentID: String, unitID: Int, name: String) -> SettingResult {
        var r: InventoryResult = .refused("Not done.")
        update { s, d, _ in r = PlayerInventory.takeUnit(&s, companyID: companyID, equipmentID: equipmentID, unitID: unitID, name: name, data: d) }
        return settingResult(r)
    }

    @discardableResult
    mutating func moveLuxuryToInventory(pieceID: Int) -> SettingResult {
        var r: InventoryResult = .refused("Not done.")
        update { s, _, _ in r = PlayerInventory.takeLuxury(&s, pieceID: pieceID) }
        return settingResult(r)
    }

    @discardableResult
    mutating func keepInventoryLuxury(itemID: String) -> SettingResult {
        var r: InventoryResult = .refused("Not done.")
        update { s, _, _ in r = PlayerInventory.keepLuxury(&s, id: itemID) }
        return settingResult(r)
    }

    @discardableResult
    mutating func stockInventoryItem(itemID: String, companyID: Int) -> SettingResult {
        var r: InventoryResult = .refused("Not done.")
        update { s, _, _ in r = PlayerInventory.stockInDealer(&s, id: itemID, companyID: companyID) }
        return settingResult(r)
    }

    mutating func lockInventory(itemID: String, listingID: String) {
        update { s, _, _ in PlayerInventory.lockForListing(&s, id: itemID, listingID: listingID) }
    }

    mutating func unlockInventory(itemID: String) {
        update { s, _, _ in PlayerInventory.unlock(&s, id: itemID) }
    }

    @discardableResult
    mutating func holdForDeal(dealID: String, amount: Double, label: String) -> SettingResult {
        var r: InventoryResult = .refused("Not done.")
        update { s, _, _ in r = PlayerInventory.hold(&s, dealID: dealID, amount: amount, label: label) }
        return settingResult(r)
    }

    @discardableResult
    mutating func releaseDealHold(dealID: String) -> Double {
        var back = 0.0
        update { s, _, _ in
            back = PlayerInventory.release(&s, dealID: dealID)
            if back > 0 { Payments.playerReceives(&s, back, label: "Marketplace: money back") }
        }
        return back
    }
}
