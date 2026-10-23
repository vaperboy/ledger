import Foundation
import GameCore
import Countries
import Employees
import Finance

/// Equipment that goes with a person, not with the size of the business: a car per estate agent, a van per three cleaners, a
/// laptop for everyone. Their number limits what the people can do; own cars with mileage; fuel cost of bigger vans for couriers and
/// hauliers; the class of a taxi fleet and the nice car of a salesman in demand.
/// Originals: `PER`, `ruleOf`, `prodN`, `needOf`, `adjCap`, `fleetEff`, `taxiClass`, the `postWeek` own-car and fuel lines, the
/// 'demand' step of features/company/realistic_buying.js, `ACT.carallow` and `carOffer`/`car7`.
public enum PersonalEquipment {
    public struct Rule: Equatable, Sendable {
        /// Roles that use one. "*" means everyone.
        public var roles: [String]
        /// How many people share one.
        public var peoplePerUnit: Double
        /// How much of the work can go on without it (0 to 1).
        public var workWithout: Double
    }

    static let table: [String: Rule] = {
        func r(_ roles: [String], _ per: Double, _ rest: Double) -> Rule { Rule(roles: roles, peoplePerUnit: per, workWithout: rest) }
        return ["carclean:van": r(["carwash"], 2, 0), "handy:van": r(["handy"], 1, 0), "handy:tools": r(["handy"], 1, 0),
                "cleaning:van": r(["cleaner"], 3, 0.3), "cleaning:vac": r(["cleaner"], 1, 0),
                "drivsk:car": r(["instr"], 1, 0), "estate:car": r(["estate"], 1, 0.6),
                "construction:vans": r(["labour", "carp", "foreman"], 3, 0.3), "construction:tools": r(["labour", "carp", "foreman"], 3, 0),
                "electrician:vans": r(["elec"], 1, 0.2), "electrician:tools": r(["elec"], 1, 0),
                "plumber:vans": r(["plumb"], 1, 0.2), "plumber:tools": r(["plumb"], 1, 0),
                "event:van": r(["event", "av"], 3, 0.4), "taxi:car": r(["driver"], 1, 0), "courier:van": r(["courier"], 1, 0),
                "trucking:truck": r(["truckd"], 1, 0), "trucking:trail": r(["truckd"], 1, 0),
                "barber:chair": r(["barber"], 1, 0), "physio:bench": r(["physio"], 1, 0), "pets:groom": r(["groom"], 1, 0), "photo:cam": r(["photog"], 1, 0)]
    }()

    /// Original: `ruleOf`. Laptops and workstations go with every person.
    public static func rule(_ bd: Trade, _ e: EquipmentSpec, tables: TradeTables) -> Rule? {
        if let r = table[bd.id + ":" + e.id] { return r }
        if e.vehicleModels == nil, EquipmentMarket.kind(e, tradeID: bd.id, tables: tables) == "it" {
            let n = e.name.lowercased()
            if n.contains("laptop") || n.contains("workstation") { return Rule(roles: ["*"], peoplePerUnit: 1, workWithout: 0.25) }
        }
        return nil
    }

    static func ownerWorks(_ co: Company) -> Bool { co.managerID == nil && co.ownerHours > 0 }

    /// People who work with it, you included if you work in the business yourself. Original: `prodN`.
    public static func people(_ co: Company, _ bd: Trade, roles: [String]) -> Int {
        var n = co.staff.filter { (roles[0] == "*" || roles.contains($0.role)) && $0.noticeWeeks <= 0 }.count
        if ownerWorks(co) && (roles[0] == "*" || (bd.standardStaff.first.map { roles.contains($0.role) } ?? false)) { n += 1 }
        return n
    }

    /// How many the company needs. Original: `needOf`.
    public static func needed(_ co: Company, _ bd: Trade, _ e: EquipmentSpec, tables: TradeTables) -> Double {
        let std = CompanySetup.standardEquipment(bd, size: co.size)[e.id] ?? 0
        guard let rl = rule(bd, e, tables: tables) else { return e.isRequired ? max(1, std) : std }
        var w = Double(people(co, bd, roles: rl.roles))
        if co.staff.isEmpty && !ownerWorks(co) { return max(e.isRequired ? 1 : 0, std != 0 ? min(std, 1) : 0) }
        if bd.id == "estate" && e.id == "car" { w -= Double(co.staff.filter { $0.flag("ownCar") && $0.role == "estate" }.count) }
        if bd.id == "courier" && e.id == "van", let bike = bd.equipment.first(where: { $0.id == "bike" }) { w -= min(w, CapacityModel.equipmentCount(co, bike)) }
        return w > 0 ? (w / rl.peoplePerUnit).rounded(.up) : 0
    }

    /// "one per cleaner" or "one per 3 cleaners on a job". Original: `perText`.
    public static func perText(_ rl: Rule, tables: TradeTables) -> String {
        let first = rl.roles[0] == "*" ? "person" : (tables.roles[rl.roles[0]]?.name.lowercased() ?? "worker")
        return rl.peoplePerUnit == 1 ? "one per \(first)" : "one per \(Int(rl.peoplePerUnit)) \(first)\(first.hasSuffix("s") ? "" : "s") on a job"
    }

    /// Bigger or smaller vans change what a courier or haulier can carry. Original: `fleetEff`.
    static func fleetEfficiency(_ co: Company, _ e: EquipmentSpec, tables: TradeTables) -> Double {
        let veh = tables.raw["VEH"]
        let vs = co.value("veh").array.filter { $0["eq"].string == e.id && !veh[$0["model"].string].isNull }
        guard !vs.isEmpty, let std = e.vehicleModels?.first, !veh[std].isNull else { return 1 }
        let mean = vs.reduce(0) { $0 + veh[$1["model"].string][5].double } / Double(vs.count)
        return clamp(mean / veh[std][5].double, 0.75, 1.5)
    }

