import Foundation
import GameCore
import Businesses

public extension GameEngine {
    func equipmentRelevance(companyID: Int) -> (machines: Bool, vehicles: Bool, software: Bool) {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return (false, false, false) }
        let tables = data.catalog.tables
        var machines = false, vehicles = false, software = false
        for e in bd.equipment where e.id != "fit" {
            switch EquipmentMarket.kind(e, tradeID: bd.id, tables: tables) {
            case "veh": vehicles = true
            case "soft": software = true
            default: machines = true
            }
        }
        for o in ownedEquipment(companyID: companyID) {
            switch o.kind {
            case "veh": vehicles = true
            case "soft": software = true
            default: machines = true
            }
        }
        return (machines, vehicles, software)
    }
}
