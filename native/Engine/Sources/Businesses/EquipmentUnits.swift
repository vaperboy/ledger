import Foundation
import GameCore
import Countries
import Finance

/// Every machine is a unit that wears out on its own, and sometimes breaks down: it is out of use for a few days, and
/// the repair is free only while the warranty lasts. Originals: `unitsOf`, `newUnit`, `breakUnit`, `postWeek`, the
/// 'eqWeek.before' / 'eqWeek.after' steps and 'eqN' (engine/company/equipment_realism.js).
///
/// Units bought through `EquipmentMarket` carry their brand, class, reliability and (used) true wear; units bought by the
/// standard purchase (quick setup) have reliability 1 and class 1.
public enum EquipmentUnits {
    public static func kind(tradeID: String, equipmentID: String, tables: TradeTables) -> String {
        tables.raw["EQ_KINDS"][tradeID][equipmentID].string.isEmpty ? "mach" : tables.raw["EQ_KINDS"][tradeID][equipmentID].string
    }

    static func gameYear(_ week: Int) -> Int { GameCalendar.year(week: week) }

    /// Warranty length in years for a new unit of this kind. Original: `warrY`.
    static func warrantyYears(kind k: String, vehicleModel m: String?, class cls: Double, price: Double, tables: TradeTables, currency: Currency) -> Double {
        if k == "veh" {
            let c = tables.raw["VEH_CLASS"][m ?? ""].string
            if ["car", "van", "boxvan"].contains(c) { return (m ?? "").contains("ev") || (m ?? "").contains("electric") ? 5 : (m == "car_lux" || m == "taxi_prm") ? 4 : 3 }
            if c == "truck" || c == "bus" || c == "bike" || c == "scooter" { return 2 }
            if c == "plant" || c == "crane" { return 1 }
            return 2
        }
        if k == "tool" { return cls >= 2 ? 3 : 2 }
        if k == "it" || k == "pos" { return cls >= 2 ? 3 : 1 }
        if k == "furn" { return cls >= 2 ? 5 : 2 }
        if k == "soft" || k == "svc" { return 0 }
        return (price >= currency.scaledPrice(500000) ? 2 : 1) + (cls >= 2 ? 1 : 0)
    }

    /// A new unit, as bought. Original: `newUnit(.., 'new')`.
    static func newUnit(_ s: inout GameState, kind k: String, name: String, price: Double, years: Double,
                        brand: EquipmentMarket.Brand? = nil, used: EquipmentMarket.UsedOffer? = nil) -> JSONValue {
        if let u = used {
            // A second-hand unit: no warranty, and its true wear may differ from what the seller showed.
            return .object(["u": .number(Double(s.makeID())), "src": "used", "nm": .string(u.name), "yr": .number(Double(u.year)), "tc": .number(u.trueCondition),
                            "vis": .number(u.visibleCondition), "c0": .number(u.trueCondition), "warr": 0, "price": .number(u.price), "down": 0,
                            "rel": .number(u.reliability), "kr": .bool(u.knownToLast), "cls": .number(Double(u.cls))])
        }
        return .object(["u": .number(Double(s.makeID())), "src": "new", "nm": .string(brand?.name ?? name), "yr": .number(Double(gameYear(s.week))), "tc": 1, "vis": 1, "c0": 1,
                        "warr": .number(Double(s.week) + years * 52), "price": .number(price), "down": 0, "rel": .number(brand?.reliability ?? 1), "cls": .number(Double(brand?.cls ?? 1))])
    }

    /// Bring the list of units in line with the count in the equipment record. Original: `unitsOf`.
    static func ensureUnits(_ s: inout GameState, companyIndex i: Int, equipmentID id: String) {
        var units = s.companies[i].value("units")
        let rec = s.companies[i].value("eq")[id]
        if rec.isNull || !rec["sub"].isNull { if !units[id].isNull { units = removing(units, id); s.companies[i].set("units", units) }; return }
        var list = units[id].array
        let n = max(0, Int(jsRound(rec["n"].double)))
        while list.count < n {
            let name = rec["mods"].array.first?["nm"].string ?? ""
            list.append(.object(["u": .number(Double(s.makeID())), "src": "old", "nm": .string(name), "yr": .number(Double(gameYear(s.week) - 1)), "tc": .number(rec["cond"].double),
                                 "vis": .number(rec["cond"].double), "c0": .number(rec["cond"].double), "warr": 0,
                                 "price": .number(jsRound(rec["cost"].double / max(1, rec["n"].double))), "down": 0, "rel": .number(rec["rel"].isNull ? 1 : rec["rel"].double)]))
        }
        if list.count > n { list.removeLast(list.count - n) }
        units[id] = .array(list)
        s.companies[i].set("units", units)
    }

