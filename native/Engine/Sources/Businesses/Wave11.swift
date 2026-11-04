import Foundation
import GameCore
import Countries
import Finance

/// Wave 11, the financial, energy and group trades (insco, bank, fund, power, oilgas, hold). Each real product line of the company is an item:
/// an insurer's covers (premium, expected claims, reserves), a bank's loan types and deposit accounts (rate against funding cost and credit loss),
/// a fund's fee classes (AUM, fee, market exposure), a power producer's tariffs (price per MWh against the cost of generating it), an oil company's
/// fields (price per barrel against lifting cost, depletion and the oil price exposure) and a holding's group services (cost-plus fee per unit).
/// The money stays where it was: `FinanceModel`, `EnergyModel` and `HoldingModel` book premiums, interest, fees, claims, losses and barrels exactly as before,
/// and the items split that money by product. Nothing here moves cash. The overhead (wages, premises, interest, depreciation not booked to a product)
/// is the company's smoothed weekly expense less what the product lines carry directly, shared by value, so the item profits tie to the company's result.
/// Save keys: `items27` (the products become items), `itemsv2` (their records), `w11` (set once set up). See `native/docs/waves/wave11.md`.
public enum Wave11 {
    public static var trades: Set<String> { ItemWaves.w11 }
    static let allTrades: Set<String> = ["insco", "bank", "fund", "power", "oilgas", "hold"]
    static let key = "w11"
    static let prefix = "w11:"

    static let spec: JSONValue = {
        guard let url = Bundle.module.url(forResource: "wave11_items", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return .null }
        return j
    }()

    static func isManaged(_ id: String) -> Bool { id.hasPrefix(prefix) }

    /// One cost or income line of a product, per unit sold (the unit of `Econ.priceUnit`).
    public struct Part: Equatable, Sendable { public var label: String; public var perUnit: Double }

    /// A product line before the owner's price and the overhead are known. Money in accounting units, prices at the market (slider at 1).
    struct Base {
        var id: String, name: String, kind: String, unitWord: String, priceUnit: String
        var units = 0.0, volume = 0.0, price = 0.0
        var parts: [Part] = []
        var credit = 0.0
        var weight = 0.0, share = 0.0
        var size = 0.0, sizeLabel = "", reserve = 0.0, reserveLabel = ""
        var riskLabel = "", risk = 0.0, stress = 0.0, swing = 0.0
        var status = "", note = ""
        var model: ItemModels.Model = .sub
        var directBooked = 0.0
        init(id: String, name: String, kind: String, unitWord: String, priceUnit: String) {
            self.id = prefix + id; self.name = name; self.kind = kind; self.unitWord = unitWord; self.priceUnit = priceUnit
        }
    }

    // MARK: Economics of one product

    public struct Econ: Equatable, Sendable {
        public var itemID: String
        public var name: String
        /// "Insurance cover", "Loan", "Deposit account", "Fee class", "Tariff", "Field", "Group service".
        public var kindLabel: String
        /// "policy", "customer", "client", "MWh", "barrel", "subsidiary".
        public var unitWord: String
        /// What the price is per: "a year", "MWh", "barrel" or "a week".
        public var priceUnit: String
        public var units: Double
        /// Units sold in a week (policy-years, customer-years, MWh, barrels), the base of every per-unit figure.
        public var volume: Double
        /// The owner's price and the market price, per unit.
        public var price: Double
        public var marketPrice: Double
        /// Direct cost per unit by cause (claims, funding, credit loss, lifting, depreciation ...), and income per unit that is not the price (investment income).
        public var parts: [Part]
        public var credit: Double
        public var overheadPerUnit: Double
        /// All-in cost per unit, which is also the price that breaks even.
        public var costPerUnit: Double
        public var margin: Double
        public var weeklyRevenue: Double
        public var weeklyCost: Double
        public var weeklyProfit: Double
        /// Size of the book behind it: annual premium, loan balance, AUM, MWh a week, barrels in the ground, subsidiaries served.
        public var size: Double
        public var sizeLabel: String
        /// Capital or reserves held against it.
        public var reserve: Double
        public var reserveLabel: String
        /// Expected loss or exposure per unit, what it becomes in a bad year, and the relative swing of the result.
        public var riskLabel: String
        public var risk: Double
        public var stress: Double
        public var swing: Double
        public var status: String
        public var note: String
    }

    struct Computed { var base: Base; var econ: Econ; var itemID: String { base.id } }

