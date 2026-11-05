import Foundation
import GameCore
import Countries
import Finance

/// Venues with capacity tickets and passes (nightclub, casino, fun, skires, indoorski, gym, club). The venue sells entry tickets by peak and off-peak, tables,
/// lift passes, memberships, season passes, lessons, parties, bar, food and merchandise; each is an item with its own real cost: the direct cost of one sale
/// (bottle, pour, meal, duty, comps) plus its share of what the venue costs a week (wages, rent, depreciation, loans, the lifts, the cooling plant) divided by
/// what it really sold. The profit or loss slider on the price is true to that cost. Cost of sales moves with the volume sold, not with the price
/// the owner charges (`cogsFactor`, exactly 1 at default prices). The football club keeps its own model (`FootballModel`): its items are attributed from the
/// club's own week and the match and season ticket price moves the existing ticket level (`clubTixShift`, exactly 0 at default prices).
/// Save keys: `items27` (the items), `itemsv2` (their records), `w9u` (set once the items were set up).
public enum VenueItems {
    public static var trades: Set<String> { ItemTradeGroups.venues }
    static let allTrades: Set<String> = ["nightclub", "casino", "fun", "skires", "indoorski", "gym", "club"]
    static let key = "w9u"
    static let prefix = "w9:"

    // MARK: Data

    struct Def {
        var id: String, name: String, kind: String, model: ItemModels.Model
        var ratio: Double, share: Double, fleet: Double, vc: Double, use: Double, edge: Double, churn: Double, days: Double
        var recipe: String
    }
    struct Spec { var per: String, sessions: Double, sessionName: String, unit: String, source: String, items: [Def] }

    static let specs: [String: Spec] = {
        guard let url = Bundle.module.url(forResource: "venue_items", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return [:] }
        var out: [String: Spec] = [:]
        for (k, v) in j["trades"].object {
            out[k] = Spec(per: v["per"].string, sessions: v["sessions"].double, sessionName: v["sessionName"].string, unit: v["unit"].string, source: v["source"].string,
                          items: v["items"].array.map {
                              Def(id: $0["id"].string, name: $0["n"].string, kind: $0["kind"].string, model: ItemModels.Model(rawValue: $0["model"].string) ?? .svc,
                                  ratio: $0["ratio"].double, share: $0["share"].double, fleet: $0["fleet"].double, vc: $0["vc"].double, use: $0["use"].double,
                                  edge: $0["edge"].double, churn: $0["churn"].double, days: $0["days"].double, recipe: $0["recipe"].string)
                          })
        }
        return out
    }()

    static func isManaged(_ id: String) -> Bool { id.hasPrefix(prefix) }

    // MARK: Economics of one item

    public struct Part: Equatable, Sendable { public var label: String; public var weekly: Double }

    public struct Economics: Equatable, Sendable {
        public var itemID: String
        public var name: String
        public var kindLabel: String
        public var modelLabel: String
        /// "guest", "skier day", "member-week" ... the unit one sale is.
        public var per: String
        /// What the item can sell a week (0 = no capacity), and per night, day or match.
        public var capacity: Double
        public var capacityPerSession: Double
        public var sessionName: String
        public var sold: Double
        public var occupancy: Double
        public var price: Double
        public var marketPrice: Double
        /// Direct cost of one sale (bottle, meal, duty, comps), independent of the price charged.
        public var variablePerSale: Double
        public var fixedParts: [Part]
        public var fixedWeekly: Double
        public var costPerSale: Double
        public var breakEvenPrice: Double
        public var weeklyRevenue: Double
        public var weeklyProfit: Double
        /// Month demand index of the trade (1 = an average month).
        public var seasonIndex: Double
        /// Sales booked in advance for the coming weeks (parties, hire, tournaments), an estimate.
        public var booked: Int
        /// Members or pass holders (passes and memberships only), and the share of them lost a month.
        public var holders: Double
        public var churnMonthly: Double
        /// Casino: house edge, and the money played per sale that gives the price.
        public var edge: Double
        public var playedPerSale: Double
        /// Visits a pass or booking covers, and the whole price of it at the price per visit now.
        public var bundleDays: Double
        public var bundlePrice: Double
        /// What it is made of, and where it comes from.
        public var recipe: String
        public var isSub: Bool
    }

    struct Computed { var def: Def; var itemID: String; var econ: Economics }