    /// Put the personal-equipment limits into the capacity parts. Original: `adjCap` (the 'capacity.core' step).
    /// Returns whether anything changed; the caller works out the new capacity.
    static func adjustCapacity(_ parts: inout [CapacityPart], _ co: Company, _ bd: Trade, _ w: World) -> Bool {
        let tables = w.catalog.tables
        var changed = false
        for e in bd.equipment {
            guard let rl = rule(bd, e, tables: tables) else { continue }
            let key = "eq:" + e.id
            let i = parts.firstIndex { $0.key == key }
            let need = needed(co, bd, e, tables: tables)
            if need <= 0 { if let i = i { parts.remove(at: i); changed = true }; continue }
            let rp = parts.indices.filter { idx in parts[idx].kind == .staff && (rl.roles[0] == "*" || rl.roles.contains { parts[idx].key == "role:" + $0 }) }
            if rp.isEmpty { continue }
            let base = rp.map { parts[$0].capacity }.min() ?? 0
            let have = CapacityModel.equipmentAvailable(co, e), cond = CapacityModel.equipmentCondition(co, e)
            let frac = min(1, have / need)
            let gate = e.isRequired && have < 0.01
            let eff = e.vehicleModels != nil && (bd.id == "courier" || bd.id == "trucking") ? fleetEfficiency(co, e, tables: tables) : 1
            let condF = cond >= 0.6 ? 1.002 : 0.7 + 0.5 * cond
            let cap = gate ? 0 : base * (frac + (1 - frac) * rl.workWithout) * condF * eff
            let part = CapacityPart(key: key, label: e.name + (gate ? " (required)" : ""), kind: gate ? .gate : .equip, have: jsRound(have * 10) / 10, need: need, capacity: cap, capacityPerUnit: base / need)
            if let i = i { parts[i] = part } else { parts.append(part) }
            if eff != 1 { for k in rp { parts[k].capacity *= eff } }
            changed = true
        }
        return changed
    }

    // MARK: Weekly costs

    /// Mileage for people on their own car, and the fuel cost of bigger vans for couriers and hauliers. Original: `postWeek` lines.
    static func weeklyCosts(_ s: inout GameState, companyIndex i: Int, _ bd: Trade, data: GameData) {
        let co = s.companies[i]
        let cur = World(state: s, data: data).currency(co)
        let own = co.staff.filter { $0.flag("ownCar") }.count
        if own > 0 { Payments.companyPays(&s, companyID: co.id, amount: cur.scaledPrice(4500) * 12 / 52 * Double(own), category: "oth") }
        if bd.id == "courier" || bd.id == "trucking" {
            let veh = data.catalog.tables.raw["VEH"]
            for v in co.value("veh").array {
                guard let e = bd.equipment.first(where: { $0.id == v["eq"].string }), let std = e.vehicleModels?.first,
                      !veh[v["model"].string].isNull, !veh[std].isNull else { continue }
                let x = veh[v["model"].string][4].double / max(0.05, veh[std][4].double) - 1
                if x > 0 { Payments.companyPays(&s, companyID: co.id, amount: x * cur.scaledPrice(450), category: "oth") }
            }
        }
    }

    // MARK: Taxi classes and nice cars (demand)

    /// Average class of a taxi fleet: 0 economy, 1 comfort, 2 premium. Original: `taxiClass`.
    public static func taxiClass(_ co: Company) -> Double {
        let cls: [String: Double] = ["car_s": 0, "car_ev": 0, "taxi_ev": 0, "taxi_cmf": 1, "taxi_xl": 1, "taxi_prm": 2, "car_lux": 2]
        let vs = co.value("veh").array.filter { $0["eq"].string == "car" }
        return vs.isEmpty ? 0 : vs.reduce(0) { $0 + (cls[$1["model"].string] ?? 0) } / Double(vs.count)
    }

    /// Demand factor of the fleet: better taxis draw more riders and carry a higher price; luxury cars help estate agents and dealers.
    /// Original: the 'demand' step 'taxi classes and cars for sales people'.
    static func demandFactor(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        var f = 1.0
        let veh = co.value("veh").array
        if bd.id == "taxi" && !veh.isEmpty {
            let cls = taxiClass(co), pm = Pricing.priceIndex(co, w), a = 0.12 * cls
            f = 1 + 0.07 * cls
            if pm > 1 {
                f *= pow(min(pm, 1 + a), bd.elasticity * 0.8)
                if pm > 1 + a + 0.25 { f *= pow((1 + a + 0.25) / pm, 2) }
            }
        }
        if (bd.id == "estate" || bd.id == "cardealer") && !veh.isEmpty {
            f *= 1 + 0.05 * Double(veh.filter { $0["model"].string == "car_lux" }.count) / Double(veh.count)
        }
        return f
    }

    // MARK: Own car or company car

    /// Does this trade let a salesperson use their own car? Original: `carOffer`.
    public static func offersOwnCar(_ co: Company, _ bd: Trade) -> Bool { bd.id == "estate" }

    /// Switch a person between a company car and their own car with mileage. Original: `ACT.carallow`.
    @discardableResult
    public static func toggleOwnCar(_ s: inout GameState, companyID: Int, staffID: Int, set: Bool? = nil) -> Bool? {
        guard let i = s.companyIndex(companyID), let k = s.companies[i].staff.firstIndex(where: { $0.id == staffID }) else { return nil }
        var st = s.companies[i].staff
        let on = set ?? !st[k].flag("ownCar")
        st[k].set("ownCar", on ? 1 : 0)
        s.companies[i].staff = st
        return on
    }
}