    static func econ(_ b: Base, overheadTotal: Double, weightTotal: Double, mult: Double) -> Econ {
        let direct = b.parts.reduce(0.0) { $0 + $1.perUnit }
        let oh = weightTotal > 0 ? overheadTotal * b.weight / weightTotal : 0
        let ohUnit = b.volume > 0 ? oh / b.volume : 0
        let cost = direct + ohUnit - b.credit
        let price = b.price * mult
        let rev = b.volume * (price + b.credit)
        let wcost = b.volume * (direct + ohUnit)
        return Econ(itemID: b.id, name: b.name, kindLabel: b.kind, unitWord: b.unitWord, priceUnit: b.priceUnit, units: b.units, volume: b.volume, price: price,
                    marketPrice: b.price, parts: b.parts, credit: b.credit, overheadPerUnit: ohUnit, costPerUnit: cost, margin: price > 0 ? (price - cost) / price : 0,
                    weeklyRevenue: rev, weeklyCost: wcost, weeklyProfit: rev - wcost, size: b.size, sizeLabel: b.sizeLabel, reserve: b.reserve, reserveLabel: b.reserveLabel,
                    riskLabel: b.riskLabel, risk: b.risk, stress: b.stress, swing: b.swing, status: b.status, note: b.note)
    }

    /// The company's smoothed weekly expense and what the product lines book directly (kept as an EMA so monthly bills do not make the costs jump).
    static func overheadTotal(_ co: Company) -> Double {
        let r = co.value(key)
        return max(0, r["exp"].double - r["dir"].double)
    }

    static func bases(_ s: GameState, _ co: Company, _ bd: Trade, _ w: World, mt: Double, overhead: Double) -> [Base] {
        switch bd.id {
        case "insco": return insuranceBases(s, co, bd, w, mt: mt)
        case "bank": return bankBases(s, co, bd, w, mt: mt)
        case "fund": return fundBases(s, co, bd, w, mt: mt)
        case "power": return powerBases(s, co, bd, w, mt: mt)
        case "oilgas": return oilBases(s, co, bd, w, mt: mt)
        case "hold": return holdBases(s, co, bd, w, mt: mt, overhead: overhead)
        default: return []
        }
    }

    static func computed(_ s: GameState, companyID: Int, data: GameData) -> [Computed] {
        guard let co = s.company(companyID), let bd = data.catalog[co.type], allTrades.contains(bd.id), !co.value(key).isNull, !co.value(SalesItems.key).isNull else { return [] }
        let w = World(state: s, data: data)
        let mt = SalesItems.marketTicket(co, bd, w)
        let oh = overheadTotal(co)
        let list = bases(s, co, bd, w, mt: mt, overhead: oh)
        let items = SalesItems.items(co, bd)
        let wt = list.reduce(0.0) { $0 + $1.weight }
        return list.compactMap { b in
            guard let it = items.first(where: { $0.id == b.id }) else { return nil }
            return Computed(base: b, econ: econ(b, overheadTotal: oh, weightTotal: wt, mult: it.effectiveMultiplier))
        }
    }

    /// Everything about the product behind one item, at the owner's current price. Nil for an item that is not a product line of this wave.
    public static func economics(_ s: GameState, companyID: Int, itemID: String, data: GameData) -> Econ? {
        computed(s, companyID: companyID, data: data).first { $0.itemID == itemID }?.econ
    }

    public static func allEconomics(_ s: GameState, companyID: Int, data: GameData) -> [Econ] {
        computed(s, companyID: companyID, data: data).map { $0.econ }
    }

    /// Pure: the same product at a proposed price (accounting units, absolute), for the live slider. Margin, profit a week and the loss on a bad year.
    public static func atPrice(_ e: Econ, price p: Double) -> (profitPerUnit: Double, margin: Double, weeklyProfit: Double, badYearProfitPerUnit: Double) {
        let per = p - e.costPerUnit
        let bad = per - max(0, e.stress - e.risk)
        return (per, p > 0 ? per / p : 0, per * e.volume, bad)
    }

    // MARK: Setting the products up as items