    static func removing(_ v: JSONValue, _ key: String) -> JSONValue { var o = v.object; o.removeValue(forKey: key); return .object(o) }

    /// Record units for equipment just bought. Called by `CompanySetup.buyEquipment`.
    static func recordPurchase(_ s: inout GameState, companyIndex i: Int, _ e: EquipmentSpec, tradeID: String, quantity q: Int, unitPrice: Double,
                               brand: EquipmentMarket.Brand? = nil, used: EquipmentMarket.UsedOffer? = nil, data: GameData) {
        let k = kind(tradeID: tradeID, equipmentID: e.id, tables: data.catalog.tables)
        guard k != "soft", k != "svc" else { return }
        // Units that existed before the purchase are listed first (they keep their own wear).
        let rec = s.companies[i].value("eq")[e.id]
        var prior = rec
        prior["n"] = .number(rec["n"].double - Double(q))
        var sc = s.companies[i]; var eqAll = sc.value("eq"); eqAll[e.id] = prior; sc.set("eq", eqAll)
        let saved = s.companies[i]; s.companies[i] = sc
        ensureUnits(&s, companyIndex: i, equipmentID: e.id)
        s.companies[i].set("eq", saved.value("eq"))
        let years = warrantyYears(kind: k, vehicleModel: nil, class: Double(brand?.cls ?? 1), price: unitPrice, tables: data.catalog.tables, currency: World(state: s, data: data).currency(s.companies[i]))
        var units = s.companies[i].value("units")
        var list = units[e.id].array
        for _ in 0..<q { list.append(newUnit(&s, kind: k, name: e.name, price: unitPrice, years: years, brand: brand, used: used)) }
        units[e.id] = .array(list)
        s.companies[i].set("units", units)
        syncCondition(&s, companyIndex: i, equipmentID: e.id)
    }

    /// The record's condition is the average of its units'. Original: `syncCond`.
    static func syncCondition(_ s: inout GameState, companyIndex i: Int, equipmentID id: String) {
        var eq = s.companies[i].value("eq")
        let list = s.companies[i].value("units")[id].array
        guard !eq[id].isNull else { return }
        if !list.isEmpty { eq[id]["cond"] = .number(list.reduce(0) { $0 + $1["tc"].double } / Double(list.count)) }
        eq[id]["_c"] = eq[id]["cond"]
        s.companies[i].set("eq", eq)
    }

    // MARK: Availability

    /// How many units can be used right now: units in for repair do not count. Original: step 'eqN'.
    static func availableCount(_ co: Company, equipmentID id: String, vehicle: Bool, count n0: Double) -> Double {
        var n = n0
        if vehicle {
            for v in co.value("veh").array where v["eq"].string == id && v["down"].double > 0 { n -= min(1, v["down"].double / 7) }
        } else {
            for u in co.value("units")[id].array where u["down"].double > 0 { n -= min(1, u["down"].double / 7) }
        }
        return max(0, n)
    }

    // MARK: The weekly steps

    /// Before the week's wear: changes of the record's condition (events, repairs) reach the units. Original: 'eqWeek.before'.
    static func before(_ s: inout GameState, companyIndex i: Int, _ bd: Trade, data: GameData) {
        let ids = s.companies[i].value("eq").object.keys.sorted()
        for id in ids where id != "fit" {
            var rec = s.companies[i].value("eq")[id]
            if rec["sub"].isNull && rec["soft"].isNull {
                let k = kind(tradeID: bd.id, equipmentID: id, tables: data.catalog.tables)
                if k == "soft" || k == "svc" {
                    rec["soft"] = .string(k == "svc" ? "svc" : "once")
                    if rec["ver"].isNull { rec["ver"] = .number(Double(s.week)) }
                    var eq = s.companies[i].value("eq"); eq[id] = rec; s.companies[i].set("eq", eq)
                    s.companies[i].set("units", removing(s.companies[i].value("units"), id))
                }
            }
            rec = s.companies[i].value("eq")[id]
            if !rec["sub"].isNull || !rec["soft"].isNull { continue }
            ensureUnits(&s, companyIndex: i, equipmentID: id)
            var list = s.companies[i].value("units")[id].array
            if !rec["_c"].isNull, !list.isEmpty {
                let d = rec["cond"].double - rec["_c"].double
                if d > 0.001 { for k in list.indices { list[k]["tc"] = .number(min(1, list[k]["tc"].double + d)) } }
                else if d < -0.001 {
                    let k = Int(s.random.next() * Double(list.count))
                    list[k]["tc"] = .number(max(0.05, list[k]["tc"].double + d * Double(list.count)))
                }
                var units = s.companies[i].value("units"); units[id] = .array(list); s.companies[i].set("units", units)
            }
        }
    }

