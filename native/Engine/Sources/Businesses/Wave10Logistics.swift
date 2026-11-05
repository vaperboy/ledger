import Foundation
import GameCore
import Countries
import Finance

/// Transport and logistics (taxi, courier, trucking, shipping, airline, wh3pl). Every service or route the company sells is an item: a ride type, a parcel
/// service, a lane, a voyage type, a route with its cabin, a warehouse service. The item's price is the live slider. Its cost is built from the company's own books:
/// the fleet's depreciation or lease, loan interest, servicing and (where the company pays it) fuel from the vehicle records, then wages, premises and fixed costs,
/// shared by the capacity the item uses and divided by what it really sold; plus the cost that only exists when one is sold (fuel carried in cost of sales, tolls,
/// port dues, handling, packaging, agent commission). Load factor (sold against capacity) and the empty share are shown with each item.
/// Nothing here moves cash: the attributions come from what the weekly model books, so a trade earns what it earned before at default prices.
/// Save keys: `items27` (the services become items), `itemsv2` (their records), `w10u` (set once the items were set up).
public enum Wave10 {
    public static var trades: Set<String> { ItemWaves.w10 }
    static let allTrades: Set<String> = ["taxi", "courier", "trucking", "shipping", "airline", "wh3pl"]
    static let key = "w10u"
    static let unitPrefix = "w10s:", extraPrefix = "w10x:"

    // MARK: Data

    struct TypeSpec { var id: String; var name: String; var ratio: Double; var share: Double; var fleet: Double; var weight: Double; var variable: Double; var empty: Double; var lead: Int; var note: String }
    struct ExtraSpec { var name: String; var ratio: Double; var share: Double; var cost: Double; var note: String }
    struct Spec {
        var per: String, pools: [String], chan: Double, adv: Double
        var types: [TypeSpec], extras: [ExtraSpec]
    }

    static let specs: [String: Spec] = {
        guard let url = Bundle.module.url(forResource: "wave10_services", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return [:] }
        var out: [String: Spec] = [:]
        for (k, v) in j["trades"].object {
            out[k] = Spec(per: v["per"].string, pools: v["pools"].string.split(separator: ",").map(String.init), chan: v["chan"].double, adv: v["adv"].double,
                          types: v["types"].array.map { TypeSpec(id: $0["id"].string, name: $0["n"].string, ratio: $0["ratio"].double, share: $0["share"].double, fleet: $0["fleet"].double,
                                                                 weight: $0["cw"].isNull ? 1 : $0["cw"].double, variable: $0["var"].double, empty: $0["empty"].double, lead: $0["lead"].int, note: $0["note"].string) },
                          extras: v["extras"].array.map { ExtraSpec(name: $0["n"].string, ratio: $0["ratio"].double, share: $0["share"].double, cost: $0["cost"].double, note: $0["note"].string) })
        }
        return out
    }()

    static func isManaged(_ id: String) -> Bool { id.hasPrefix(unitPrefix) || id.hasPrefix(extraPrefix) }

    /// What the item is, besides its economics: the empty share at a normal load, the lead time and a line of what it is in real life.
    public struct Info: Equatable, Sendable {
        public var economics: Wave8.UnitEconomics
        /// "service" (a ride type, lane, route) or "extra" (an add-on sold with it).
        public var kind: String
        /// Share of the running or seats that goes empty at a normal load (empty running, empty seats, empty racking).
        public var empty: Double
        public var leadDays: Int
        public var note: String
        /// Cost of the load that did not pay: what one empty share of the capacity costs per sold unit.
        public var emptyCostPerUnit: Double
    }

    // MARK: Fleet and pool costs (real, from the company's records)

    struct PoolCosts { var depreciation = 0.0, lease = 0.0, interest = 0.0, upkeep = 0.0, fuel = 0.0 }

