import Foundation
import GameCore
import Countries

/// A breakdown of an item that is still under warranty needs no decision: the supplier repairs it at no cost (owner decision, 3 Nov), the unit is
/// out of use for one or two days, and an informational message says so. Out of warranty the breakdown events keep asking the owner.
/// The warranty data is the `warr` week of each unit (`EquipmentUnits.newUnit`) and of each vehicle (`CompanySetup`); a used unit has none.
public enum EquipmentWarranty {
    /// Is the next unit of this item (by name) under warranty now?
    public static func isCovered(_ s: GameState, companyID: Int, itemName: String, data: GameData) -> Bool {
        guard let co = s.company(companyID), let spec = data.catalog[co.type]?.allEquipment.first(where: { $0.name == itemName }) else { return false }
        if spec.vehicleModels != nil {
            return co.value("veh").array.first { $0["eq"].string == spec.id && $0["down"].double == 0 }.map { covered($0, s.week) } ?? false
        }
        return co.value("units")[spec.id].array.first { $0["down"].double == 0 }.map { covered($0, s.week) } ?? false
    }

    static func covered(_ u: JSONValue, _ week: Int) -> Bool { u["warr"].double != 0 && Double(week) < u["warr"].double }

    /// If the broken item is under warranty: the supplier repairs it (1-2 days out of use), an info message is posted, and true is returned (no decision).
    @discardableResult
    public static func repairIfCovered(_ s: inout GameState, companyIndex i: Int, itemName: String, data: GameData) -> Bool {
        let co = s.companies[i]
        guard co.status == .open, let spec = data.catalog[co.type]?.allEquipment.first(where: { $0.name == itemName }) else { return false }
        let days = Double(1 + (HashedRandom.first("warr:\(co.id):\(s.week):\(spec.id)") < 0.5 ? 0 : 1))
        if spec.vehicleModels != nil {
            var list = co.value("veh").array
            guard let k = list.firstIndex(where: { $0["eq"].string == spec.id && $0["down"].double == 0 }), covered(list[k], s.week) else { return false }
            list[k]["down"] = .number(days)
            s.companies[i].set("veh", .array(list))
        } else {
            EquipmentUnits.ensureUnits(&s, companyIndex: i, equipmentID: spec.id)
            var units = s.companies[i].value("units")
            var list = units[spec.id].array
            guard let k = list.firstIndex(where: { $0["down"].double == 0 }), covered(list[k], s.week) else { return false }
            list[k]["down"] = .number(days)
            units[spec.id] = .array(list)
            s.companies[i].set("units", units)
        }
        s.addMessage(kind: "info", from: "Supplier", title: "\(itemName) broke down; repaired under warranty",
                     body: "The supplier repaired \(itemName) at \(co.name) at no cost. It is back in \(Int(days)) day\(days == 1 ? "" : "s").", companyID: co.id, tone: "n", status: "done")
        return true
    }
}
