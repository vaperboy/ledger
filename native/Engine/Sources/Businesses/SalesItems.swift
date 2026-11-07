import Foundation
import GameCore
import Countries
import Finance

/// Per-item prices. A company sells a small list of items (products, or services in a service trade) with names of its own. Each item has a
/// revenue weight, a market price (the company's own going price times the item's price ratio), a player price (a plain real number, kept
/// unrounded, stored as a share of the market price so it follows the market), and an optional discount (percent, weeks).
///
/// Demand per item follows a constant elasticity of `elasticity` (-1.5) on price against market, clamped. The company-wide effect is
/// `demandFactor` (on `Pricing.demandEffect`) and `ticketFactor` (on `Pricing.ticket`); both are exactly 1 while every item is at the market
/// price with no discount, so a company that never touches its items plays as it did before. The record is `items27` on the company:
/// a list of { id, n, svc, q (unit share), r (price ratio, sum of q*r = 1), pm (price / market), dp (discount percent), dw (weeks left), lg (listed) }.
/// Until the player changes something nothing is stored: the default list is derived from the trade and company name.
public enum SalesItems {
    /// Price elasticity of one item's demand, and the clamps on price ratio and on the demand multiplier.
    public static let elasticity = -1.5
    public static let ratioRange = 0.3...3.0
    /// The range a player price may take against the market price. The ceiling is well under what the demand curve is clamped at: no customer
    /// pays three times the going price, and a price that far out only sells through the clamp.
    public static let priceFloor = 0.3
    public static let priceCeiling = 1.8
    public static let priceRange = priceFloor...priceCeiling
    static let demandRange = 0.4...2.5
    public static let maxItems = 12
    static let key = "items27"

    public struct Item: Equatable, Sendable {
        public var id: String
        public var name: String
        public var isService: Bool
        /// Share of customers (units) buying it; the shares add up to 1.
        public var unitShare: Double
        /// Market price of the item against the company's going ticket; unit share times ratio adds up to 1, so the weights are revenue weights.
        public var ratio: Double
        /// Player price against the market price (1 = market).
        public var priceMultiplier: Double
        public var discountPercent: Double
        public var discountWeeks: Int
        public var listedForGroup: Bool
        public var revenueWeight: Double { unitShare * ratio }
        /// Price against market after the discount.
        public var effectiveMultiplier: Double { priceMultiplier * (1 - discountPercent / 100) }
    }

    // MARK: Who sets prices

    /// The owner sets item prices unless someone is hired to: a market advisor first (it is their job), else the manager.
    public enum PriceSetter: Equatable, Sendable {
        case owner
        case advisor
        case manager(name: String)

        public var isOwner: Bool { self == .owner }
        /// "You", "Market advisor", or the manager's name.
        public var label: String {
            switch self { case .owner: return "You"; case .advisor: return "Market advisor"; case .manager(let n): return n }
        }
    }

    public static func priceSetter(_ s: GameState, _ co: Company) -> PriceSetter {
        if RoleEffects.filled(co, NewItemOptions.advisorRole) { return .advisor }
        if let m = co.managerID { return .manager(name: s.people[m]?.name ?? "Manager") }
        return .owner
    }

    // MARK: First choice

    /// A company started by the player has no products until the player chooses: while `pick1` says so, the item list the player sees is
    /// empty and the trade's starter items are offered as the first choice. Companies without the key (older saves, test setups) show everything.
    static let pickKey = "pick1"

    public static func firstChoicePending(_ co: Company) -> Bool { co.value(pickKey)["p"].bool }

    public static func markFirstChoicePending(_ s: inout GameState, _ i: Int) { s.companies[i].set(pickKey, .object(["p": .bool(true)])) }

    /// The first choice is made: every starter item except `keeping` (nil: all of them) stays out of the player's list.
    static func settlePick(_ s: inout GameState, companyID: Int, keeping: String?, data: GameData) {
        guard let i = s.companyIndex(companyID), let bd = data.catalog[s.companies[i].type], firstChoicePending(s.companies[i]) else { return }
        let hide = items(s.companies[i], bd).map(\.id).filter { $0 != keeping }
        s.companies[i].set(pickKey, .object(["p": .bool(false), "hide": .array(hide.map { .string($0) })]))
    }

    /// Ids the player does not see (starter items left unchosen).
    static func hiddenIDs(_ co: Company) -> Set<String> { Set(co.value(pickKey)["hide"].array.map(\.string)) }