    static func season(_ w: World, _ bd: Trade) -> Double {
        let table = w.catalog.tables.seasons[bd.seasonKey] ?? []
        let m = GameCalendar.month(week: w.week) - 1
        return m >= 0 && m < table.count ? table[m] : 1
    }

    static func trailing(_ r: ItemModels.Record?, _ field: (ItemModels.Week) -> Double) -> Double? {
        guard let r else { return nil }
        let last = r.history.suffix(13)
        guard !last.isEmpty else { return nil }
        let v = last.reduce(0.0) { $0 + field($1) } / Double(last.count)
        return v > 0 ? v : nil
    }

    static func fallbackOverhead(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        var total = co.lastWages + CompanyCosts.fixedOverhead(co, bd, w)
        let prem = co.value("prem")
        if !prem.isNull, !prem["owned"].bool, prem["m2"].double > 0 { total += prem["rent"].double * prem["m2"].double / 52 }
        for (id, r) in co.value("eq").object where r["n"].double > 0 {
            if let spec = bd.allEquipment.first(where: { $0.id == id }) { total += r["cost"].double / max(1, spec.lifeYears) / 52 }
        }
        return total
    }

    /// Scale on the direct costs so that at default prices the venue's cost of sales is exactly the trade's share (what the books book).
    static func costScale(_ items: [SalesItems.Item], _ spec: Spec, _ bd: Trade) -> Double {
        var weight = 0.0, direct = 0.0
        for d in spec.items {
            guard let it = items.first(where: { $0.id == prefix + d.id }) else { continue }
            weight += it.unitShare * it.ratio
            direct += it.unitShare * it.ratio * d.vc
        }
        return direct > 0 ? bd.costOfSales * weight / direct : 1
    }

    static func churnBase(_ bd: Trade) -> Double { bd.trait("churn") ?? 0.006 }

    /// Casino: this week's luck (the venue's win against its edge) lands on the games, not on food.
    static func luck(_ co: Company, _ bd: Trade) -> Double {
        guard bd.trait("variance") != nil else { return 1 }
        let f = co.value("fm")["lastHold"]
        return f.isNull ? 1 : f.double
    }

