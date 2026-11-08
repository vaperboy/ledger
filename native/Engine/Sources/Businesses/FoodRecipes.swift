import Foundation
import GameCore
import Countries
import Finance

/// Made goods with recipes (bakery, cafe, restaurant, foodtruck, brewery, vineyard, farm).
/// An item of these trades is a product with a recipe (`Resources/food_recipes.json`): inputs bought from the company's suppliers, spoilage, labour minutes,
/// batch size, capacity per shift, shelf life, lead time (brewing, ageing, growing) and allergens. The record (`ItemModels`, model MADE, or STK for bought-in
/// drinks and beans) carries `cost` = the rolled-up inputs and `prep` = the spoilage cost of one unit sold.
/// The input shares are scaled per trade so the weighted food cost equals the trade's cost of sales and the weighted spoilage equals its perish and shrink
/// cost: the books (`CompanyWeek`) already charge exactly that, so profit does not move, the item page only shows where it comes from.
public enum FoodRecipes {
    public static let trades: Set<String> = ["bakery", "cafe", "restaurant", "foodtruck", "brewery", "vineyard", "farm"]
    /// Items made from these recipes get ids "w3-<recipe id>".
    static let prefix = "w3-"
    static let planKind = "w3"

    public struct Input: Equatable, Sendable {
        public var name: String
        public var qty: String
        /// Share of the item's market price (before the trade scale).
        public var share: Double
    }

    public struct Recipe: Equatable, Sendable {
        public var id: String
        public var name: String
        public var match: [String]
        public var ratio: Double
        public var customers: Double
        public var inputs: [Input]
        public var spoilage: Double
        public var minutes: Double
        public var batch: Int
        public var perShift: Double
        public var shelfDays: Int
        public var coverDays: Int
        public var leadDays: Int
        public var allergens: String
        public var boughtIn: Bool
        /// Harvest start (week of the year) and length in weeks; nil for year-round production.
        public var harvestStart: Int?
        public var harvestWeeks: Int
        public var inputShare: Double { inputs.reduce(0) { $0 + $1.share } }
    }

    /// A machine the named products cannot be made or sold without; `off` says what the customer misses.
    struct MachineNeed { var off: String; var products: [String] }

    struct Spec { var shifts: Double; var products: [Recipe]; var needs: [String: MachineNeed] = [:] }

    /// The share of the trade's customers who buy what this machine makes, and what they miss while it is in repair; nil when no product is linked to it.
    static func dependentShare(trade: String, equipmentID: String) -> (share: Double, off: String)? {
        guard let spec = specs[trade], let need = spec.needs[equipmentID] else { return nil }
        let total = spec.products.reduce(0) { $0 + $1.customers }
        guard total > 0 else { return nil }
        let linked = spec.products.filter { need.products.contains($0.id) }.reduce(0) { $0 + $1.customers }
        return (linked / total, need.off)
    }

    static let specs: [String: Spec] = {
        guard let url = Bundle.module.url(forResource: "food_recipes", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return [:] }
        var out: [String: Spec] = [:]
        for (k, t) in j["trades"].object {
            let ps: [Recipe] = t["products"].array.map { p in
                Recipe(id: p["id"].string, name: p["n"].string, match: p["m"].array.map { $0.string }, ratio: p["r"].double, customers: p["q"].double,
                       inputs: p["in"].array.map { Input(name: $0.array[0].string, qty: $0.array[1].string, share: $0.array[2].double) },
                       spoilage: p["w"].double, minutes: p["min"].double, batch: p["batch"].int, perShift: p["shift"].double, shelfDays: p["shelf"].int,
                       coverDays: p["cover"].int, leadDays: p["lead"].int, allergens: p["al"].string, boughtIn: p["model"].string == "stk",
                       harvestStart: p["season"].isNull ? nil : p["season"]["s"].int, harvestWeeks: p["season"]["h"].int)
            }
            var needs: [String: MachineNeed] = [:]
            for (eid, n) in t["eq"].object { needs[eid] = MachineNeed(off: n["off"].string, products: n["p"].array.map { $0.string }) }
            out[k] = Spec(shifts: t["shifts"].double, products: ps, needs: needs)
        }
        return out
    }()

    // MARK: Matching and scale