    /// Put the company's product lines in as items and records and refresh their costs. Idempotent. The old titles-only items the products replace are dropped on the
    /// first run (only when the company has products to show); items the owner added are kept.
    public static func sync(_ s: inout GameState, companyID: Int, data: GameData) {
        guard let i = s.companyIndex(companyID), s.companies[i].status == .open, let bd = data.catalog[s.companies[i].type], allTrades.contains(bd.id) else { return }
        // Smoothed books first (the overhead of this week's costs uses them).
        let wk = Books.expenses(s.companies[i].books.week)
        let first = s.companies[i].value(key).isNull
        let prev = s.companies[i].value(key)
        let co0 = s.companies[i]
        let direct = directBooked(co0, bd)
        let exp = wk > 0 ? (prev["exp"].double > 0 ? 0.9 * prev["exp"].double + 0.1 * wk : wk) : prev["exp"].double
        let dir = wk > 0 ? (prev["dir"].double > 0 ? 0.9 * prev["dir"].double + 0.1 * direct : direct) : prev["dir"].double
        let w = World(state: s, data: data)
        let mt = SalesItems.marketTicket(co0, bd, w)
        guard mt > 0 else { return }
        let list = bases(s, co0, bd, w, mt: mt, overhead: max(0, exp - dir))
        guard !list.isEmpty else { return }
        s.companies[i].set(key, .object(["w": .number(Double(s.week)), "exp": .number(exp), "dir": .number(dir)]))
        let co = s.companies[i]
        let old = SalesItems.items(co, bd)
        let existing = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        var kept: [SalesItems.Item] = old.filter { !isManaged($0.id) && !(first && $0.id.hasPrefix("d")) }
        // A company whose earlier items were all the old titles keeps no title items at all.
        let totalUnits = list.reduce(0.0) { $0 + max(0, $1.units) }
        let sumPrice = list.reduce(0.0) { $0 + (totalUnits > 0 ? max(0, $1.units) / totalUnits : 1 / Double(list.count)) * $1.price }
        var managed: [SalesItems.Item] = list.map { b in
            var it = existing[b.id] ?? SalesItems.Item(id: b.id, name: b.name, isService: true, unitShare: 0, ratio: 1, priceMultiplier: 1, discountPercent: 0, discountWeeks: 0, listedForGroup: false)
            it.name = b.name
            it.isService = true
            it.unitShare = totalUnits > 0 ? max(0, b.units) / totalUnits : 1 / Double(list.count)
            it.ratio = bd.id == "hold" ? b.price / mt : (sumPrice > 0 ? b.price / sumPrice : 1)
            return it
        }
        let keptShare = kept.reduce(0.0) { $0 + $1.unitShare }
        let managedShare = managed.reduce(0.0) { $0 + $1.unitShare }
        if managedShare > 0 {
            let f = max(0, 1 - keptShare) / managedShare
            for k in managed.indices { managed[k].unitShare *= f }
        }
        if bd.id != "hold" {
            let keptWeight = kept.reduce(0.0) { $0 + $1.unitShare * $1.ratio }
            let mw = managed.reduce(0.0) { $0 + $1.unitShare * $1.ratio }
            if mw > 0 { let f = max(0.05, 1 - keptWeight) / mw; for k in managed.indices { managed[k].ratio *= f } }
        }
        kept.append(contentsOf: managed)
        SalesItems.store(&s, i, kept)
        var rec = s.companies[i].value("itemsv2").isNull ? [:] : s.companies[i].value("itemsv2").object
        let live = Set(kept.map { $0.id })
        for id in rec.keys where !live.contains(id) { rec.removeValue(forKey: id) }
        s.companies[i].set("itemsv2", .object(rec))
        for b in list {
            var r = ItemModels.record(s.companies[i], itemID: b.id) ?? ItemModels.Record(id: b.id, model: b.model)
            r.model = b.model
            r.stock = Int(b.units.rounded()); r.capacity = b.volume; r.status = ""
            ItemModels.put(&s, i, r)
        }
        refresh(&s, i, companyID: companyID, data: data)
    }

    /// What the company books directly for its products in a week (claims, interest paid and credit losses, running and depreciation of the plant, lifting).
    static func directBooked(_ co: Company, _ bd: Trade) -> Double {
        let b = co.books.week
        switch bd.id {
        case "insco": return b["cogs"] ?? 0
        case "bank": return (b["cogs"] ?? 0) + (b["loss"] ?? 0)
        case "power", "oilgas": return (b["cogs"] ?? 0) + (b["dep"] ?? 0)
        default: return 0
        }
    }

    /// This week's line in every product's history, and the cost of one unit in the units of the item list so the shared price slider shows the true profit or loss.
    static func refresh(_ s: inout GameState, _ i: Int, companyID: Int, data: GameData) {
        let week = s.week
        let items = SalesItems.items(s.companies[i], data.catalog[s.companies[i].type]!)
        let w = World(state: s, data: data)
        let mt = SalesItems.marketTicket(s.companies[i], data.catalog[s.companies[i].type]!, w)
        for c in computed(s, companyID: companyID, data: data) {
            guard var r = ItemModels.record(s.companies[i], itemID: c.itemID), let it = items.first(where: { $0.id == c.itemID }) else { continue }
            let e = c.econ
            let line = ItemModels.Week(week: week, units: e.volume, revenue: e.weeklyRevenue, profit: e.weeklyProfit)
            if let last = r.history.last, last.week == week { r.history[r.history.count - 1] = line } else { ItemModels.log(&r, week: week, units: line.units, revenue: line.revenue, profit: line.profit) }
            // The list price of the item is `mt * ratio` and the product's own price is `marketPrice`: the cost keeps its share of the price in both.
            let listMarket = mt * it.ratio
            r.fair = listMarket
            r.cost = e.marketPrice > 0 ? e.costPerUnit / e.marketPrice * listMarket : 0
            ItemModels.put(&s, i, r)
        }
    }

    /// Weekly, after `ItemModels.weeklyTick`: set up new product lines, drop gone ones, refresh costs and the history line.
    public static func weekly(_ s: inout GameState, _ i: Int, data: GameData) {
        guard s.companies.indices.contains(i), trades.contains(s.companies[i].type), s.companies[i].status == .open else { return }
        sync(&s, companyID: s.companies[i].id, data: data)
    }
}