    static func computed(_ s: GameState, companyID: Int, data: GameData) -> [Computed] {
        guard let co = s.company(companyID), let bd = data.catalog[co.type], allTrades.contains(bd.id), let spec = specs[bd.id], !co.value(SalesItems.key).isNull else { return [] }
        if spec.source == "club" { return clubComputed(s, co, bd, spec, data) }
        let w = World(state: s, data: data)
        let rows = SalesItems.rows(s, companyID: companyID, data: data)
        let items = SalesItems.items(co, bd)
        let k = costScale(items, spec, bd)
        let season = season(w, bd)
        let capTotal = co.value("lastW")["cap"].double
        let present = Set(items.map { $0.id })
        let fleetSum = spec.items.reduce(0.0) { acc, d in acc + (d.fleet > 0 && present.contains(prefix + d.id) ? d.fleet : 0) }
        struct Line { var d: Def; var row: SalesItem; var sold: Double; var rev: Double; var price: Double; var market: Double; var cap: Double; var vc: Double }
        var lines: [Line] = spec.items.compactMap { d in
            guard let row = rows.first(where: { $0.id == prefix + d.id }) else { return nil }
            let cap = fleetSum > 0 && d.fleet > 0 ? capTotal * d.fleet / fleetSum / max(0.01, d.use) : 0
            return Line(d: d, row: row, sold: row.weeklyUnits, rev: row.weeklyRevenue, price: row.price * (1 - row.discountPercent / 100), market: row.marketPrice, cap: cap, vc: d.vc * k * row.marketPrice)
        }
        let luckF = luck(co, bd)
        if luckF != 1 {
            let all = lines.reduce(0.0) { $0 + $1.rev }, edge = lines.reduce(0.0) { $0 + ($1.d.edge > 0 ? $1.rev : 0) }
            if edge > 0 { let f = 1 + (luckF - 1) * all / edge; for n in lines.indices where lines[n].d.edge > 0 { lines[n].rev *= f } }
        }
        let direct = lines.reduce(0.0) { $0 + $1.sold * $1.vc }
        let booked = co.value(key)["exp"].double
        let overhead = booked > 0 ? max(0, booked - direct) : fallbackOverhead(co, bd, w)
        let revSum = lines.reduce(0.0) { $0 + $1.rev }, useSum = lines.reduce(0.0) { $0 + $1.sold * $1.d.use }
        let weights: [Double] = lines.map { l in
            let a = revSum > 0 ? l.rev / revSum : 1 / Double(max(1, lines.count)), b = useSum > 0 ? l.sold * l.d.use / useSum : 1 / Double(max(1, lines.count))
            return 0.5 * a + 0.5 * b
        }
        let wSum = max(1e-12, weights.reduce(0, +))
        return lines.indices.map { n in
            let l = lines[n]
            let id = prefix + l.d.id
            let rec = ItemModels.record(co, itemID: id)
            let oh = overhead * weights[n] / wSum
            let basis = max(trailing(rec) { $0.units } ?? l.sold, l.cap > 0 ? 0.01 * l.cap : 0.5)
            let fixedPerSale = oh / basis
            let cost = l.vc + fixedPerSale
            let sub = l.d.model == .sub
            let wk = bd.trait("churn") != nil ? churnBase(bd) * (1.5 - co.quality / 100) : churnBase(bd)
            let holders = sub ? (l.d.days > 0 ? l.sold * 52 / l.d.days : l.sold) : 0
            let adv: Double = (l.d.kind == "Booking" || l.d.kind == "Event") ? 2 : 0
            let parts = [Part(label: "Wages, premises, plant and overheads", weekly: oh)]
            let e = Economics(itemID: id, name: l.row.name, kindLabel: l.d.kind, modelLabel: l.d.model.label, per: spec.per, capacity: l.cap,
                              capacityPerSession: spec.sessions > 0 ? l.cap / spec.sessions : l.cap, sessionName: spec.sessionName, sold: l.sold,
                              occupancy: l.cap > 0 ? l.sold / l.cap : 0, price: l.price, marketPrice: l.market, variablePerSale: l.vc, fixedParts: parts, fixedWeekly: oh,
                              costPerSale: cost, breakEvenPrice: cost, weeklyRevenue: l.rev, weeklyProfit: l.rev - l.sold * l.vc - oh, seasonIndex: season,
                              booked: Int((l.sold * adv).rounded()), holders: holders, churnMonthly: sub ? 1 - pow(1 - min(0.99, wk * max(0.1, l.d.churn)), 52.0 / 12) : 0,
                              edge: l.d.edge, playedPerSale: l.d.edge > 0 ? l.price / l.d.edge : 0, bundleDays: l.d.days, bundlePrice: l.d.days > 0 ? l.price * l.d.days : 0,
                              recipe: l.d.recipe, isSub: sub)
            return Computed(def: l.d, itemID: id, econ: e)
        }
    }

    // MARK: The football club (own model, attributed)

