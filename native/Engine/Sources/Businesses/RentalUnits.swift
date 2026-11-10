import Foundation
import GameCore
import Countries
import Finance

public enum RentalUnits {
    public static var trades: Set<String> { ItemTradeGroups.rentals }
    static let allTrades: Set<String> = ["resrent", "comrent", "parking", "carrental", "hotel", "pcbang"]
    static let key = "w8u"
    static let unitPrefix = "w8u:", extraPrefix = "w8x:"

    struct TypeSpec { var id: String; var name: String; var ratio: Double; var share: Double; var fleet: Double }
    struct ExtraSpec { var name: String; var ratio: Double; var share: Double; var cost: Double }
    struct Spec {
        var kind: String, per: String, periods: Double
        var pools: [String], turn: Double, dmg: Double, chan: Double, adv: Double
        var tenure: Double, relet: Double
        var types: [TypeSpec], extras: [ExtraSpec]
    }

    static let specs: [String: Spec] = {
        guard let url = Bundle.module.url(forResource: "rental_units", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return [:] }
        var out: [String: Spec] = [:]
        for (k, v) in j["trades"].object {
            out[k] = Spec(kind: v["kind"].string, per: v["per"].string, periods: v["periods"].double,
                          pools: v["pools"].string.split(separator: ",").map(String.init), turn: v["turn"].double, dmg: v["dmg"].double,
                          chan: v["chan"].double, adv: v["adv"].double, tenure: v["tenure"].double, relet: v["relet"].double,
                          types: v["types"].array.map { TypeSpec(id: $0["id"].string, name: $0["n"].string, ratio: $0["ratio"].double, share: $0["share"].double, fleet: $0["fleet"].double) },
                          extras: v["extras"].array.map { ExtraSpec(name: $0["n"].string, ratio: $0["ratio"].double, share: $0["share"].double, cost: $0["cost"].double) })
        }
        return out
    }()

    static func isManaged(_ id: String) -> Bool { id.hasPrefix(unitPrefix) || id.hasPrefix(extraPrefix) }

    public struct Part: Equatable, Sendable { public var label: String; public var weekly: Double }

    struct UnitBase {
        var itemID: String
        var name: String
        var kindLabel: String
        var count: Double
        var periods: Double
        var share: Double
        var ratio: Double
        var overheadWeight: Double
        var parts: [Part]
        var status: String
        var rentedNow: Double?
    }

    static func weeklyOverhead(_ co: Company, _ bd: Trade, _ w: World, pools: [String]) -> Double {
        var total = co.lastWages + CompanyCosts.fixedOverhead(co, bd, w)
        let prem = co.value("prem")
        if !prem.isNull, !prem["owned"].bool, prem["m2"].double > 0 { total += prem["rent"].double * prem["m2"].double / 52 }
        let eq = co.value("eq")
        for (id, r) in eq.object where !pools.contains(id) && r["n"].double > 0 {
            if let spec = bd.allEquipment.first(where: { $0.id == id }) { total += r["cost"].double / max(1, spec.lifeYears) / 52 }
        }
        return total
    }

    static func loanInterestWeekly(_ s: GameState, loanID: Int) -> Double {
        guard loanID != 0, let l = s.loans.first(where: { $0.id == loanID }) else { return 0 }
        return l.balance * (s.economy.policyRate + l.margin) / 52
    }

    static func upkeepRate(_ co: Company) -> Double { [0.005, 0.011, 0.02][min(2, max(0, co.maintenance))] }

    static func bases(_ s: GameState, _ co: Company, _ bd: Trade, _ spec: Spec, _ w: World, mt: Double) -> [UnitBase] {
        switch spec.kind {
        case "property": return propertyBases(s, co, bd, spec, w)
        case "vehicle": return vehicleBases(s, co, bd, spec, w)
        default: return typeBases(s, co, bd, spec, w)
        }
    }