    /// The recipe of an item: its own id, else the first recipe whose words are in the name, else the trade's average product.
    public static func recipe(trade: String, itemID: String, name: String) -> Recipe? {
        guard let spec = specs[trade] else { return nil }
        if itemID.hasPrefix(prefix), let r = spec.products.first(where: { prefix + $0.id == itemID }) { return r }
        let n = name.lowercased()
        if let r = spec.products.first(where: { p in p.match.contains { n.contains($0) } }) { return r }
        return average(spec, name: name)
    }

    /// A product the trade has no named recipe for (a player-added line): the trade's average inputs, labour and capacity.
    static func average(_ spec: Spec, name: String) -> Recipe {
        let ps = spec.products.filter { !$0.boughtIn }
        let w = ps.reduce(0.0) { $0 + $1.customers * $1.ratio }
        func avg(_ f: (Recipe) -> Double) -> Double { w > 0 ? ps.reduce(0.0) { $0 + $1.customers * $1.ratio * f($1) } / w : 0 }
        return Recipe(id: "avg", name: name, match: [], ratio: 1, customers: 1, inputs: [Input(name: "Ingredients and materials", qty: "per unit", share: avg { $0.inputShare })],
                      spoilage: avg { $0.spoilage }, minutes: avg { $0.minutes }, batch: Int(saturating: avg { Double($0.batch) }.rounded()), perShift: avg { $0.perShift },
                      shelfDays: Int(saturating: avg { Double($0.shelfDays) }.rounded()), coverDays: Int(saturating: avg { Double($0.coverDays) }.rounded()), leadDays: Int(saturating: avg { Double($0.leadDays) }.rounded()),
                      allergens: "See the allergen sheet", boughtIn: false, harvestStart: nil, harvestWeeks: 0)
    }

    /// Multipliers on the authored input shares and spoilage so that the trade's default mix equals its books (cost of sales; perish and shrink).
    public static func scales(trade: String, _ bd: Trade) -> (inputs: Double, spoilage: Double) {
        guard let spec = specs[trade], !spec.products.isEmpty else { return (1, 1) }
        let ps = spec.products
        let sq = ps.reduce(0.0) { $0 + $1.customers }
        let norm = ps.reduce(0.0) { $0 + $1.customers / sq * $1.ratio }
        var cost = 0.0, waste = 0.0
        for p in ps { let w = p.customers / sq * p.ratio / norm; cost += w * p.inputShare; waste += w * p.spoilage }
        let tw = bd.traits
        let wasteTarget = (tw["perish"] ?? 0) * 0.6 + (tw["shrink"] ?? 0) * 0.3
        return (cost > 0 ? bd.costOfSales / cost : 1, waste > 0 ? wasteTarget / waste : 0)
    }

    // MARK: Card (what the item page shows)

    public struct Line: Equatable, Sendable {
        public var name: String
        public var qty: String
        /// Cost of this input in one unit, accounting units, before the supplier's relationship discount.
        public var cost: Double
    }

    public struct Card: Equatable, Sendable {
        public var recipeName: String
        public var boughtIn: Bool
        public var lines: [Line]
        /// All inputs of one unit after the relationship discount of the linked supplier.
        public var inputCost: Double
        public var supplierDiscount: Double
        public var supplierName: String?
        /// Cost of unsold and spoilt product carried by each unit sold.
        public var spoilageCost: Double
        public var unitCost: Double
        public var price: Double
        /// Inputs as a share of the price shown (the food cost percent).
        public var foodCostPercent: Double
        public var labourMinutes: Double
        public var batch: Int
        public var perShift: Double
        public var capacityPerWeek: Double
        public var weeklyUnits: Double
        /// Weekly units over weekly capacity; above 1 the kitchen, tank or field cannot make what customers ask for.
        public var capacityUse: Double
        public var shelfDays: Int
        public var leadDays: Int
        public var allergens: String
        public var seasonNote: String
    }

    static func monthWord(weekOfYear w: Int) -> String { GameCalendar.monthNames[max(0, min(11, w * 12 / 52))] }

