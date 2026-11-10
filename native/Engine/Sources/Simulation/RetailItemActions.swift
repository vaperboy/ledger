import Foundation
import GameCore
import Countries
import Finance
import Businesses

public extension GameEngine {
    func retailAddableItems(companyID: Int) -> [RetailItems.Def] { RetailItems.addable(state, companyID: companyID, data: data) }

    @discardableResult
    mutating func addRetailItem(companyID: Int, defID: String) -> SettingResult {
        let data = self.data
        return applySetting(refuse: { s in RetailItems.addRefusal(s, companyID: companyID, defID: defID, data: data) }, probe: { $0.companySnapshot(companyID) }) { s, d, _ in
            _ = RetailItems.add(&s, companyID: companyID, defID: defID, data: d)
        }
    }

    func carRepairQuote(garageID: Int, kind: String, scale: Double = 1) -> RepairQuote? {
        RetailItems.carRepairQuote(state, garageID: garageID, kind: kind, scale: scale, data: data)
    }

    func carRepairGarages(for companyID: Int) -> [Int] { CarRepairJobs.garages(for: companyID, state, data: data) }

    @discardableResult
    mutating func orderCarRepair(garageID: Int, dealerID: Int, kind: String, scale: Double = 1, ref: String = "") -> RepairResult {
        var result: RepairResult = .refused("Not done.")
        update { s, d, _ in result = RetailItems.orderRepair(&s, garageID: garageID, dealerID: dealerID, kind: kind, scale: scale, ref: ref, data: d) }
        return result
    }
}