    static func propertyBases(_ s: GameState, _ co: Company, _ bd: Trade, _ spec: Spec, _ w: World) -> [UnitBase] {
        let maint = bd.trait("maint") ?? 0.008, ptax = bd.trait("ptax") ?? 0.0025
        let pr = (1 + 0.08 * co.priceLevel) * Knobs.effect(co, bd, "t", w)
        let housing = w.economy.housing
        let label = "Building"
        return co.properties.map { p in
            let lu = min(p.leasedUnits, p.units), fu = p.units - lu
            let occupied = lu + fu * (1 - p.vacancy)
            let idx0 = p.housingAtPurchase == 0 ? housing : p.housingAtPurchase
            let rentEff = p.rentPerUnit * pr * (0.93 + 0.07 * p.condition) * pow(housing / idx0, 0.6) * (1 + (co.reputation - 50) / 700)
            let parts = [Part(label: "Mortgage interest", weekly: loanInterestWeekly(s, loanID: p.loanID)),
                         Part(label: "Upkeep and repairs", weekly: p.value * maint / 52 * (1.7 - p.condition) * 1.1),
                         Part(label: "Property tax", weekly: p.value * ptax / 52)]
            var u = UnitBase(itemID: unitPrefix + "p\(p.id)", name: p.name, kindLabel: label, count: p.units, periods: p.units, share: max(occupied, 1e-6),
                             ratio: rentEff, overheadWeight: p.value, parts: parts, status: p.condition < 0.4 ? "repair" : "", rentedNow: occupied)
            u.ratio = rentEff
            return u
        }
    }

    static func vehicleBases(_ s: GameState, _ co: Company, _ bd: Trade, _ spec: Spec, _ w: World) -> [UnitBase] {
        let veh = co.value("veh").array
        guard !veh.isEmpty else { return [] }
        let tables = w.catalog.tables
        let avg = veh.reduce(0.0) { $0 + $1["cost"].double } / Double(veh.count)
        let country = w.country(co), cur = w.currency(co)
        let util = co.value("lastW")["util"].double
        let mc = upkeepRate(co)
        return veh.map { v in
            let model = v["model"].string
            let kind = tables.vehicles[model]?.kind ?? ""
            let depRate: Double = ["plane": 0.05, "bus": 0.1, "truck": 0.12, "plant": 0.1, "van": 0.15, "car": 0.16, "bike": 0.2][kind] ?? 0.15
            let cost = v["cost"].double
            var parts = [Part(label: "Depreciation", weekly: cost * depRate / 52)]
            switch v["mode"].string {
            case "lease": parts.append(Part(label: "Lease payment", weekly: v["lease"].double))
            case "fin": parts.append(Part(label: "Loan interest", weekly: loanInterestWeekly(s, loanID: v["loan"].int)))
            default: break
            }
            if v["mode"].string != "lease" { parts.append(Part(label: "Servicing and repairs", weekly: cost * mc * 1.3 / 52)) }
            if VehicleRunning.companyPaysFuelLine(bd) {
                parts.append(Part(label: "Fuel", weekly: VehicleRunning.vehicleWeek(v, bd: bd, util: util, tables: tables, country: country, currency: cur, fuelIndex: w.economy.fuel).fuel))
            }
            let baseName = v["name"].string.isEmpty ? (tables.vehicles[model]?.name ?? model) : v["name"].string
            let same = veh.filter { ($0["name"].string.isEmpty ? $0["model"].string : $0["name"].string) == (v["name"].string.isEmpty ? model : v["name"].string) }
            let nth = (same.firstIndex { $0["id"].int == v["id"].int } ?? 0) + 1
            let name = same.count > 1 ? "\(baseName) \(nth)" : baseName
            let ratio = avg > 0 ? pow(cost / avg, 0.7) : 1
            return UnitBase(itemID: unitPrefix + "v\(v["id"].int)", name: name, kindLabel: kind == "van" ? "Van" : "Car", count: 1, periods: spec.periods, share: 1, ratio: ratio,
                            overheadWeight: ratio, parts: parts, status: v["down"].double > 0 ? "repair" : "", rentedNow: nil)
        }
    }