    static func poolCosts(_ s: GameState, _ co: Company, _ bd: Trade, _ spec: Spec, _ w: World) -> PoolCosts {
        var p = PoolCosts()
        let mc = Wave8.upkeepRate(co)
        let tables = w.catalog.tables, country = w.country(co), cur = w.currency(co)
        let util = co.value("lastW")["util"].double
        for id in spec.pools {
            guard let e = bd.allEquipment.first(where: { $0.id == id }) else { continue }
            let life = max(1, e.lifeYears)
            if e.vehicleModels != nil {
                for v in co.value("veh").array where v["eq"].string == id {
                    let cost = v["cost"].double
                    switch v["mode"].string {
                    case "lease": p.lease += v["lease"].double
                    case "fin":
                        p.depreciation += cost / life / 52
                        p.interest += Wave8.loanInterestWeekly(s, loanID: v["loan"].int)
                        p.upkeep += cost * mc * 1.3 / 52
                    default:
                        p.depreciation += cost / life / 52
                        p.upkeep += cost * mc * 1.3 / 52
                    }
                    if VehicleRunning.companyPaysFuelLine(bd) {
                        p.fuel += VehicleRunning.vehicleWeek(v, bd: bd, util: util, tables: tables, country: country, currency: cur, fuelIndex: w.economy.fuel).fuel
                    }
                }
            } else {
                let count = max(1, CapacityModel.equipmentCount(co, e))
                let rec = co.value("eq")[id]
                let total = rec["cost"].isNull ? e.cost * count : rec["cost"].double
                p.depreciation += total / life / 52
                p.upkeep += total * mc / 52
            }
        }
        return p
    }

    // MARK: Items before prices are known

    struct Base {
        var itemID: String
        var spec: TypeSpec
        var count: Double
        var periods: Double
        var parts: [Wave8.Part]
        var status: String
    }

    /// Capacity of one unit of the main pool a week: what a normally set up company of the trade handles per vehicle, bay or rack.
    static func capacityPerUnit(_ bd: Trade, main: EquipmentSpec) -> Double {
        main.standardCount > 0 ? bd.normalCapacity / main.standardCount : 0
    }

    static func bases(_ s: GameState, _ co: Company, _ bd: Trade, _ spec: Spec, _ w: World) -> [Base] {
        guard let main = spec.pools.first, let mainSpec = bd.allEquipment.first(where: { $0.id == main }) else { return [] }
        let n = CapacityModel.equipmentCount(co, mainSpec)
        guard n > 0 else { return [] }
        let per = capacityPerUnit(bd, main: mainSpec)
        let p = poolCosts(s, co, bd, spec, w)
        let weight = spec.types.reduce(0.0) { $0 + $1.fleet * $1.weight }
        return spec.types.map { t in
            let f = weight > 0 ? t.fleet * t.weight / weight : 0
            var parts: [Wave8.Part] = []
            func add(_ label: String, _ v: Double) { if v * f > 0 { parts.append(Wave8.Part(label: label, weekly: v * f)) } }
            add("Depreciation", p.depreciation)
            add("Lease payments", p.lease)
            add("Loan interest", p.interest)
            add("Servicing and repairs", p.upkeep)
            add("Fuel and energy", p.fuel)
            return Base(itemID: unitPrefix + t.id, spec: t, count: n * t.fleet, periods: n * t.fleet * per, parts: parts, status: "")
        }
    }

    // MARK: Economics

    struct Computed { var base: Base; var econ: Wave8.UnitEconomics }

    /// A `Wave8.Spec` with this service's own variable cost: the rental maths (fixed cost over periods sold, variable cost on the going price) is the same.
    static func costSpec(_ spec: Spec, variable: Double) -> Wave8.Spec {
        Wave8.Spec(kind: "roomtype", per: spec.per, periods: 1, pools: spec.pools, turn: variable, dmg: 0, chan: spec.chan, adv: spec.adv, tenure: 0, relet: 0, types: [], extras: [])
    }