    /// Matchday revenue split by the item weights among match tickets, season tickets and boxes; the rest read from the club's own week (`fm.wk`).
    static func clubComputed(_ s: GameState, _ co: Company, _ bd: Trade, _ spec: Spec, _ data: GameData) -> [Computed] {
        let w = World(state: s, data: data)
        let rows = SalesItems.rows(s, companyID: co.id, data: data)
        let items = SalesItems.items(co, bd)
        let wk = co.value("fm")["wk"]
        let M = Double(FootballModel.readLeague(s, co.countryCode)?.matchWeeks ?? 38)
        let homeShare = (M / 2) / 52
        let lastHome = co.value(key)["mdh"].double
        let md = wk["match"].double > 0 ? wk["match"].double : lastHome
        let matchDefs = spec.items.filter { ["match", "season", "box"].contains($0.id) }
        let mw = matchDefs.reduce(0.0) { acc, d in acc + (items.first { $0.id == prefix + d.id }.map { $0.unitShare * $0.ratio } ?? 0) }
        func weekly(_ d: Def) -> Double {
            switch d.id {
            case "merch": return wk["merch"].double
            case "spons": return wk["spons"].double
            default:
                let it = items.first { $0.id == prefix + d.id }
                return mw > 0 ? md * homeShare * (it.map { $0.unitShare * $0.ratio } ?? 0) / mw : 0
            }
        }
        let revs = spec.items.map { weekly($0) }
        let revSum = revs.reduce(0, +)
        let costs = wk["wages"].double + wk["coaches"].double + wk["ops"].double
        let tv = wk["tv"].double
        var direct = 0.0
        for (n, d) in spec.items.enumerated() { direct += revs[n] * d.vc }
        let pool = costs - tv - direct
        let season = season(w, bd)
        return spec.items.enumerated().map { n, d in
            let id = prefix + d.id
            let row = rows.first { $0.id == id }
            let rev = revs[n]
            // Sponsorship is priced by the club's own deals: a unit is one deal, its price the deal's weekly money.
            let deals = Double(co.value("fm")["sp"].object.filter { $0.value["until"].double > Double(s.week) }.count)
            let price = d.id == "spons" ? (deals > 0 ? rev / deals : 0) : (row?.price ?? 0) * (1 - (row?.discountPercent ?? 0) / 100)
            let market = d.id == "spons" ? price : (row?.marketPrice ?? 0)
            let units = d.id == "spons" ? deals : (price > 0 ? rev / price : 0)
            let share = revSum > 0 ? rev / revSum : 0
            let alloc = pool * share
            let varPerSale = price * d.vc
            let fixedPerSale = units > 0 ? alloc / units : 0
            let parts = [Part(label: "Wages, coaches and running costs", weekly: (costs - direct) * share), Part(label: "Less its share of the league's broadcast money", weekly: -tv * share)]
            let sub = d.model == .sub
            let e = Economics(itemID: id, name: row?.name ?? d.name, kindLabel: d.kind, modelLabel: d.model.label, per: spec.per, capacity: 0, capacityPerSession: 0, sessionName: spec.sessionName,
                              sold: units, occupancy: 0, price: price, marketPrice: market, variablePerSale: varPerSale, fixedParts: parts, fixedWeekly: alloc,
                              costPerSale: varPerSale + fixedPerSale, breakEvenPrice: varPerSale + fixedPerSale, weeklyRevenue: rev, weeklyProfit: rev - rev * d.vc - alloc,
                              seasonIndex: season, booked: 0, holders: sub && d.days > 0 ? units / d.days : 0, churnMonthly: 0, edge: 0, playedPerSale: 0,
                              bundleDays: d.days, bundlePrice: d.days > 0 ? price * d.days : 0, recipe: d.recipe, isSub: sub)
            return Computed(def: d, itemID: id, econ: e)
        }
    }

    /// Shift of the club's ticket level from the owner's prices for match tickets, season tickets and boxes (their average against the market, weighted by their
    /// takings): +50% on the price is the top level (+1) of the club's own ticket setting. Exactly 0 for a club that is not on item records or at market prices.
    public static func clubTixShift(_ co: Company) -> Double {
        guard trades.contains("club"), !co.value(SalesItems.key).isNull, !co.value(key).isNull else { return 0 }
        var num = 0.0, den = 0.0
        for it in co.value(SalesItems.key).array.map(SalesItems.decode) where it.id.hasPrefix(prefix) && ["match", "season", "box"].contains(String(it.id.dropFirst(prefix.count))) {
            num += it.unitShare * it.ratio * (it.effectiveMultiplier - 1); den += it.unitShare * it.ratio
        }
        return den > 0 ? 2 * num / den : 0
    }

    // MARK: Reads

    public static func economics(_ s: GameState, companyID: Int, itemID: String, data: GameData) -> Economics? {
        computed(s, companyID: companyID, data: data).first { $0.itemID == itemID }?.econ
    }

    public static func allEconomics(_ s: GameState, companyID: Int, data: GameData) -> [Economics] {
        computed(s, companyID: companyID, data: data).map { $0.econ }
    }

    /// The factor on the week's cost of sales from what the items really cost against the trade's share of the same takings: 1 at default prices
    /// (the direct costs are rescaled to the trade's share), above 1 when the owner prices below the market, below 1 above it. 1 for the club (own model).
    public static func cogsFactor(_ s: GameState, companyID: Int, data: GameData) -> Double {
        guard let co = s.company(companyID), allTrades.contains(co.type), co.type != "club", !co.value(key).isNull, let bd = data.catalog[co.type], let spec = specs[co.type] else { return 1 }
        let items = SalesItems.items(co, bd)
        guard !items.allSatisfy({ $0.effectiveMultiplier == 1 }) else { return 1 }
        let rows = SalesItems.rows(s, companyID: companyID, data: data)
        let k = costScale(items, spec, bd)
        var cost = 0.0, rev = 0.0
        for row in rows {
            let vcShare = spec.items.first { prefix + $0.id == row.id }.map { $0.vc * k } ?? bd.costOfSales
            cost += row.weeklyUnits * vcShare * row.marketPrice
            rev += row.weeklyRevenue
        }
        guard rev > 0, bd.costOfSales > 0, cost > 0 else { return 1 }
        return cost / (rev * bd.costOfSales)
    }