    static func typeBases(_ s: GameState, _ co: Company, _ bd: Trade, _ spec: Spec, _ w: World) -> [UnitBase] {
        guard let main = spec.pools.first, let mainSpec = bd.allEquipment.first(where: { $0.id == main }) else { return [] }
        let n = CapacityModel.equipmentCount(co, mainSpec)
        guard n > 0 else { return [] }
        let mc = upkeepRate(co)
        var depPerUnit = 0.0, upkeepPerUnit = 0.0
        for id in spec.pools {
            guard let e = bd.allEquipment.first(where: { $0.id == id }) else { continue }
            let count = max(1, CapacityModel.equipmentCount(co, e))
            let rec = co.value("eq")[id]
            let total = rec["cost"].isNull ? e.cost * count : rec["cost"].double
            depPerUnit += total / count / max(1, e.lifeYears) / 52
            upkeepPerUnit += total / count * mc / 52
        }
        let fleetRatio = spec.types.reduce(0.0) { $0 + $1.fleet * $1.ratio }
        return spec.types.map { t in
            let cf = fleetRatio > 0 ? t.ratio / fleetRatio : 1
            let count = n * t.fleet
            return UnitBase(itemID: unitPrefix + t.id, name: t.name, kindLabel: spec.per == "night" ? "Room type" : "Seat class", count: count, periods: count * spec.periods,
                            share: t.share, ratio: t.ratio, overheadWeight: count * t.ratio,
                            parts: [Part(label: "Depreciation", weekly: count * depPerUnit * cf), Part(label: "Upkeep and repairs", weekly: count * upkeepPerUnit * cf)],
                            status: "", rentedNow: nil)
        }
    }

    public struct UnitEconomics: Equatable, Sendable {
        public var itemID: String
        public var name: String
        public var kindLabel: String
        public var per: String
        public var units: Double
        public var capacity: Double
        public var rented: Double
        public var occupancy: Double
        public var rate: Double
        public var marketRate: Double
        public var variablePerPeriod: Double
        public var fixedParts: [Part]
        public var fixedWeekly: Double
        public var costPerPeriod: Double
        public var breakEvenRate: Double
        public var weeklyProfit: Double
        public var status: String
        public var seasonIndex: Double
        public var booked: Int
    }

    struct Computed { var base: UnitBase; var econ: UnitEconomics }

    static func econ(_ b: UnitBase, _ spec: Spec, overhead: Double, overheadTotal: Double, market: Double, price: Double, rented: Double,
                     historyOccupancy: Double?, season: Double) -> UnitEconomics {
        let measured = b.periods > 0 ? rented / b.periods : 0
        let basis: Double = historyOccupancy ?? (measured > 0 ? measured : 1)
        let oh = overheadTotal > 0 ? overhead * b.overheadWeight / overheadTotal : 0
        var parts = b.parts
        parts.append(Part(label: "Wages, premises and overheads", weekly: oh))
        let fixed = parts.reduce(0.0) { $0 + $1.weekly }
        let tenureShare = spec.tenure > 0 ? spec.relet / spec.tenure : 0
        let varOnMarket = (spec.turn + spec.dmg + tenureShare) * market
        let varPerPeriod = varOnMarket + spec.chan * price
        let eff = max(basis, 0.01)
        let cost = varPerPeriod + (b.periods > 0 ? fixed / (b.periods * eff) : 0)
        let breakEven = (varOnMarket + (b.periods > 0 ? fixed / (b.periods * eff) : 0)) / max(1e-9, 1 - spec.chan)
        return UnitEconomics(itemID: b.itemID, name: b.name, kindLabel: b.kindLabel, per: spec.per, units: b.count, capacity: b.periods, rented: rented, occupancy: measured,
                             rate: price, marketRate: market, variablePerPeriod: varPerPeriod, fixedParts: parts, fixedWeekly: fixed, costPerPeriod: cost, breakEvenRate: breakEven,
                             weeklyProfit: rented * (price - varPerPeriod) - fixed, status: b.status, seasonIndex: season, booked: Int(saturating: (rented * spec.adv).rounded()))
    }

    static func season(_ w: World, _ bd: Trade) -> Double {
        let table = w.catalog.tables.seasons[bd.seasonKey] ?? []
        let m = GameCalendar.month(week: w.week) - 1
        return m >= 0 && m < table.count ? table[m] : 1
    }

    static func trailingOccupancy(_ r: ItemModels.Record?, capacity: Double) -> Double? {
        guard let r, capacity > 0 else { return nil }
        let last = r.history.suffix(13)
        guard !last.isEmpty else { return nil }
        let u = last.reduce(0.0) { $0 + $1.units } / Double(last.count)
        return u > 0 ? u / capacity : nil
    }

