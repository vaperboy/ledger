import Foundation
import GameCore
import Countries
import Finance

/// Item record v2 (W0 foundation, products audit `native/docs/audit/products_by_trade.md`). A company item (`SalesItems.Item`, key `items27`) is a title
/// with a price. This adds the real thing behind it, per item, in a second record `itemsv2` = { itemID: record } on the company:
/// model (STK stocked resale, MADE recipe, SVC service, BRK unique unit, RENT, PROJ, SUB), unit cost, extra cost per unit (repairs, prep), holding cost per
/// week, stock, on order, lead time, capacity, supplier link, status, reservations, plans and a weekly sales and profit history.
/// Nothing is written until something sets it, and no trade is switched on: `optedInTrades` is empty until a wave adds its trades.
/// `SalesItems` itself, demand and every old save are untouched; an item without a record is read through `fallbackCost` (the trade's cost-of-sales share).
public enum ItemModels {
    /// Trades whose old titles-only items are migrated to records. Empty in W0: a wave adds its trades here (tests pass their own set).
    public static var optedInTrades: Set<String> { ItemWaves.all }
    static let key = "itemsv2"
    public static let historyWeeks = 52
    /// Weekly rate at which interested customers buy one unit at the fair price (a unique unit sits a few weeks on average).
    public static let baseSaleRate = 0.25

    public enum Model: String, CaseIterable, Sendable {
        case stk, made, svc, brk, rent, proj, sub
        public var label: String {
            switch self {
            case .stk: return "Stocked goods"
            case .made: return "Made goods"
            case .svc: return "Service"
            case .brk: return "Unique unit"
            case .rent: return "Rental"
            case .proj: return "Project"
            case .sub: return "Subscription"
            }
        }
        /// True when the item has units on hand that can run out.
        public var holdsStock: Bool { self == .stk || self == .made || self == .brk }
    }

    public struct Week: Equatable, Sendable {
        public var week: Int
        public var units: Double
        public var revenue: Double
        public var profit: Double
    }

    public struct Plan: Equatable, Sendable {
        public var kind: String
        public var text: String
        public var week: Int
    }

    public struct Record: Equatable, Sendable {
        public var id: String
        public var model: Model
        /// Buy or make price of one unit at list, accounting units.
        public var cost: Double = 0
        /// Extra cost of one unit on top (repairs, prep, inspection).
        public var prep: Double = 0
        /// Holding cost of one unit for one week (lot space, storage, finance).
        public var holdingPerWeek: Double = 0
        public var stock: Int = 0
        public var onOrder: Int = 0
        public var leadDays: Int = 0
        /// Units (or hours, slots) the item can supply a week; 0 = not limited.
        public var capacity: Double = 0
        public var supplierID: String?
        /// Fair value to customers; 0 = the market price of the item.
        public var fair: Double = 0
        /// "" ready, "repair", "reserved", "listed", "retired".
        public var status: String = ""
        public var reserved: Int = 0
        /// Week the stock arrived (for holding cost).
        public var since: Int?
        public var plans: [Plan] = []
        public var history: [Week] = []
        public init(id: String, model: Model) { self.id = id; self.model = model }
    }

    // MARK: Storage

    static func decode(_ id: String, _ j: JSONValue) -> Record {
        var r = Record(id: id, model: Model(rawValue: j["m"].string) ?? .stk)
        r.cost = j["c"].double; r.prep = j["p"].double; r.holdingPerWeek = j["h"].double
        r.stock = j["s"].int; r.onOrder = j["o"].int; r.leadDays = j["l"].int; r.capacity = j["cp"].double
        r.supplierID = j["v"].isNull ? nil : j["v"].string
        r.fair = j["f"].double; r.status = j["st"].string; r.reserved = j["rs"].int
        r.since = j["sw"].isNull ? nil : j["sw"].int
        r.plans = j["pl"].array.map { Plan(kind: $0["k"].string, text: $0["t"].string, week: $0["w"].int) }
        r.history = j["hi"].array.map { Week(week: $0["w"].int, units: $0["u"].double, revenue: $0["r"].double, profit: $0["p"].double) }
        return r
    }