    /// The recipe card of an item at a price (nil price = its own price). nil for a trade or item without a made record.
    public static func card(_ s: GameState, companyID: Int, itemID: String, price: Double? = nil, data: GameData) -> Card? {
        guard let co = s.company(companyID), trades.contains(co.type), let bd = data.catalog[co.type],
              let rec = ItemModels.record(co, itemID: itemID), rec.model == .made || rec.model == .stk,
              let row = SalesItems.rows(s, companyID: companyID, data: data).first(where: { $0.id == itemID }),
              let r = recipe(trade: co.type, itemID: itemID, name: row.name) else { return nil }
        let k = scales(trade: co.type, bd)
        let disc = ItemModels.supplierDiscount(s, rec)
        let lines = r.inputs.map { Line(name: $0.name, qty: $0.qty, cost: row.marketPrice * $0.share * k.inputs) }
        let listInputs = lines.reduce(0.0) { $0 + $1.cost }
        let input = listInputs * (1 - disc)
        let spoil = row.marketPrice * r.spoilage * k.spoilage
        let shown = price ?? row.price
        let cap = capacity(r, spec: specs[co.type], co)
        let vendor = rec.supplierID.flatMap { Suppliers.vendor(s, id: $0, data: data)?.name }
        return Card(recipeName: r.name, boughtIn: r.boughtIn, lines: lines, inputCost: input, supplierDiscount: disc, supplierName: vendor, spoilageCost: spoil,
                    unitCost: input + spoil, price: shown, foodCostPercent: shown > 0 ? input / shown : 0, labourMinutes: r.minutes, batch: r.batch, perShift: r.perShift,
                    capacityPerWeek: cap, weeklyUnits: row.weeklyUnits, capacityUse: cap > 0 ? row.weeklyUnits / cap : 0, shelfDays: r.shelfDays, leadDays: r.leadDays,
                    allergens: r.allergens, seasonNote: seasonNote(r, week: s.week))
    }

    static func capacity(_ r: Recipe, spec: Spec?, _ co: Company) -> Double {
        guard !r.boughtIn, let spec else { return 0 }
        return r.perShift * spec.shifts * co.size
    }

    static func seasonNote(_ r: Recipe, week: Int) -> String {
        guard let h = r.harvestStart else { return "" }
        let d = GameCalendar.date(week: week)
        let year = d.month >= 9 ? d.year : d.year - 1
        var t = "Harvest from \(monthWord(weekOfYear: h)), about \(r.harvestWeeks) weeks"
        if r.leadDays >= 365 { t += ". Vintage \(year), ready \(year + Int(saturating: (Double(r.leadDays) / 365).rounded(.up)))" }
        return t
    }

    // MARK: Writes

    /// Weeks of sales on hand: the made stock, or in a harvest trade what the store holds.
    static func coverWeeks(_ r: Recipe) -> Double { Double(max(1, r.coverDays)) / 7 }

    static func bestSupplier(_ s: GameState, _ co: Company, data: GameData) -> String? {
        Suppliers.candidates(s, company: co, scope: "goods", data: data)
            .max { ($0.relationship, $0.rating) < ($1.relationship, $1.rating) }?.id
    }

    static func plans(_ r: Recipe, rec: ItemModels.Record, units: Double, cap: Double, week: Int) -> [ItemModels.Plan] {
        var out: [ItemModels.Plan] = []
        func add(_ t: String) { out.append(ItemModels.Plan(kind: planKind, text: t, week: week)) }
        if r.boughtIn {
            add("Bought in: reorder every \(max(1, r.leadDays)) days from the linked supplier")
        } else {
            add("Batch of \(r.batch), about \(Int(saturating: r.minutes.rounded())) minutes of work a unit")
            if r.leadDays >= 7 { add("Takes \(r.leadDays / 7) weeks to make or age, \(rec.onOrder) units in the tanks, barrels or fields now") }
            if cap > 0, units > cap { add("Over capacity: \(Int(saturating: units.rounded())) a week asked, \(Int(saturating: cap.rounded())) can be made. Add a shift or equipment.") }
        }
        if r.shelfDays > 0, r.shelfDays < 30 { add("Keeps \(r.shelfDays) days, unsold product is written off") }
        let note = seasonNote(r, week: week)
        if !note.isEmpty { add(note) }
        return out
    }

