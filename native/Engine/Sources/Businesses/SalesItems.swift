import Foundation
import GameCore
import Countries
import Finance

public enum SalesItems {
    public static let elasticity = -1.5
    public static let ratioRange = 0.3...3.0
    public static let priceFloor = 0.3
    public static let priceCeiling = 1.8
    public static let priceRange = priceFloor...priceCeiling

    static let tradeCeilings: [String: Double] = [
        "bakery": 1.5, "cafe": 1.5, "restaurant": 1.8, "foodtruck": 1.4, "grocery": 1.4, "kiosk": 1.4, "hardware": 1.5, "taxi": 1.4, "courier": 1.5,
        "parking": 1.5, "brewery": 1.6, "barber": 1.6, "carclean": 1.5, "cleaning": 1.5, "handy": 1.6, "gym": 1.7,
        "hotel": 2.2, "nightclub": 2.2, "boutique": 2.2, "cardealer": 1.6, "airline": 2.0, "event": 2.2, "photo": 2.2, "vineyard": 2.2,
        "law": 2.5, "acctfirm": 2.2, "cons": 2.5, "mktg": 2.3, "webdev": 2.2, "dental": 2.2, "physio": 2.0, "security": 1.8, "gamestudio": 2.2,
    ]
    static let familyCeilings: [String: Double] = ["prod": 1.6, "venue": 1.7, "project": 2.0, "logi": 1.5]

    public static func ceiling(for bd: Trade) -> Double { tradeCeilings[bd.id] ?? familyCeilings[bd.family] ?? priceCeiling }
    public static func range(for bd: Trade) -> ClosedRange<Double> { priceFloor...ceiling(for: bd) }
    static let demandRange = 0.4...2.5
    public static let maxItems = 12
    static let key = "items27"

    public struct Item: Equatable, Sendable {
        public var id: String
        public var name: String
        public var isService: Bool
        public var unitShare: Double
        public var ratio: Double
        public var priceMultiplier: Double
        public var discountPercent: Double
        public var discountWeeks: Int
        public var listedForGroup: Bool
        public var revenueWeight: Double { unitShare * ratio }
        public var effectiveMultiplier: Double { priceMultiplier * (1 - discountPercent / 100) }
    }

    public enum PriceSetter: Equatable, Sendable {
        case owner
        case advisor
        case manager(name: String)

        public var isOwner: Bool { self == .owner }
        public var label: String {
            switch self { case .owner: return "You"; case .advisor: return "Market advisor"; case .manager(let n): return n }
        }
    }

    public static func priceSetter(_ s: GameState, _ co: Company) -> PriceSetter {
        if RoleEffects.filled(co, NewItemOptions.advisorRole) { return .advisor }
        if let m = co.managerID { return .manager(name: s.people[m]?.name ?? "Manager") }
        return .owner
    }

    static let pickKey = "pick1"

    public static func firstChoicePending(_ co: Company) -> Bool { co.value(pickKey)["p"].bool }

    public static func markFirstChoicePending(_ s: inout GameState, _ i: Int) { s.companies[i].set(pickKey, .object(["p": .bool(true)])) }

    public static func seedStarters(_ s: inout GameState, _ i: Int, data: GameData) {
        let status = s.companies[i].status
        s.companies[i].status = .open
        ItemHooks.weekly(&s, i, data: data)
        s.companies[i].status = status
    }

