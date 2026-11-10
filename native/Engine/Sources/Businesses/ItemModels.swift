import Foundation
import GameCore
import Countries
import Finance

public enum ItemModels {
    public static var optedInTrades: Set<String> { ItemTradeGroups.all }
    static let key = "itemsv2"
    public static let historyWeeks = 52
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
        public var cost: Double = 0
        public var prep: Double = 0
        public var holdingPerWeek: Double = 0
        public var stock: Int = 0
        public var onOrder: Int = 0
        public var leadDays: Int = 0
        public var capacity: Double = 0
        public var supplierID: String?
        public var fair: Double = 0
        public var status: String = ""
        public var reserved: Int = 0
        public var since: Int?
        public var monthlyUnits: Int = 0
        public var pickedWeek: Int?
        public var plans: [Plan] = []
        public var history: [Week] = []
        public init(id: String, model: Model) { self.id = id; self.model = model }
    }

    static func decode(_ id: String, _ j: JSONValue) -> Record {
        var r = Record(id: id, model: Model(rawValue: j["m"].string) ?? .stk)
        r.cost = j["c"].double; r.prep = j["p"].double; r.holdingPerWeek = j["h"].double
        r.stock = j["s"].int; r.onOrder = j["o"].int; r.leadDays = j["l"].int; r.capacity = j["cp"].double
        r.supplierID = j["v"].isNull ? nil : j["v"].string
        r.fair = j["f"].double; r.status = j["st"].string; r.reserved = j["rs"].int
        r.since = j["sw"].isNull ? nil : j["sw"].int
        r.monthlyUnits = j["mu"].int
        r.pickedWeek = j["pw"].isNull ? nil : j["pw"].int
        r.plans = j["pl"].array.map { Plan(kind: $0["k"].string, text: $0["t"].string, week: $0["w"].int) }
        r.history = j["hi"].array.map { Week(week: $0["w"].int, units: $0["u"].double, revenue: $0["r"].double, profit: $0["p"].double) }
        return r
    }

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
        if r.monthlyUnits != 0 { o["mu"] = .number(Double(r.monthlyUnits)) }
        if let w = r.pickedWeek { o["pw"] = .number(Double(w)) }
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

    public enum Outcome: String, Sendable { case profit, loss, breakEven }

    public struct LiveProfit: Equatable, Sendable {
        public var price: Double
        public var cost: Double
        public var amount: Double
        public var outcome: Outcome
        public var word: String { outcome == .breakEven ? "break-even" : outcome.rawValue }
        public var margin: Double { price > 0 ? amount / price : 0 }
    }

    public static func unitCost(_ r: Record, weeksHeld: Int = 0, supplierDiscount: Double = 0) -> Double {
        r.cost * (1 - max(0, min(1, supplierDiscount))) + r.prep + r.holdingPerWeek * Double(max(0, weeksHeld))
    }

    public static func liveProfit(price: Double, cost: Double, sellingShare: Double = 0) -> LiveProfit {
        let amount = price * (1 - sellingShare) - cost
        let eps = 1e-9 * max(1, abs(price), abs(cost))
        return LiveProfit(price: price, cost: cost, amount: amount, outcome: abs(amount) <= eps ? .breakEven : (amount > 0 ? .profit : .loss))
    }

    public static func fallbackCost(market: Double, _ bd: Trade) -> Double { market * bd.costOfSales }

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

    public static func saleProbability(price: Double, fair: Double, baseRate: Double = baseSaleRate) -> Double {
        guard fair > 0 else { return 0 }
        guard price > 0 else { return 1 }
        return 1 - exp(-baseRate * pow(price / fair, SalesItems.elasticity))
    }

    public static func expectedWeeks(price: Double, fair: Double) -> Double? {
        let p = saleProbability(price: price, fair: fair)
        return p > 0 ? 1 / p : nil
    }

    public struct SupplyLine: Equatable, Sendable {
        public var vendorID: String
        public var vendorName: String
        public var relationshipWord: String
        public var discount: Double
        public var listCost: Double
        public var buyPrice: Double
        public var leadDays: Int
        public var reliability: Double
        public var owner: String = ""
        public var capacityTotal: Int = 0
        public var capacityFree: Int = 0
    }

    public static let repickWeeks = 4
    public static let cancelFeeWeeks = 2.0
    static let weeksPerMonth = 52.0 / 12.0

    static func discount(_ s: GameState, vendorID: String?) -> Double {
        guard let v = vendorID else { return 0 }
        return clamp(Suppliers.discount(s, scope: "goods", vendorID: v), 0, 1)
    }

    static func supplierDiscount(_ s: GameState, _ r: Record) -> Double { discount(s, vendorID: r.supplierID) }

    public static func buyPrice(_ s: GameState, _ r: Record, vendorID: String?) -> Double { r.cost * (1 - discount(s, vendorID: vendorID)) }

    public static func blendedDiscount(_ s: GameState, _ co: Company, base: Double) -> Double? {
        let list = records(co).filter { $0.model == .stk || $0.model == .made }
        guard list.contains(where: { $0.pickedWeek != nil && $0.supplierID != nil }) else { return nil }
        var weight = 0.0, total = 0.0
        for r in list {
            let w = max(1e-9, r.cost)
            weight += w
            total += w * (r.pickedWeek != nil && r.supplierID != nil ? discount(s, vendorID: r.supplierID) : base)
        }
        return weight > 0 ? total / weight : nil
    }

    public static func supply(_ s: GameState, companyID: Int, itemID: String, data: GameData) -> SupplyLine? {
        guard let co = s.company(companyID), let r = record(co, itemID: itemID), let v = r.supplierID,
              let vendor = Suppliers.vendor(s, id: v, data: data) else { return nil }
        return line(s, companyID: companyID, vendor, r, data: data)
    }

    static func line(_ s: GameState, companyID: Int, _ v: Suppliers.Vendor, _ r: Record, data: GameData) -> SupplyLine {
        let space = room(s, companyID: companyID, vendorID: v.id, excluding: r.id, data: data)
        return SupplyLine(vendorID: v.id, vendorName: v.name, relationshipWord: v.relationshipWord, discount: discount(s, vendorID: v.id), listCost: r.cost,
                          buyPrice: buyPrice(s, r, vendorID: v.id), leadDays: r.leadDays,
                          reliability: min(0.995, max(0.8, 0.85 + (v.rating - 2.6) / 2.2 * 0.14)), owner: v.owner, capacityTotal: space.total, capacityFree: space.free)
    }

    public static func offers(_ s: GameState, companyID: Int, itemID: String, data: GameData) -> [SupplyLine] {
        guard needsSupplier(s, companyID: companyID, itemID: itemID, data: data), let co = s.company(companyID),
              let r = record(co, itemID: itemID) ?? provisional(s, co, itemID: itemID, data: data) else { return [] }
        return Suppliers.candidates(s, company: co, scope: "goods", data: data).map { line(s, companyID: companyID, $0, r, data: data) }
    }

    public static func monthlyNeed(_ s: GameState, companyID: Int, itemID: String, data: GameData) -> Int {
        guard let row = SalesItems.rows(s, companyID: companyID, data: data).first(where: { $0.id == itemID }) else { return 1 }
        return max(1, Int(saturating: (row.weeklyUnits * weeksPerMonth).rounded(.up)))
    }

    static func companyNeed(_ s: GameState, companyID: Int, data: GameData) -> Int {
        let rows = SalesItems.rows(s, companyID: companyID, data: data).filter { !$0.isService }
        return max(1, rows.reduce(0) { $0 + max(1, Int(saturating: ($1.weeklyUnits * weeksPerMonth).rounded(.up))) })
    }

    public struct Room: Equatable, Sendable {
        public var total: Int
        public var others: Int
        public var mine: Int
        public var free: Int
    }

    public static func room(_ s: GameState, companyID: Int, vendorID: String, excluding itemID: String?, data: GameData) -> Room {
        let need = Double(companyNeed(s, companyID: companyID, data: data))
        let total = max(1, Int(saturating: (need * (2.5 + 4.5 * HashedRandom.first("vcap:" + vendorID))).rounded()))
        let others = Int(saturating: (Double(total) * (0.1 + 0.45 * HashedRandom.first("vload:" + vendorID))).rounded())
        var mine = 0
        if let co = s.company(companyID) {
            for r in records(co) where r.supplierID == vendorID && r.id != itemID { mine += r.monthlyUnits }
        }
        return Room(total: total, others: others, mine: mine, free: max(0, total - others - mine))
    }

    public static func repickWeeksLeft(_ s: GameState, companyID: Int, itemID: String) -> Int {
        guard let co = s.company(companyID), let r = record(co, itemID: itemID), let w = r.pickedWeek else { return 0 }
        return max(0, repickWeeks - (s.week - w))
    }

    public static func cancelFee(_ s: GameState, companyID: Int, itemID: String) -> Double {
        guard let co = s.company(companyID), let r = record(co, itemID: itemID), r.supplierID != nil, r.monthlyUnits > 0 else { return 0 }
        return Double(r.monthlyUnits) / weeksPerMonth * buyPrice(s, r, vendorID: r.supplierID) * cancelFeeWeeks
    }

    public static func pickRefusal(_ s: GameState, companyID: Int, itemID: String, vendorID: String?, units: Int?, data: GameData) -> String? {
        guard let co = s.company(companyID) else { return "That company no longer exists." }
        let current = record(co, itemID: itemID)?.supplierID
        if let id = vendorID, id != current {
            guard Suppliers.candidates(s, company: co, scope: "goods", data: data).contains(where: { $0.id == id }) else { return "That supplier is not available." }
        }
        if vendorID != current {
            let left = repickWeeksLeft(s, companyID: companyID, itemID: itemID)
            if left > 0 { return "You changed this supplier recently. You can pick another in \(left) \(left == 1 ? "week" : "weeks")." }
        }
        guard let id = vendorID else { return nil }
        let want = units ?? monthlyNeed(s, companyID: companyID, itemID: itemID, data: data)
        if want < 1 { return "Order at least one unit a month." }
        let free = room(s, companyID: companyID, vendorID: id, excluding: itemID, data: data).free
        if want > free { return "This supplier can only take \(free) more units a month, you asked for \(want)." }
        return nil
    }

    public static func pick(_ s: inout GameState, companyID: Int, itemID: String, vendorID: String?, units: Int?, data: GameData) {
        let want = max(1, units ?? monthlyNeed(s, companyID: companyID, itemID: itemID, data: data))
        let week = s.week
        let before = s.company(companyID).flatMap { record($0, itemID: itemID) }?.supplierID
        mutate(&s, companyID: companyID, itemID: itemID) { r in
            if r.supplierID != vendorID { r.pickedWeek = week }
            r.supplierID = vendorID
            r.monthlyUnits = vendorID == nil ? 0 : want
        }
        guard let id = vendorID, id != before, let v = Suppliers.vendor(s, id: id, data: data) else { return }
        let fee = cancelFee(s, companyID: companyID, itemID: itemID)
        s.addMessage(kind: "info", from: v.name, title: "New supplier",
                     body: "\(v.name) will supply \(want) units a month. Either side can end it for a fee of two weeks of the order, now \(Int(saturating: fee.rounded())).",
                     companyID: companyID, tone: "good")
    }

    @discardableResult
    public static func cancel(_ s: inout GameState, companyID: Int, itemID: String, bySupplier: Bool, data: GameData) -> String? {
        guard let co = s.company(companyID), let r = record(co, itemID: itemID), let id = r.supplierID else { return "There is no supplier to end." }
        let fee = cancelFee(s, companyID: companyID, itemID: itemID)
        let name = Suppliers.vendor(s, id: id, data: data)?.name ?? "The supplier"
        if bySupplier {
            Payments.companyReceives(&s, companyID: companyID, amount: fee, category: "oth", label: "Fee from \(name) for ending the supply")
        } else {
            if co.cash < fee { return "Not enough cash for the cancellation fee." }
            Payments.companyPays(&s, companyID: companyID, amount: fee, category: "oth", label: "Fee to \(name) for ending the supply")
        }
        mutate(&s, companyID: companyID, itemID: itemID) { x in
            x.supplierID = nil
            x.monthlyUnits = 0
            x.pickedWeek = nil
        }
        s.addMessage(kind: "info", from: name, title: bySupplier ? "Supplier ended the supply" : "Supply ended",
                     body: bySupplier ? "\(name) stopped supplying this item and paid the fee of two weeks of the order. Pick a new supplier."
                                      : "You ended the supply from \(name) and paid the fee of two weeks of the order.",
                     companyID: companyID, tone: bySupplier ? "bad" : "n")
        return nil
    }

    @discardableResult
    static func dropFakeVendors(_ s: inout GameState) -> Int {
        var n = 0
        for i in s.companies.indices {
            for r in records(s.companies[i]) where r.supplierID?.hasPrefix("V-") == true {
                var x = r
                x.supplierID = nil
                x.monthlyUnits = 0
                x.pickedWeek = nil
                put(&s, i, x)
                n += 1
            }
        }
        return n
    }

    public static func needsSupplier(_ s: GameState, companyID: Int, itemID: String, data: GameData) -> Bool {
        guard let co = s.company(companyID), let bd = data.catalog[co.type], Suppliers.hasGoods(bd, co),
              let it = SalesItems.items(co, bd).first(where: { $0.id == itemID }) else { return false }
        if let r = record(co, itemID: itemID) { return r.model == .stk || r.model == .made }
        return !it.isService
    }

    static func provisional(_ s: GameState, _ co: Company, itemID: String, data: GameData) -> Record? {
        guard let bd = data.catalog[co.type], let it = SalesItems.items(co, bd).first(where: { $0.id == itemID }) else { return nil }
        let market = SalesItems.marketTicket(co, bd, World(state: s, data: data)) * it.ratio
        var r = Record(id: itemID, model: it.isService ? .svc : .stk)
        r.cost = fallbackCost(market: market, bd)
        return r
    }

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

    @discardableResult
    public static func migrateItem(_ s: inout GameState, companyID: Int, itemID: String, data: GameData) -> Bool {
        guard let i = s.companyIndex(companyID) else { return false }
        let co = s.companies[i]
        guard record(co, itemID: itemID) == nil, let r = provisional(s, co, itemID: itemID, data: data) else { return false }
        put(&s, i, r)
        return true
    }

    @discardableResult
    public static func migrate(_ s: inout GameState, companyID: Int, data: GameData) -> Int {
        guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return 0 }
        var n = 0
        for it in SalesItems.items(co, bd) where migrateItem(&s, companyID: companyID, itemID: it.id, data: data) { n += 1 }
        return n
    }

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

    public static func receive(_ s: inout GameState, companyID: Int, itemID: String, units: Int) {
        let week = s.week
        mutate(&s, companyID: companyID, itemID: itemID) { r in
            let n = max(0, units)
            r.onOrder = max(0, r.onOrder - n)
            if r.stock == 0 { r.since = week }
            r.stock += n
        }
    }

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