    /// Put the recipe on an item's record: cost, spoilage, lead time, capacity, stock. Keeps the supplier, history and other plans.
    static func fill(_ rec: inout ItemModels.Record, _ r: Recipe, spec: Spec, co: Company, market: Double, k: (inputs: Double, spoilage: Double), units: Double, week: Int) {
        rec.model = r.boughtIn ? .stk : .made
        rec.cost = market * r.inputShare * k.inputs
        rec.prep = market * r.spoilage * k.spoilage
        rec.holdingPerWeek = 0
        rec.leadDays = r.leadDays
        rec.capacity = capacity(r, spec: spec, co)
        let cover = coverWeeks(r)
        rec.stock = max(1, Int(saturating: (units * cover).rounded(.up)))
        rec.onOrder = r.leadDays >= 7 || r.boughtIn ? Int(saturating: (units * Double(r.leadDays) / 7).rounded(.up)) : 0
        rec.since = nil
        rec.plans.removeAll { $0.kind == planKind }
        let fresh = plans(r, rec: rec, units: units, cap: rec.capacity, week: week)
        rec.plans.append(contentsOf: fresh)
    }

    /// Bring one company's items up to the recipe model: the untouched default titles become the trade's real product list (same demand), every item gets
    /// a record with its recipe cost and stock. Idempotent and also the weekly refresh (costs follow the market price, stock follows sales).
    /// Returns how many records were written.
    @discardableResult
    public static func apply(_ s: inout GameState, companyID: Int, data: GameData, trades set: Set<String> = ItemTradeGroups.food) -> Int {
        guard let i = s.companyIndex(companyID), set.contains(s.companies[i].type), let bd = data.catalog[s.companies[i].type],
              let spec = specs[s.companies[i].type] else { return 0 }
        let type = s.companies[i].type
        // 1. The product list.
        let before = SalesItems.items(s.companies[i], bd)
        if before == SalesItems.defaults(s.companies[i], bd) {
            let sq = spec.products.reduce(0.0) { $0 + $1.customers }
            let norm = spec.products.reduce(0.0) { $0 + $1.customers / sq * $1.ratio }
            let list = spec.products.map { p in
                SalesItems.Item(id: prefix + p.id, name: p.name, isService: false, unitShare: p.customers / sq, ratio: p.ratio / norm,
                                priceMultiplier: 1, discountPercent: 0, discountWeeks: 0, listedForGroup: false)
            }
            SalesItems.store(&s, i, list)
            dropRecords(&s, i, except: Set(list.map { $0.id }))
        }
        // 2. A record per item.
        let rows = SalesItems.rows(s, companyID: companyID, data: data)
        let k = scales(trade: type, bd)
        var n = 0
        let supplier = bestSupplier(s, s.companies[i], data: data)
        for row in rows where !row.isService {
            guard let r = recipe(trade: type, itemID: row.id, name: row.name) else { continue }
            let co = s.companies[i]
            var rec = ItemModels.record(co, itemID: row.id) ?? ItemModels.Record(id: row.id, model: .made)
            // A hand-managed stocked record (units on hand, not ours) is left as it is.
            if rec.model == .stk, rec.stock > 0, !rec.plans.contains(where: { $0.kind == planKind }) { continue }
            fill(&rec, r, spec: spec, co: co, market: row.marketPrice, k: k, units: row.weeklyUnits, week: s.week)
            if rec.supplierID == nil { rec.supplierID = supplier }
            ItemModels.put(&s, i, rec)
            n += 1
        }
        return n
    }

    static func dropRecords(_ s: inout GameState, _ i: Int, except keep: Set<String>) {
        let raw = s.companies[i].value("itemsv2")
        guard !raw.isNull else { return }
        var o: [String: JSONValue] = [:]
        for (k, v) in raw.object where keep.contains(k) { o[k] = v }
        s.companies[i].set("itemsv2", .object(o))
    }

    /// Weekly: every open company of an opted-in trade is brought up to date. Costs follow the market price, stock follows sales.
    public static func weeklyTick(_ s: inout GameState, data: GameData, trades set: Set<String> = ItemTradeGroups.food) {
        guard !set.isEmpty else { return }
        let ids: [Int] = s.companies.filter { $0.status == .open && set.contains($0.type) }.map { $0.id }
        for id in ids { apply(&s, companyID: id, data: data, trades: set) }
    }
}