    // MARK: Defaults from trade data

    /// Item concepts per trade (noun, relative price, relative share of customers). Trades not listed use their family's concepts. These reuse the
    /// concepts the game already has (menu items for cafes, restaurants and food trucks, bakes for the bakery, service lines, product ranges).
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
        "hold": [("management fee", 1.0, 1)],
    ]
    /// Venue trades that sell food and drink: their items are products (menu items), not services.
    static let goodsVenues: Set<String> = ["cafe", "restaurant", "foodtruck"]
    static let productFamilies: Set<String> = ["prod", "retail"]

    public static func isService(_ bd: Trade) -> Bool {
        if productFamilies.contains(bd.family) { return false }
        return !goodsVenues.contains(bd.id)
    }

    /// The first word of the company name, for "<name> sourdough".
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

    // MARK: Storage

    static func decode(_ j: JSONValue) -> Item {
        Item(id: j["id"].string, name: j["n"].string, isService: j["svc"].bool, unitShare: j["q"].double, ratio: j["r"].double,
             priceMultiplier: j["pm"].isNull ? 1 : j["pm"].double, discountPercent: j["dp"].double, discountWeeks: j["dw"].int, listedForGroup: j["lg"].bool)
    }

    static func encode(_ it: Item) -> JSONValue {
        .object(["id": .string(it.id), "n": .string(it.name), "svc": .bool(it.isService), "q": .number(it.unitShare), "r": .number(it.ratio),
                 "pm": .number(it.priceMultiplier), "dp": .number(it.discountPercent), "dw": .number(Double(it.discountWeeks)), "lg": .bool(it.listedForGroup)])
    }

    /// The company's items: the stored list, or the default list while nothing has been changed.
    public static func items(_ co: Company, _ bd: Trade) -> [Item] {
        let raw = co.value(key)
        return raw.isNull ? defaults(co, bd) : raw.array.map(decode)
    }

    static func store(_ s: inout GameState, _ i: Int, _ items: [Item]) { s.companies[i].set(key, .array(items.map(encode))) }

    // MARK: Demand

    /// Demand multiplier of one item against its market price: price ratio to the power of the elasticity, clamped.
    public static func demandMultiplier(priceRatio r: Double) -> Double {
        if abs(r - 1) < 1e-12 { return 1 }
        return clamp(pow(clamp(r, ratioRange.lowerBound, ratioRange.upperBound), elasticity), demandRange.lowerBound, demandRange.upperBound)
    }

    static func isNeutral(_ items: [Item]) -> Bool { items.allSatisfy { $0.effectiveMultiplier == 1 } }

    /// The company-wide demand multiplier from its items (sum of unit share times item demand). Exactly 1 at market prices.
    public static func demandFactor(_ co: Company) -> Double {
        let raw = co.value(key)
        guard !raw.isNull else { return 1 }
        let items = raw.array.map(decode)
        return isNeutral(items) ? 1 : items.reduce(0.0) { $0 + $1.unitShare * demandMultiplier(priceRatio: $1.effectiveMultiplier) }
    }

    /// The multiplier on the average ticket: revenue per customer after the mix shifts towards the cheaper items. Exactly 1 at market prices.
    public static func ticketFactor(_ co: Company) -> Double {
        let raw = co.value(key)
        guard !raw.isNull else { return 1 }
        let items = raw.array.map(decode)
        guard !isNeutral(items) else { return 1 }
        var g = 0.0, rev = 0.0
        for it in items {
            let d = it.unitShare * demandMultiplier(priceRatio: it.effectiveMultiplier)
            g += d; rev += d * it.ratio * it.effectiveMultiplier
        }
        return g > 0 ? rev / g : 1
    }

    /// Discount weeks run down; a finished discount ends with a note.
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

    // MARK: Reads

    public static func marketTicket(_ co: Company, _ bd: Trade, _ w: World) -> Double { Pricing.ticket(co, bd, w, withItems: false) }

    /// Units sold at market prices in a normal week for this company right now (last week's sales divided by what the items did to demand).
    static func baseUnits(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        let lw = co.value("lastW")
        let g = demandFactor(co)
        let units = lw["units"].isNull ? DemandModel.compute(co, bd, w).customers : lw["units"].double
        return g > 0 ? units / g : units
    }

    /// Suggestion for the name of a new item, from the trade, company name and what already exists. Deterministic.
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