    // MARK: Setting the items up

    /// Put the venue's items in as items and records and refresh their costs. Idempotent. The old titles-only items are dropped on the first run; items the owner
    /// added are kept.
    public static func sync(_ s: inout GameState, companyID: Int, data: GameData) {
        guard let i = s.companyIndex(companyID), s.companies[i].status == .open, let bd = data.catalog[s.companies[i].type], allTrades.contains(bd.id), let spec = specs[bd.id] else { return }
        let co = s.companies[i]
        let first = co.value(key).isNull
        let old = SalesItems.items(co, bd)
        let existing = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        var kept: [SalesItems.Item] = old.filter { !isManaged($0.id) && !(first && $0.id.hasPrefix("d")) }
        var managed: [SalesItems.Item] = []
        let svc = SalesItems.isService(bd)
        for d in spec.items {
            let id = prefix + d.id
            var it = existing[id] ?? SalesItems.Item(id: id, name: d.name, isService: svc, unitShare: 0, ratio: 1, priceMultiplier: 1, discountPercent: 0, discountWeeks: 0, listedForGroup: false)
            it.unitShare = d.share; it.ratio = d.ratio
            managed.append(it)
        }
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
        for d in spec.items {
            let id = prefix + d.id
            var r = ItemModels.record(s.companies[i], itemID: id) ?? ItemModels.Record(id: id, model: d.model)
            r.model = d.model
            ItemModels.put(&s, i, r)
        }
        // A smoothed weekly cost of the company (monthly bills would otherwise make the unit costs jump); for the club the last home matchday takings.
        let wk = Books.expenses(s.companies[i].books.week), prev = s.companies[i].value(key)["exp"].double
        var o: [String: JSONValue] = ["w": .number(Double(s.week)), "exp": .number(wk > 0 ? (prev > 0 ? 0.9 * prev + 0.1 * wk : wk) : prev)]
        let md = s.companies[i].value("fm")["wk"]["match"].double
        o["mdh"] = .number(md > 0 ? md : s.companies[i].value(key)["mdh"].double)
        s.companies[i].set(key, .object(o))
        refresh(&s, i, companyID: companyID, spec: spec, data: data)
    }

    /// This week's true line in every item's history, then the cost of one sale, capacity, stock (holders) and bookings from the books.
    static func refresh(_ s: inout GameState, _ i: Int, companyID: Int, spec: Spec, data: GameData) {
        let week = s.week
        for c in computed(s, companyID: companyID, data: data) {
            guard var r = ItemModels.record(s.companies[i], itemID: c.itemID) else { continue }
            let e = c.econ
            let line = ItemModels.Week(week: week, units: e.sold, revenue: e.weeklyRevenue, profit: e.weeklyProfit)
            if let last = r.history.last, last.week == week { r.history[r.history.count - 1] = line } else { ItemModels.log(&r, week: week, units: line.units, revenue: line.revenue, profit: line.profit) }
            ItemModels.put(&s, i, r)
        }
        for c in computed(s, companyID: companyID, data: data) {
            guard var r = ItemModels.record(s.companies[i], itemID: c.itemID) else { continue }
            let e = c.econ
            r.cost = e.costPerSale; r.fair = e.marketPrice; r.reserved = e.booked; r.capacity = e.capacity
            r.stock = c.def.model == .sub ? Int(e.holders.rounded()) : Int(e.capacityPerSession.rounded())
            ItemModels.put(&s, i, r)
        }
    }

    /// Weekly, after `ItemModels.weeklyTick`: set up the items, refresh costs and the history line.
    public static func weekly(_ s: inout GameState, _ i: Int, data: GameData) {
        guard s.companies.indices.contains(i), trades.contains(s.companies[i].type), s.companies[i].status == .open else { return }
        sync(&s, companyID: s.companies[i].id, data: data)
    }
}