    public static func economics(_ s: GameState, companyID: Int, itemID: String, data: GameData) -> UnitEconomics? {
        computed(s, companyID: companyID, data: data).first { $0.base.itemID == itemID }?.econ
    }

    public static func allEconomics(_ s: GameState, companyID: Int, data: GameData) -> [UnitEconomics] {
        computed(s, companyID: companyID, data: data).map { $0.econ }
    }

    static func computed(_ s: GameState, companyID: Int, data: GameData) -> [Computed] {
        guard let co = s.company(companyID), let bd = data.catalog[co.type], allTrades.contains(bd.id), let spec = specs[bd.id], !co.value(SalesItems.key).isNull else { return [] }
        let w = World(state: s, data: data)
        let rows = SalesItems.rows(s, companyID: companyID, data: data)
        let list = bases(s, co, bd, spec, w, mt: 0)
        let season = season(w, bd)
        struct Line { var b: UnitBase; var row: SalesItem; var rented: Double; var price: Double; var hist: Double? }
        let lines: [Line] = list.compactMap { b in
            guard let row = rows.first(where: { $0.id == b.itemID }) else { return nil }
            return Line(b: b, row: row, rented: b.rentedNow ?? row.weeklyUnits, price: row.price * (1 - row.discountPercent / 100),
                        hist: trailingOccupancy(ItemModels.record(co, itemID: b.itemID), capacity: b.periods))
        }
        var direct = 0.0
        for l in lines {
            let e = econ(l.b, spec, overhead: 0, overheadTotal: 1, market: l.row.marketPrice, price: l.price, rented: l.rented, historyOccupancy: l.hist, season: season)
            direct += e.fixedWeekly + l.rented * e.variablePerPeriod
        }
        for row in rows where row.id.hasPrefix(extraPrefix) { direct += row.weeklyUnits * (ItemModels.record(co, itemID: row.id)?.cost ?? 0) }
        let booked = co.value(key)["exp"].double
        let overhead = booked > 0 ? max(0, booked - direct) : weeklyOverhead(co, bd, w, pools: spec.pools)
        let total = lines.reduce(0.0) { $0 + $1.b.overheadWeight }
        return lines.map { l in
            Computed(base: l.b, econ: econ(l.b, spec, overhead: overhead, overheadTotal: total, market: l.row.marketPrice, price: l.price, rented: l.rented, historyOccupancy: l.hist, season: season))
        }
    }

    public static func rateMultiplier(_ co: Company, _ bd: Trade, propertyID: Int) -> Double {
        guard trades.contains(bd.id), !co.value(SalesItems.key).isNull else { return 1 }
        let id = unitPrefix + "p\(propertyID)"
        guard let it = SalesItems.items(co, bd).first(where: { $0.id == id }) else { return 1 }
        return it.effectiveMultiplier
    }