    /// Only fields that differ from the default are written.
    static func encode(_ r: Record) -> JSONValue {
        var o: [String: JSONValue] = ["m": .string(r.model.rawValue)]
        if r.cost != 0 { o["c"] = .number(r.cost) }
        if r.prep != 0 { o["p"] = .number(r.prep) }
        if r.holdingPerWeek != 0 { o["h"] = .number(r.holdingPerWeek) }
        if r.stock != 0 { o["s"] = .number(Double(r.stock)) }
        if r.onOrder != 0 { o["o"] = .number(Double(r.onOrder)) }
        if r.leadDays != 0 { o["l"] = .number(Double(r.leadDays)) }
        if r.capacity != 0 { o["cp"] = .number(r.capacity) }
        if let v = r.supplierID { o["v"] = .string(v) }
        if r.fair != 0 { o["f"] = .number(r.fair) }
        if !r.status.isEmpty { o["st"] = .string(r.status) }
        if r.reserved != 0 { o["rs"] = .number(Double(r.reserved)) }
        if let w = r.since { o["sw"] = .number(Double(w)) }
        if !r.plans.isEmpty { o["pl"] = .array(r.plans.map { .object(["k": .string($0.kind), "t": .string($0.text), "w": .number(Double($0.week))]) }) }
        if !r.history.isEmpty {
            o["hi"] = .array(r.history.map { .object(["w": .number(Double($0.week)), "u": .number($0.units), "r": .number($0.revenue), "p": .number($0.profit)]) })
        }
        return .object(o)
    }

    public static func record(_ co: Company, itemID: String) -> Record? {
        let j = co.value(key)[itemID]
        return j.isNull ? nil : decode(itemID, j)
    }

    public static func records(_ co: Company) -> [Record] {
        co.value(key).object.map { decode($0.key, $0.value) }.sorted { $0.id < $1.id }
    }

    static func put(_ s: inout GameState, _ i: Int, _ r: Record) {
        var o: [String: JSONValue] = s.companies[i].value(key).isNull ? [:] : s.companies[i].value(key).object
        o[r.id] = encode(r)
        s.companies[i].set(key, .object(o))
    }

    // MARK: Cost, live profit and loss

    public enum Outcome: String, Sendable { case profit, loss, breakEven }

    public struct LiveProfit: Equatable, Sendable {
        public var price: Double
        public var cost: Double
        public var amount: Double
        public var outcome: Outcome
        /// The word to show: "profit", "loss" or "break-even". Never "profit" for a loss and never a plain 0 for a real figure.
        public var word: String { outcome == .breakEven ? "break-even" : outcome.rawValue }
        /// Margin on the price (0 when the price is 0).
        public var margin: Double { price > 0 ? amount / price : 0 }
    }

    /// Cost of one unit held `weeksHeld` weeks: buy or make price after the supplier's relationship discount, plus prep, plus holding.
    public static func unitCost(_ r: Record, weeksHeld: Int = 0, supplierDiscount: Double = 0) -> Double {
        r.cost * (1 - max(0, min(1, supplierDiscount))) + r.prep + r.holdingPerWeek * Double(max(0, weeksHeld))
    }

    /// Pure: what selling at `price` leaves after `cost` (and a selling cost share, e.g. a commission). Break-even only when the figure is truly zero.
    public static func liveProfit(price: Double, cost: Double, sellingShare: Double = 0) -> LiveProfit {
        let amount = price * (1 - sellingShare) - cost
        let eps = 1e-9 * max(1, abs(price), abs(cost))
        return LiveProfit(price: price, cost: cost, amount: amount, outcome: abs(amount) <= eps ? .breakEven : (amount > 0 ? .profit : .loss))
    }

    /// Cost of an item that has no record yet: the trade's cost-of-sales share of the market price (what the books already assume).
    public static func fallbackCost(market: Double, _ bd: Trade) -> Double { market * bd.costOfSales }