    static func computed(_ s: GameState, companyID: Int, data: GameData) -> [Computed] {
        guard let co = s.company(companyID), let bd = data.catalog[co.type], allTrades.contains(bd.id), let spec = specs[bd.id], !co.value(SalesItems.key).isNull else { return [] }
        let w = World(state: s, data: data)
        let rows = SalesItems.rows(s, companyID: companyID, data: data)
        let list = bases(s, co, bd, spec, w)
        let season = Wave8.season(w, bd)
        struct Line { var b: Base; var row: SalesItem; var sold: Double; var price: Double; var hist: Double? }
        let lines: [Line] = list.compactMap { b in
            guard let row = rows.first(where: { $0.id == b.itemID }) else { return nil }
            return Line(b: b, row: row, sold: row.weeklyUnits, price: row.price * (1 - row.discountPercent / 100),
                        hist: Wave8.trailingOccupancy(ItemModels.record(co, itemID: b.itemID), capacity: b.periods))
        }
        func unit(_ l: Line) -> Wave8.UnitBase {
            Wave8.UnitBase(itemID: l.b.itemID, name: l.b.spec.name, kindLabel: "Service", count: l.b.count, periods: l.b.periods, share: l.b.spec.share, ratio: l.b.spec.ratio,
                           overheadWeight: l.b.periods > 0 ? l.b.periods : l.b.count, parts: l.b.parts, status: l.b.status, rentedNow: nil)
        }
        var direct = 0.0
        for l in lines {
            let e = Wave8.econ(unit(l), costSpec(spec, variable: l.b.spec.variable), overhead: 0, overheadTotal: 1, market: l.row.marketPrice, price: l.price, rented: l.sold, historyOccupancy: l.hist, season: season)
            direct += e.fixedWeekly + l.sold * e.variablePerPeriod
        }
        for row in rows where row.id.hasPrefix(extraPrefix) { direct += row.weeklyUnits * (ItemModels.record(co, itemID: row.id)?.cost ?? 0) }
        let booked = co.value(key)["exp"].double
        let overhead = booked > 0 ? max(0, booked - direct) : Wave8.weeklyOverhead(co, bd, w, pools: spec.pools)
        let total = lines.reduce(0.0) { $0 + unit($1).overheadWeight }
        return lines.map { l in
            Computed(base: l.b, econ: Wave8.econ(unit(l), costSpec(spec, variable: l.b.spec.variable), overhead: overhead, overheadTotal: total, market: l.row.marketPrice, price: l.price,
                                                 rented: l.sold, historyOccupancy: l.hist, season: season))
        }
    }

    /// Everything about the service behind one item, at its current price. Nil for an item that is not one of the wave's services.
    public static func economics(_ s: GameState, companyID: Int, itemID: String, data: GameData) -> Wave8.UnitEconomics? {
        computed(s, companyID: companyID, data: data).first { $0.base.itemID == itemID }?.econ
    }

    public static func allEconomics(_ s: GameState, companyID: Int, data: GameData) -> [Wave8.UnitEconomics] {
        computed(s, companyID: companyID, data: data).map { $0.econ }
    }

    /// Economics plus the real-life facts of the item (empty share, lead time, what it is). Extras have a cost only.
    public static func info(_ s: GameState, companyID: Int, itemID: String, data: GameData) -> Info? {
        guard let co = s.company(companyID), let spec = specs[co.type] else { return nil }
        if let c = computed(s, companyID: companyID, data: data).first(where: { $0.base.itemID == itemID }) {
            let e = c.econ
            let emptyCost = c.base.spec.empty > 0 && e.capacity > 0 ? e.fixedWeekly * c.base.spec.empty / max(1, e.rented) : 0
            return Info(economics: e, kind: "service", empty: c.base.spec.empty, leadDays: c.base.spec.lead, note: c.base.spec.note, emptyCostPerUnit: emptyCost)
        }
        guard itemID.hasPrefix(extraPrefix), let k = Int(itemID.dropFirst(extraPrefix.count)), k < spec.extras.count,
              let r = ItemModels.record(co, itemID: itemID) else { return nil }
        let x = spec.extras[k]
        let e = Wave8.UnitEconomics(itemID: itemID, name: x.name, kindLabel: "Add-on", per: spec.per, units: 0, capacity: 0, rented: r.history.last?.units ?? 0, occupancy: 0,
                                    rate: 0, marketRate: r.fair, variablePerPeriod: r.cost, fixedParts: [], fixedWeekly: 0, costPerPeriod: r.cost, breakEvenRate: r.cost,
                                    weeklyProfit: r.history.last?.profit ?? 0, status: "", seasonIndex: 1, booked: 0)
        return Info(economics: e, kind: "extra", empty: 0, leadDays: 0, note: x.note, emptyCostPerUnit: 0)
    }

    // MARK: Setting the services up as items