    /// After the week: wear per unit, breakdowns, repairs. Original: 'eqWeek.after' (`postWeek`).
    static func after(_ s: inout GameState, companyIndex i: Int, _ bd: Trade, utilisation util: Double, data: GameData) {
        let co0 = s.companies[i]
        let mm = [1.5, 1.0, 0.6][min(2, max(0, co0.maintenance))]
        let open = co0.status == .open
        let tables = data.catalog.tables
        let cur = World(state: s, data: data).currency(co0)
        var reports: [String] = []
        for id in s.companies[i].value("eq").object.keys.sorted() where id != "fit" {
            guard let spec = bd.equipment.first(where: { $0.id == id }) else { continue }
            var rec = s.companies[i].value("eq")[id]
            if !rec["sub"].isNull {
                // A subscription is paid every month; a plan with too few seats slows the work down.
                Payments.companyPays(&s, companyID: s.companies[i].id, amount: rec["sub"]["fee"].double * 12 / 52, category: "oth")
                let plan = EquipmentMarket.book["plans"][rec["sub"]["tier"].int]
                rec["perf"] = .number(Double(EquipmentMarket.users(s.companies[i])) > plan["users"].double ? 0.85 : plan["perf"].double)
                rec["cond"] = 1; rec["_c"] = 1
                SoftwareProducts.useWeek(&s, companyIndex: i, record: &rec)
                var eq = s.companies[i].value("eq"); eq[id] = rec; s.companies[i].set("eq", eq)
                continue
            }
            if !rec["soft"].isNull {
                // Yearly updates of a licence are paid weekly; an old one-time licence loses some of its output.
                if rec["upd"].double > 0 { Payments.companyPays(&s, companyID: s.companies[i].id, amount: rec["upd"].double / 52, category: "oth") }
                if rec["soft"].string == "once", Double(s.week) - (rec["ver"].isNull ? Double(s.week) : rec["ver"].double) > spec.lifeYears * 52 { rec["perf"] = .number(min(rec["perf"].isNull ? 1 : rec["perf"].double, 0.92)) }
                rec["cond"] = 1; rec["_c"] = 1
                SoftwareProducts.useWeek(&s, companyIndex: i, record: &rec)
                var eq = s.companies[i].value("eq"); eq[id] = rec; s.companies[i].set("eq", eq)
                continue
            }
            let k = kind(tradeID: bd.id, equipmentID: id, tables: tables)
            var list = s.companies[i].value("units")[id].array
            var repairs: [(Double, String)] = []
            for n in list.indices {
                var u = list[n]
                if u["down"].double > 0 { u["down"] = .number(max(0, u["down"].double - 7)); list[n] = u; continue }
                let rel = u["rel"].isNull ? 1 : u["rel"].double
                u["tc"] = .number(clamp(u["tc"].double - 0.0012 * mm * rel * (0.4 + util) + (s.companies[i].maintenance == 2 ? 0.0009 : 0), 0.05, 1))
                list[n] = u
                if !open { continue }
                let age = Double(gameYear(s.week) - (u["yr"].isNull ? gameYear(s.week) : u["yr"].int))
                let p = 0.0035 * (1 + 6 * pow(1 - u["tc"].double, 2)) * rel * (u["kr"].bool ? 0.6 : 1 + max(0, age - 5) * 0.08)
                if s.random.next() < p {
                    let (text, cost) = breakUnit(&s, &u, spec: spec, kind: k, tables: tables, currency: cur)
                    list[n] = u
                    reports.append(text)
                    if cost > 0 { repairs.append((cost, "Repair: " + (u["nm"].string.isEmpty ? spec.name : u["nm"].string))) }
                }
            }
            var units = s.companies[i].value("units"); units[id] = .array(list); s.companies[i].set("units", units)
            for r in repairs { Payments.companyPays(&s, companyID: s.companies[i].id, amount: r.0, category: "oth", label: r.1); Vat.input(&s, companyIndex: i, net: r.0, data: data) }
            syncCondition(&s, companyIndex: i, equipmentID: id)
        }
        // Leased equipment: the monthly instalment, service included
        for (_, monthly) in s.companies[i].value("eqL").object.sorted(by: { $0.key < $1.key }) where monthly.double > 0 {
            Payments.companyPays(&s, companyID: s.companies[i].id, amount: monthly.double / 4.33, category: "oth")
            Vat.input(&s, companyIndex: i, net: monthly.double / 4.33, data: data)
        }
        // Vehicles
        var vehicles = s.companies[i].value("veh").array
        for n in vehicles.indices {
            var v = vehicles[n]
            if v["down"].double > 0 { v["down"] = .number(max(0, v["down"].double - 7)); vehicles[n] = v; continue }
            if !open { continue }
            let age = Double(gameYear(s.week) - (v["yr"].isNull ? gameYear(s.week) : v["yr"].int))
            let rel = v["rel"].isNull ? 1 : v["rel"].double
            let p = 0.003 * (1 + 6 * pow(1 - v["cond"].double, 2)) * rel * (v["kr"].bool ? 0.6 : 1 + max(0, age - 6) * 0.07) * (1 + v["km"].double / 600000)
            if s.random.next() < p {
                let spec = bd.equipment.first { $0.id == v["eq"].string }
                let vname = v["name"].string.isEmpty ? (spec?.name ?? "Vehicle") : v["name"].string
                let (text, cost) = breakVehicle(&s, &v, name: vname, tables: tables, currency: cur)
                reports.append(text)
                vehicles[n] = v
                if cost > 0 { s.companies[i].set("veh", .array(vehicles)); Payments.companyPays(&s, companyID: s.companies[i].id, amount: cost, category: "oth", label: "Repair: " + vname); Vat.input(&s, companyIndex: i, net: cost, data: data) }
            }
        }
        s.companies[i].set("veh", .array(vehicles))
        if !reports.isEmpty && open {
            let co = s.companies[i]
            let mgrName = co.managerID.flatMap { s.people[$0]?.name }
            s.addMessage(kind: "info", from: mgrName ?? "Workshop", title: reports.count > 1 ? "\(reports.count) breakdowns at \(co.name)" : "Breakdown at \(co.name)",
                         body: reports.joined(separator: " "), companyID: co.id, tone: "bad", status: "done")
        }
    }