    /// Live profit or loss of any item of a company at a proposed price (accounting units).
    public static func liveProfit(_ s: GameState, companyID: Int, itemID: String, price: Double, data: GameData) -> LiveProfit? {
        guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return nil }
        guard let it = SalesItems.items(co, bd).first(where: { $0.id == itemID }) else { return nil }
        if let r = record(co, itemID: itemID) {
            let held = r.since.map { s.week - $0 } ?? 0
            return liveProfit(price: price, cost: unitCost(r, weeksHeld: held, supplierDiscount: supplierDiscount(s, r)))
        }
        let market = SalesItems.marketTicket(co, bd, World(state: s, data: data)) * it.ratio
        return liveProfit(price: price, cost: fallbackCost(market: market, bd))
    }

    // MARK: Sale probability

    /// Weekly chance that one interested customer buys at `price` when fair value is `fair`: 1 - exp(-rate), rate falling with price against fair
    /// value at the game's elasticity. No floor and no cap: a free item is bought at once, a far too dear one almost never.
    public static func saleProbability(price: Double, fair: Double, baseRate: Double = baseSaleRate) -> Double {
        guard fair > 0 else { return 0 }
        guard price > 0 else { return 1 }
        return 1 - exp(-baseRate * pow(price / fair, SalesItems.elasticity))
    }

    /// Expected weeks until the item sells at that price.
    public static func expectedWeeks(price: Double, fair: Double) -> Double? {
        let p = saleProbability(price: price, fair: fair)
        return p > 0 ? 1 / p : nil
    }

    // MARK: Supply

    public struct SupplyLine: Equatable, Sendable {
        public var vendorID: String
        public var vendorName: String
        public var relationshipWord: String
        public var discount: Double
        public var listCost: Double
        /// What one unit costs from this supplier.
        public var buyPrice: Double
        public var leadDays: Int
    }

    static func supplierDiscount(_ s: GameState, _ r: Record) -> Double {
        guard let v = r.supplierID else { return 0 }
        return Suppliers.relationshipDiscount(Suppliers.relationship(s, v))
    }

    /// Where the item comes from now (the linked supplier), or nil.
    public static func supply(_ s: GameState, companyID: Int, itemID: String, data: GameData) -> SupplyLine? {
        guard let co = s.company(companyID), let r = record(co, itemID: itemID), let v = r.supplierID,
              let vendor = Suppliers.vendor(s, id: v, data: data) else { return nil }
        return line(vendor, r)
    }

    static func line(_ v: Suppliers.Vendor, _ r: Record) -> SupplyLine {
        let d = Suppliers.relationshipDiscount(v.relationship)
        return SupplyLine(vendorID: v.id, vendorName: v.name, relationshipWord: v.relationshipWord, discount: d, listCost: r.cost, buyPrice: r.cost * (1 - d), leadDays: r.leadDays)
    }

    /// The suppliers that could supply this item (the company's goods suppliers), each with the price this item would cost from them.
    public static func offers(_ s: GameState, companyID: Int, itemID: String, data: GameData) -> [SupplyLine] {
        guard let co = s.company(companyID), let r = record(co, itemID: itemID) else { return [] }
        return Suppliers.candidates(s, company: co, scope: "goods", data: data).map { line($0, r) }
    }

    /// One word for the list row.
    public static func statusWord(_ r: Record?, _ row: SalesItem) -> String {
        guard let r else { return row.isService ? "Service" : "On sale" }
        switch r.status {
        case "repair": return "Being fixed"
        case "retired": return "Retired"
        case "reserved": return "Reserved"
        default: break
        }
        if r.model.holdsStock { return r.stock > 0 ? "In stock \(r.stock)" : "Sold out" }
        return r.model.label
    }

    // MARK: Writes

    /// Turn a titles-only item into a record: STK for goods, SVC for services, cost from the trade's cost-of-sales share. No stock. Idempotent.
    @discardableResult
    public static func migrateItem(_ s: inout GameState, companyID: Int, itemID: String, data: GameData) -> Bool {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type] else { return false }
        let co = s.companies[i]
        guard record(co, itemID: itemID) == nil, let it = SalesItems.items(co, bd).first(where: { $0.id == itemID }) else { return false }
        let market = SalesItems.marketTicket(co, bd, World(state: s, data: data)) * it.ratio
        var r = Record(id: itemID, model: it.isService ? .svc : .stk)
        r.cost = fallbackCost(market: market, bd)
        put(&s, i, r)
        return true
    }

    /// Migrate every item of one company. Returns how many records were created.
    @discardableResult
    public static func migrate(_ s: inout GameState, companyID: Int, data: GameData) -> Int {
        guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return 0 }
        var n = 0
        for it in SalesItems.items(co, bd) where migrateItem(&s, companyID: companyID, itemID: it.id, data: data) { n += 1 }
        return n
    }

    /// Migrate the open companies of the opted-in trades. With the empty registry this does nothing.
    @discardableResult
    public static func migrateOptedIn(_ s: inout GameState, data: GameData, trades: Set<String> = optedInTrades) -> Int {
        guard !trades.isEmpty else { return 0 }
        var n = 0
        let ids: [Int] = s.companies.filter { $0.status == .open && trades.contains($0.type) }.map { $0.id }
        for id in ids { n += migrate(&s, companyID: id, data: data) }
        return n
    }

    static func mutate(_ s: inout GameState, companyID: Int, itemID: String, _ body: (inout Record) -> Void) {
        guard let i = s.companyIndex(companyID), var r = record(s.companies[i], itemID: itemID) else { return }
        body(&r)
        put(&s, i, r)
    }

    public static func setSupplier(_ s: inout GameState, companyID: Int, itemID: String, vendorID: String?) {
        mutate(&s, companyID: companyID, itemID: itemID) { $0.supplierID = vendorID }
    }

    /// Units arrive: stock goes up, the arrival week is kept for holding cost.
    public static func receive(_ s: inout GameState, companyID: Int, itemID: String, units: Int) {
        let week = s.week
        mutate(&s, companyID: companyID, itemID: itemID) { r in
            let n = max(0, units)
            r.onOrder = max(0, r.onOrder - n)
            if r.stock == 0 { r.since = week }
            r.stock += n
        }
    }

    /// Units sold out of stock; returns how many could be sold.
    @discardableResult
    public static func take(_ s: inout GameState, companyID: Int, itemID: String, units: Int) -> Int {
        var sold = 0
        mutate(&s, companyID: companyID, itemID: itemID) { r in
            sold = min(max(0, units), r.stock)
            r.stock -= sold
            if r.stock == 0 { r.since = nil }
        }
        return sold
    }

    public static func addPlan(_ s: inout GameState, companyID: Int, itemID: String, kind: String, text: String) {
        let week = s.week
        mutate(&s, companyID: companyID, itemID: itemID) { $0.plans.append(Plan(kind: kind, text: text, week: week)) }
    }

    static func log(_ r: inout Record, week: Int, units: Double, revenue: Double, profit: Double) {
        r.history.append(Week(week: week, units: units, revenue: revenue, profit: profit))
        if r.history.count > historyWeeks { r.history.removeFirst(r.history.count - historyWeeks) }
    }

    public static func logWeek(_ s: inout GameState, companyID: Int, itemID: String, units: Double, revenue: Double, profit: Double) {
        let week = s.week
        mutate(&s, companyID: companyID, itemID: itemID) { log(&$0, week: week, units: units, revenue: revenue, profit: profit) }
    }

    /// Weekly: every item that has a record gets this week's units, revenue and profit into its history. No record, no write.
    static func weeklyTick(_ s: inout GameState, _ i: Int, data: GameData) {
        guard !s.companies[i].value(key).isNull else { return }
        let id = s.companies[i].id
        let rows = SalesItems.rows(s, companyID: id, data: data)
        for r in records(s.companies[i]) {
            guard let row = rows.first(where: { $0.id == r.id }) else { continue }
            let cost = unitCost(r, weeksHeld: r.since.map { s.week - $0 } ?? 0, supplierDiscount: supplierDiscount(s, r))
            logWeek(&s, companyID: id, itemID: r.id, units: row.weeklyUnits, revenue: row.weeklyRevenue, profit: row.weeklyRevenue - row.weeklyUnits * cost)
        }
    }
}