    static func localID(_ id: String) -> String {
        guard id.hasPrefix("w"), let sep = id.firstIndex(where: { $0 == "-" || $0 == "_" || $0 == ":" }) else { return id }
        let digits = id[id.index(after: id.startIndex)..<sep]
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return id }
        return String(id[id.index(after: sep)...])
    }

    public static func starterIDs(_ bd: Trade, _ list: [Item]) -> [String] {
        guard list.count > 3 else { return list.map(\.id) }
        let named = bd.raw["starters"].array.map(\.string)
        let byLocal = Dictionary(list.map { (localID($0.id), $0.id) }, uniquingKeysWith: { a, _ in a })
        let fromData = named.compactMap { byLocal[$0] }
        if named.count == 3, fromData.count == 3, Set(fromData).count == 3 { return fromData }
        let byPrice = list.sorted { $0.ratio != $1.ratio ? $0.ratio < $1.ratio : $0.id < $1.id }
        let third = max(1, byPrice.count / 3)
        let maxShare = byPrice.map(\.unitShare).max() ?? 0
        let cheap = byPrice.prefix(third).max { $0.unitShare < $1.unitShare }
        let top = byPrice.suffix(third)
        let dear = top.filter { $0.unitShare >= 0.15 * maxShare }.max { $0.ratio < $1.ratio } ?? top.last
        guard let c = cheap, let d = dear, c.id != d.id else { return byPrice.prefix(3).map(\.id) }
        let mid = byPrice.filter { $0.id != c.id && $0.id != d.id }.min { abs($0.ratio - 1) < abs($1.ratio - 1) }
        return [c.id] + (mid.map { [$0.id] } ?? []) + [d.id]
    }

    static func onSaleNames(_ co: Company, _ bd: Trade) -> Set<String> {
        let hidden = hiddenIDs(co)
        return Set(items(co, bd).filter { !hidden.contains($0.id) }.map { $0.name.lowercased() })
    }

    public static func settlePick(_ s: inout GameState, companyID: Int, keeping: String?, data: GameData) {
        guard let i = s.companyIndex(companyID), firstChoicePending(s.companies[i]) else { return }
        seedStarters(&s, i, data: data)
        guard let bd = data.catalog[s.companies[i].type] else { return }
        let all = stored(s.companies[i], bd)
        let hide = all.map(\.id).filter { $0 != keeping }
        let keep: [JSONValue] = keeping.map { [JSONValue.string($0)] } ?? []
        store(&s, i, all)
        s.companies[i].set(pickKey, .object(["p": .bool(false), "hide": .array(hide.map { .string($0) }), "only": .bool(true), "keep": .array(keep)]))
    }

    static func gate(_ ctx: inout CompanyWeek.WeekContext, _ co: Company) {
        guard firstChoicePending(co) else { return }
        ctx.units = 0; ctx.rev = 0; ctx.D = 0; ctx.util = 0
    }

    static func demandGate(_ co: Company) -> Double { firstChoicePending(co) ? 0 : 1 }

    static func shaped(_ co: Company, _ list: [Item]) -> [Item] {
        let hidden = hiddenIDs(co)
        guard !hidden.isEmpty else { return list }
        let total = list.filter { !hidden.contains($0.id) }.reduce(0.0) { $0 + $1.unitShare }
        guard total > 0 else { return list }
        return list.map { var it = $0; it.unitShare = hidden.contains(it.id) ? 0 : it.unitShare / total; return it }
    }

    public static func hiddenIDs(_ co: Company) -> Set<String> {
        let pick = co.value(pickKey)
        var out = Set(pick["hide"].array.map(\.string))
        guard pick["only"].bool, !pick["p"].bool else { return out }
        let chosen = Set(pick["keep"].array.map(\.string))
        for id in co.value(key).array.map({ $0["id"].string }) where !chosen.contains(id) && !isOwnerItemID(id) { out.insert(id) }
        return out
    }

    static func rangeFactor(_ co: Company) -> Double {
        let hidden = hiddenIDs(co)
        guard !hidden.isEmpty else { return 1 }
        let raw = co.value(key).array
        let total = raw.reduce(0.0) { $0 + $1["q"].double }
        guard total > 0 else { return 1 }
        let visible = raw.filter { !hidden.contains($0["id"].string) }.reduce(0.0) { $0 + $1["q"].double }
        return clamp((visible / total).squareRoot(), 0.25, 1)
    }

    static func isOwnerItemID(_ id: String) -> Bool {
        if id.hasPrefix(RentalUnits.unitPrefix) { return true }
        return id.count > 1 && id.hasPrefix("n") && id.dropFirst().allSatisfy(\.isNumber)
    }

    static let tradeNouns: [String: [(String, Double, Double)]] = [
        "bakery": [("sourdough", 1.0, 3), ("croissants", 0.8, 4), ("celebration cake", 4.0, 0.6), ("sandwich", 1.3, 2)],
        "cafe": [("coffee", 0.9, 5), ("pastry", 0.8, 3), ("lunch plate", 2.2, 1.5)],
        "restaurant": [("starter", 0.6, 2), ("main course", 1.5, 4), ("dessert", 0.6, 2), ("wine", 1.2, 1.5)],
        "foodtruck": [("signature wrap", 1.2, 4), ("fries", 0.6, 3), ("drink", 0.5, 3)],
        "barber": [("haircut", 1.0, 5), ("beard trim", 0.6, 2), ("full style", 1.8, 1)],
        "gym": [("monthly pass", 1.0, 4), ("class pack", 0.8, 3), ("personal training", 2.5, 1)],
        "cons": [("advisory hour", 1.0, 5), ("workshop", 2.5, 1), ("audit", 3.0, 0.6)],
        "webdev": [("website build", 3.0, 1), ("maintenance plan", 0.5, 4), ("custom feature", 1.5, 2)],
        "grocery": [("fresh produce", 0.8, 4), ("pantry basket", 1.2, 3), ("ready meals", 1.0, 2)],
        "boutique": [("everyday piece", 0.7, 4), ("signature piece", 1.4, 2), ("accessory", 0.4, 3)],
    ]
    static let familyNouns: [String: [(String, Double, Double)]] = [
        "prod": [("classic", 1.0, 4), ("signature", 1.5, 2), ("premium", 2.4, 1)],
        "venue": [("standard", 1.0, 4), ("favourite", 1.4, 2), ("special", 2.0, 1)],
        "retail": [("everyday range", 0.8, 4), ("signature range", 1.3, 2), ("premium range", 2.2, 1)],
        "svc": [("standard service", 1.0, 4), ("extended service", 1.6, 2), ("premium service", 2.4, 1)],
        "project": [("small job", 0.6, 4), ("standard job", 1.0, 3), ("large job", 2.2, 1)],
        "logi": [("standard run", 1.0, 4), ("express run", 1.6, 2), ("bulk run", 2.2, 1)],
        "rent": [("standard let", 1.0, 4), ("premium let", 1.6, 2)],
        "fin": [("basic plan", 1.0, 4), ("plus plan", 1.6, 2)],
        "energy": [("standard supply", 1.0, 4), ("green supply", 1.3, 2)],
        "club": [("entry", 1.0, 4), ("night out", 1.5, 2), ("table", 3.5, 0.5)],
    ]
    static let goodsVenues: Set<String> = ["cafe", "restaurant", "foodtruck"]
    static let productFamilies: Set<String> = ["prod", "retail"]

    public static func isService(_ bd: Trade) -> Bool {
        if productFamilies.contains(bd.family) { return false }
        return !goodsVenues.contains(bd.id)
    }

    static func shortName(_ co: Company) -> String {
        let first = co.name.split(separator: " ").first.map(String.init) ?? co.name
        return first.count >= 2 ? first : co.name
    }

    static func defaults(_ co: Company, _ bd: Trade) -> [Item] {
        let rows = tradeNouns[bd.id] ?? familyNouns[bd.family] ?? [("standard", 1.0, 1)]
        let sumQ = rows.reduce(0.0) { $0 + $1.2 }
        let qs = rows.map { $0.2 / sumQ }
        let norm = zip(rows, qs).reduce(0.0) { $0 + $1.0.1 * $1.1 }
        let short = shortName(co)
        let svc = isService(bd)
        return rows.indices.map { k in
            Item(id: "d\(k)", name: "\(short) \(rows[k].0)", isService: svc, unitShare: qs[k], ratio: rows[k].1 / norm,
                 priceMultiplier: 1, discountPercent: 0, discountWeeks: 0, listedForGroup: false)
        }
    }

    static func decode(_ j: JSONValue) -> Item {
        Item(id: j["id"].string, name: j["n"].string, isService: j["svc"].bool, unitShare: j["q"].double, ratio: j["r"].double,
             priceMultiplier: j["pm"].isNull ? 1 : j["pm"].double, discountPercent: j["dp"].double, discountWeeks: j["dw"].int, listedForGroup: j["lg"].bool)
    }

    static func encode(_ it: Item) -> JSONValue {
        .object(["id": .string(it.id), "n": .string(it.name), "svc": .bool(it.isService), "q": .number(it.unitShare), "r": .number(it.ratio),
                 "pm": .number(it.priceMultiplier), "dp": .number(it.discountPercent), "dw": .number(Double(it.discountWeeks)), "lg": .bool(it.listedForGroup)])
    }

    // The list as saved. Hidden starters keep their share here, so edits never change how wide the range counts.
    static func stored(_ co: Company, _ bd: Trade) -> [Item] {
        let raw = co.value(key)
        return raw.isNull ? defaults(co, bd) : raw.array.map(decode)
    }

    public static func items(_ co: Company, _ bd: Trade) -> [Item] { shaped(co, stored(co, bd)) }

    // True once an item price or discount differs from the market default.
    public static func hasOwnPrices(_ co: Company) -> Bool {
        co.value(key).array.contains { (j: JSONValue) -> Bool in (!j["pm"].isNull && j["pm"].double != 1) || j["dp"].double > 0 }
    }

    static func store(_ s: inout GameState, _ i: Int, _ items: [Item]) { s.companies[i].set(key, .array(items.map(encode))) }

    public struct DemandShape: Equatable, Sendable {
        public var elasticity: Double
        public var reference: Double
        public init(elasticity: Double, reference: Double) { self.elasticity = elasticity; self.reference = reference }
        public static let standard = DemandShape(elasticity: 1.5, reference: 1)
        static let belowFactor = 0.75, aboveFactor = 1.3
    }

    public static func shape(_ co: Company, _ bd: Trade, _ w: World) -> DemandShape {
        let rivals = Rivals.rivals(w.state, for: co)
        let size = rivals.reduce(0.0) { $0 + max(0.05, $1.size) }
        let avg = size > 0 ? rivals.reduce(0.0) { $0 + max(0.05, $1.size) * $1.priceFactor } / size : 1
        let quality = 1 + 0.2 * clamp((co.quality - 50) / 50, -1, 1)
        return DemandShape(elasticity: max(0.8, bd.elasticity), reference: clamp(pow(max(0.1, avg), 0.6) * quality, 0.8, 1.3))
    }

    public static func position(priceRatio r: Double, shape: DemandShape) -> Double { r / shape.reference - 1 }

    static func curve(_ r: Double, _ shape: DemandShape) -> Double {
        let x = r / shape.reference
        return pow(x, -shape.elasticity * (x < 1 ? DemandShape.belowFactor : DemandShape.aboveFactor))
    }

    public static func demandMultiplier(priceRatio r: Double, shape: DemandShape = .standard) -> Double {
        if abs(r - 1) < 1e-12 { return 1 }
        let c = curve(clamp(r, ratioRange.lowerBound, ratioRange.upperBound), shape) / curve(1, shape)
        return clamp(c, demandRange.lowerBound, demandRange.upperBound)
    }

    static func isNeutral(_ items: [Item]) -> Bool { items.allSatisfy { $0.effectiveMultiplier == 1 } }

    static func loaded(_ co: Company) -> [Item]? {
        let raw = co.value(key)
        return raw.isNull ? nil : shaped(co, raw.array.map(decode))
    }

    public static func demandFactor(_ co: Company, _ bd: Trade? = nil, _ w: World? = nil) -> Double {
        guard let items = loaded(co) else { return 1 }
        guard !isNeutral(items) else { return 1 }
        let sh = bd.flatMap { b in w.map { shape(co, b, $0) } } ?? .standard
        return items.reduce(0.0) { $0 + $1.unitShare * demandMultiplier(priceRatio: $1.effectiveMultiplier, shape: sh) }
    }

    public static func ticketFactor(_ co: Company, _ bd: Trade? = nil, _ w: World? = nil) -> Double {
        guard let items = loaded(co) else { return 1 }
        guard !isNeutral(items) || !hiddenIDs(co).isEmpty else { return 1 }
        let sh = bd.flatMap { b in w.map { shape(co, b, $0) } } ?? .standard
        var g = 0.0, rev = 0.0
        for it in items {
            let d = it.unitShare * demandMultiplier(priceRatio: it.effectiveMultiplier, shape: sh)
            g += d; rev += d * it.ratio * it.effectiveMultiplier
        }
        return g > 0 ? rev / g : 1
    }

    static func weeklyTick(_ s: inout GameState, _ i: Int) {
        let raw = s.companies[i].value(key)
        guard !raw.isNull else { return }
        var items = raw.array.map(decode), changed = false
        for k in items.indices where items[k].discountWeeks > 0 {
            items[k].discountWeeks -= 1
            changed = true
            if items[k].discountWeeks == 0 {
                items[k].discountPercent = 0
                s.note("The discount on \(items[k].name) has ended.", tone: "n", companyID: s.companies[i].id)
            }
        }
        if changed { store(&s, i, items) }
    }

    public static func marketTicket(_ co: Company, _ bd: Trade, _ w: World) -> Double { Pricing.ticket(co, bd, w, withItems: false) }

    static func baseUnits(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        let lw = co.value("lastW")
        let g = demandFactor(co)
        let units = lw["units"].isNull ? DemandModel.compute(co, bd, w).customers : lw["units"].double
        return g > 0 ? units / g : units
    }

    public static func suggestedName(_ co: Company, _ bd: Trade, isService svc: Bool, seed: Int) -> String {
        let existing = Set(items(co, bd).map { $0.name.lowercased() })
        let pool = svc ? ["consultation", "express service", "care plan", "workshop", "premium package", "weekend special"]
                       : ["limited edition", "house special", "seasonal pick", "bestseller", "gift box", "family pack"]
        var h = HashedRandom("\(seed):itemname:\(co.id):\(items(co, bd).count)")
        let start = Int(h.next() * Double(pool.count))
        for k in pool.indices {
            let n = "\(shortName(co)) \(pool[(start + k) % pool.count])"
            if !existing.contains(n.lowercased()) { return n }
        }
        return "\(shortName(co)) item \(items(co, bd).count + 1)"
    }
}