    static func breakUnit(_ s: inout GameState, _ u: inout JSONValue, spec: EquipmentSpec, kind k: String, tables: TradeTables, currency cur: Currency) -> (String, Double) {
        let days = downtimeDays(k, &s, tables)
        let name = u["nm"].string.isEmpty ? spec.name : u["nm"].string
        if u["warr"].double != 0, Double(s.week) < u["warr"].double {
            u["down"] = .number(Double(days))
            return ("\(name) broke down. Covered by warranty, back in about \(days) days.", 0)
        }
        let price = u["price"].double != 0 ? u["price"].double : spec.cost
        let cost = max(cur.scaledPrice(400), jsRound(price * s.random.range(0.05, 0.2)))
        let down = max(1, Int(jsRound(Double(days) * 0.6)))
        u["down"] = .number(Double(down))
        return ("\(name) broke down. No warranty, so the repair cost \(cur.display(cost)). Back in about \(down) days.", cost)
    }

    static func breakVehicle(_ s: inout GameState, _ v: inout JSONValue, name: String, tables: TradeTables, currency cur: Currency) -> (String, Double) {
        let c = tables.raw["VEH_CLASS"][v["model"].string].string
        let days = downtimeDays(c.isEmpty ? "car" : c, &s, tables)
        if v["mode"].string == "lease" { v["warr"] = .number(max(v["warr"].double, Double(s.week + 1))) }
        if v["warr"].double != 0, Double(s.week) < v["warr"].double {
            v["down"] = .number(Double(days))
            return ("\(name) broke down. Covered by warranty, back in about \(days) days.", 0)
        }
        let cost = max(cur.scaledPrice(400), jsRound(v["cost"].double * s.random.range(0.05, 0.2)))
        let down = max(1, Int(jsRound(Double(days) * 0.6)))
        v["down"] = .number(Double(down))
        return ("\(name) broke down. No warranty, so the repair cost \(cur.display(cost)). Back in about \(down) days.", cost)
    }

    /// Whole days out of use, between the table's low and high. Original: `rint(W[0], W[1])`.
    static func downtimeDays(_ key: String, _ s: inout GameState, _ tables: TradeTables) -> Int {
        let w = tables.raw["BREAKDOWN_DAYS"][key]
        let lo = w.isNull ? 3 : w[0].int, hi = w.isNull ? 10 : w[1].int
        return s.random.int(lo, hi)
    }
}
