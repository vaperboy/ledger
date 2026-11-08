import Foundation
import GameCore
import Businesses

/// What the equipment screen reads to decide which categories apply to a company.
public extension GameEngine {
    /// Which equipment categories a company has any use for: from the trade's own item list (a vehicle model means vehicles, a software kind
    /// means software, anything else is a machine), plus whatever the company already owns of a kind, so nothing owned is ever hidden.
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