    public static func sync(_ s: inout GameState, companyID: Int, data: GameData) {
        guard let i = s.companyIndex(companyID), s.companies[i].status == .open, let bd = data.catalog[s.companies[i].type], allTrades.contains(bd.id), let spec = specs[bd.id] else { return }
        let co = s.companies[i]
        let w = World(state: s, data: data)
        let mt = SalesItems.marketTicket(co, bd, w)
        guard mt > 0 else { return }
        let first = co.value(key).isNull
        let old = SalesItems.items(co, bd)
        let units = bases(s, co, bd, spec, w, mt: mt)
        let existing = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { (a, _) in a })
        var kept: [SalesItems.Item] = old.filter { !isManaged($0.id) && !(first && $0.id.hasPrefix("d")) }
        let isProperty = spec.kind == "property"
        var managed: [SalesItems.Item] = []
        let svc = SalesItems.isService(bd)
        func fresh(_ id: String, _ name: String, svc: Bool) -> SalesItems.Item {
            existing[id] ?? SalesItems.Item(id: id, name: name, isService: svc, unitShare: 0, ratio: 1, priceMultiplier: 1, discountPercent: 0, discountWeeks: 0, listedForGroup: false)
        }
        for u in units {
            var it = fresh(u.itemID, u.name, svc: true)
            it.name = u.name
            it.unitShare = u.share
            it.ratio = isProperty ? u.ratio / mt : u.ratio
            managed.append(it)
        }
        if !isProperty {
            for (k, x) in spec.extras.enumerated() {
                let id = extraPrefix + "\(k)"
                if !first && existing[id] == nil { continue }
                var it = fresh(id, x.name, svc: true)
                it.unitShare = x.share; it.ratio = x.ratio
                managed.append(it)
            }
        }
        let keptShare = kept.reduce(0.0) { $0 + $1.unitShare }
        let managedShare = managed.reduce(0.0) { $0 + $1.unitShare }
        if managedShare > 0 {
            let f = max(0, 1 - keptShare) / managedShare
            for k in managed.indices { managed[k].unitShare *= f }
        }
        if !isProperty {
            let keptWeight = kept.reduce(0.0) { $0 + $1.unitShare * $1.ratio }
            let mw = managed.reduce(0.0) { $0 + $1.unitShare * $1.ratio }
            if mw > 0 { let f = max(0.05, 1 - keptWeight) / mw; for k in managed.indices { managed[k].ratio *= f } }
        }
        kept.append(contentsOf: managed)
        SalesItems.store(&s, i, kept)
        var rec = s.companies[i].value("itemsv2").isNull ? [:] : s.companies[i].value("itemsv2").object
        let live = Set(kept.map { $0.id })
        for id in rec.keys where isManaged(id) && !live.contains(id) { rec.removeValue(forKey: id) }
        s.companies[i].set("itemsv2", .object(rec))
        for it in managed where it.id.hasPrefix(extraPrefix) {
            guard let k = Int(it.id.dropFirst(extraPrefix.count)), k < spec.extras.count else { continue }
            var r = ItemModels.record(s.companies[i], itemID: it.id) ?? ItemModels.Record(id: it.id, model: .svc)
            r.model = .svc
            r.cost = spec.extras[k].cost * mt * it.ratio
            ItemModels.put(&s, i, r)
        }
        for u in units {
            var r = ItemModels.record(s.companies[i], itemID: u.itemID) ?? ItemModels.Record(id: u.itemID, model: .rent)
            r.model = .rent
            r.stock = Int(saturating: u.count.rounded()); r.capacity = u.periods; r.status = u.status
            ItemModels.put(&s, i, r)
        }
        let wk = Books.expenses(s.companies[i].books.week), prev = s.companies[i].value(key)["exp"].double
        s.companies[i].set(key, .object(["w": .number(Double(s.week)), "exp": .number(wk > 0 ? (prev > 0 ? 0.9 * prev + 0.1 * wk : wk) : prev)]))
        refreshCosts(&s, i, companyID: companyID, spec: spec, data: data)
    }

    static func refreshCosts(_ s: inout GameState, _ i: Int, companyID: Int, spec: Spec, data: GameData) {
        let week = s.week
        let rows = SalesItems.rows(s, companyID: companyID, data: data)
        for c in computed(s, companyID: companyID, data: data) {
            guard var r = ItemModels.record(s.companies[i], itemID: c.base.itemID) else { continue }
            let rev = rows.first { $0.id == c.base.itemID }?.weeklyRevenue ?? 0
            let line = ItemModels.Week(week: week, units: c.econ.rented, revenue: rev, profit: rev - c.econ.rented * c.econ.variablePerPeriod - c.econ.fixedWeekly)
            if let last = r.history.last, last.week == week { r.history[r.history.count - 1] = line } else { ItemModels.log(&r, week: week, units: line.units, revenue: line.revenue, profit: line.profit) }
            ItemModels.put(&s, i, r)
        }
        for c in computed(s, companyID: companyID, data: data) {
            guard var r = ItemModels.record(s.companies[i], itemID: c.base.itemID) else { continue }
            r.cost = c.econ.costPerPeriod; r.fair = c.econ.marketRate; r.reserved = c.econ.booked
            ItemModels.put(&s, i, r)
        }
    }

    public static func weekly(_ s: inout GameState, _ i: Int, data: GameData) {
        guard s.companies.indices.contains(i), trades.contains(s.companies[i].type), s.companies[i].status == .open else { return }
        sync(&s, companyID: s.companies[i].id, data: data)
    }
}
