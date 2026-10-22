import Foundation
import GameCore
import Countries
import Finance

/// What a company owns, unit by unit, as the Owned and Fleet tabs show it. Original: `ownTab`, `unitRow`, `vehTab`, `vehRow`, `softTab`.
public extension EquipmentMarket {
    struct UnitRow: Identifiable, Equatable, Sendable {
        public var id: Int
        public var name: String
        public var year: Int
        public var boughtUsed: Bool
        public var warranty: String
        public var wear: String
        /// What the owner can tell of the condition, 0 to 1
        public var seenCondition: Double
        public var daysInRepair: Int
    }

    struct VehicleRow: Identifiable, Equatable, Sendable {
        public var id: Int
        public var name: String
        public var mode: String          // own, fin, lease
        public var kilometres: Int
        public var warranty: String
        public var wear: String
        public var seenCondition: Double
        public var daysInRepair: Int
        public var monthlyLease: Double
        public var bookValue: Double
    }

    struct Owned: Identifiable, Equatable, Sendable {
        public var id: String { equipmentID }
        public var equipmentID: String
        public var name: String
        public var kind: String
        public var count: Double
        public var leasedCount: Double
        public var leaseMonthly: Double
        public var units: [UnitRow]
        public var vehicles: [VehicleRow]
        /// Subscription plan name and monthly fee, or licence description, for software
        public var subscription: String?
        public var licence: String?
        public var subscriptionMonthly: Double
        public var outdated: Bool
        public var bookValue: Double
        public var serviceCost: Double
    }

    private static func warrantyText(_ u: JSONValue, week: Int) -> String {
        if u["src"].string == "lease" || u["mode"].string == "lease" { return "Service included in lease" }
        if u["warr"].double > 0 && Double(week) < u["warr"].double { return "Warranty to " + GameCalendar.monthString(week: Int(u["warr"].double)) }
        return u["src"].string == "used" ? "Sold as seen, no warranty" : "Warranty ended"
    }

    static func owned(_ s: GameState, companyID: Int, data: GameData) -> [Owned] {
        guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return [] }
        let tables = data.catalog.tables
        var out: [Owned] = []
        for e in bd.equipment where e.id != "fit" {
            if let _ = e.vehicleModels {
                let rows = co.value("veh").array.filter { $0["eq"].string == e.id }.map { v in
                    VehicleRow(id: v["id"].int, name: v["name"].string, mode: v["mode"].string, kilometres: v["km"].int, warranty: warrantyText(v, week: s.week),
                               wear: wearWord(seen(v)), seenCondition: seen(v), daysInRepair: v["down"].int, monthlyLease: v["lease"].double, bookValue: v["bv"].double)
                }
                if !rows.isEmpty { out.append(Owned(equipmentID: e.id, name: e.name, kind: "veh", count: Double(rows.count), leasedCount: 0, leaseMonthly: 0, units: [], vehicles: rows,
                                                    subscription: nil, licence: nil, subscriptionMonthly: 0, outdated: false, bookValue: rows.reduce(0) { $0 + $1.bookValue }, serviceCost: 0)) }
                continue
            }
            let rec = co.value("eq")[e.id]
            let leased = co.value("lease")[e.id].double
            if rec.isNull && leased == 0 { continue }
            let units = rec.isNull || !rec["sub"].isNull || !rec["soft"].isNull ? [] : co.value("units")[e.id].array.map { u in
                UnitRow(id: u["u"].int, name: (u["nm"].string.isEmpty ? e.name : u["nm"].string), year: u["yr"].int, boughtUsed: u["src"].string == "used",
                        warranty: warrantyText(u, week: s.week), wear: wearWord(seen(u)), seenCondition: seen(u), daysInRepair: u["down"].int)
            }
            var licence: String?, sub: String?
            if !rec["sub"].isNull {
                let tier = book["plans"][rec["sub"]["tier"].int]["name"].string
                sub = "\(rec["sub"]["nm"].string) · \(tier) plan"
            } else if !rec["soft"].isNull {
                licence = rec["soft"].string == "svc" ? "Done" : rec["soft"].string == "upfront" ? "Licence with yearly updates" : "Licence owned"
            }
            out.append(Owned(equipmentID: e.id, name: e.name, kind: kind(e, tradeID: bd.id, tables: tables), count: rec["n"].double, leasedCount: leased,
                             leaseMonthly: co.value("eqL")[e.id].double, units: units, vehicles: [], subscription: sub, licence: licence,
                             subscriptionMonthly: rec["sub"]["fee"].double, outdated: (rec["perf"].isNull ? 1 : rec["perf"].double) < 0.95 && !rec["soft"].isNull,
                             bookValue: rec["bv"].double, serviceCost: jsRound(rec["cost"].double * 0.04 * (1 - Suppliers.repairDiscount(s, company: co, data: data)))))
        }
        return out
    }

    /// Pay for servicing all units of one kind of equipment: 4% of what it cost, and the wear is partly undone. Original: `repaireq`.
    @discardableResult
    static func serviceAll(_ s: inout GameState, companyID: Int, equipmentID: String, data: GameData) -> Result {
        guard let i = s.companyIndex(companyID) else { return .notPossible }
        let rec = s.companies[i].value("eq")[equipmentID]
        guard !rec.isNull else { return .notPossible }
        let c = jsRound(rec["cost"].double * 0.04 * (1 - Suppliers.repairDiscount(s, company: s.companies[i], data: data)))   // the repair supplier's discount (fixDisc)
        if s.companies[i].cash < c { return .notEnoughCash }
        Payments.companyPays(&s, companyID: companyID, amount: c, category: "oth", label: "Equipment service")
        // The record's condition rises; the units follow at the start of next week ('eqWeek.before').
        var eq = s.companies[i].value("eq")
        eq[equipmentID]["cond"] = .number(min(1, eq[equipmentID]["cond"].double + 0.3))
        s.companies[i].set("eq", eq)
        return .ok
    }
}