    /// Put the company's services in as items and records and refresh their costs. Idempotent. Old titles-only items that the services replace are dropped on the
    /// first run; items the owner added are kept.
    public static func sync(_ s: inout GameState, companyID: Int, data: GameData) {
        guard let i = s.companyIndex(companyID), s.companies[i].status == .open, let bd = data.catalog[s.companies[i].type], allTrades.contains(bd.id), let spec = specs[bd.id] else { return }
        let co = s.companies[i]
        let w = World(state: s, data: data)
        guard SalesItems.marketTicket(co, bd, w) > 0 else { return }
        let first = co.value(key).isNull
        let old = SalesItems.items(co, bd)
        let list = bases(s, co, bd, spec, w)
        guard !list.isEmpty else { return }
        let existing = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        var kept: [SalesItems.Item] = old.filter { !isManaged($0.id) && !(first && $0.id.hasPrefix("d")) }
        var managed: [SalesItems.Item] = []
        func fresh(_ id: String, _ name: String) -> SalesItems.Item {
            existing[id] ?? SalesItems.Item(id: id, name: name, isService: true, unitShare: 0, ratio: 1, priceMultiplier: 1, discountPercent: 0, discountWeeks: 0, listedForGroup: false)
        }
        for b in list {
            var it = fresh(b.itemID, b.spec.name)
            it.name = b.spec.name; it.unitShare = b.spec.share; it.ratio = b.spec.ratio
            managed.append(it)
        }
        for (k, x) in spec.extras.enumerated() {
            let id = extraPrefix + "\(k)"
            if !first && existing[id] == nil { continue }   // an extra the owner removed stays removed
            var it = fresh(id, x.name)
            it.name = x.name; it.unitShare = x.share; it.ratio = x.ratio
            managed.append(it)
        }
        // Shares add up to one with the owner's own items and the ratios keep the revenue weights at one: the trade earns what it earned.
        let keptShare = kept.reduce(0.0) { $0 + $1.unitShare }
        let managedShare = managed.reduce(0.0) { $0 + $1.unitShare }
        if managedShare > 0 { let f = max(0, 1 - keptShare) / managedShare; for k in managed.indices { managed[k].unitShare *= f } }
        let keptWeight = kept.reduce(0.0) { $0 + $1.unitShare * $1.ratio }
        let mw = managed.reduce(0.0) { $0 + $1.unitShare * $1.ratio }
        if mw > 0 { let f = max(0.05, 1 - keptWeight) / mw; for k in managed.indices { managed[k].ratio *= f } }
        kept.append(contentsOf: managed)
        SalesItems.store(&s, i, kept)
        var rec = s.companies[i].value("itemsv2").isNull ? [:] : s.companies[i].value("itemsv2").object
        let live = Set(kept.map { $0.id })
        for id in rec.keys where isManaged(id) && !live.contains(id) { rec.removeValue(forKey: id) }
        s.companies[i].set("itemsv2", .object(rec))
        let mt = SalesItems.marketTicket(s.companies[i], bd, w)
        for it in managed where it.id.hasPrefix(extraPrefix) {
            guard let k = Int(it.id.dropFirst(extraPrefix.count)), k < spec.extras.count else { continue }
            var r = ItemModels.record(s.companies[i], itemID: it.id) ?? ItemModels.Record(id: it.id, model: .svc)
            r.model = .svc
            r.cost = spec.extras[k].cost * mt * it.ratio
            ItemModels.put(&s, i, r)
        }
        for b in list {
            var r = ItemModels.record(s.companies[i], itemID: b.itemID) ?? ItemModels.Record(id: b.itemID, model: .svc)
            r.model = .svc
            r.stock = max(1, Int(b.count.rounded())); r.capacity = b.periods; r.status = b.status; r.leadDays = b.spec.lead
            ItemModels.put(&s, i, r)
        }
        // A smoothed weekly cost of the company (monthly bills would otherwise make the item costs jump).
        let wk = Books.expenses(s.companies[i].books.week), prev = s.companies[i].value(key)["exp"].double
        s.companies[i].set(key, .object(["w": .number(Double(s.week)), "exp": .number(wk > 0 ? (prev > 0 ? 0.9 * prev + 0.1 * wk : wk) : prev)]))
        refreshCosts(&s, i, companyID: companyID, data: data)
    }

    /// This week's true line in every item's history (units sold, revenue, profit), then the cost of one unit from the books.
    static func refreshCosts(_ s: inout GameState, _ i: Int, companyID: Int, data: GameData) {
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

    /// Weekly, after `ItemModels.weeklyTick`: set up new services, refresh costs and the history line.
    public static func weekly(_ s: inout GameState, _ i: Int, data: GameData) {
        guard s.companies.indices.contains(i), trades.contains(s.companies[i].type), s.companies[i].status == .open else { return }
        sync(&s, companyID: s.companies[i].id, data: data)
    }
}
