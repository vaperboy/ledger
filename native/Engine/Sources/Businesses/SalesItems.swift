import Foundation
import GameCore
import Countries
import Finance

/// Per-item prices. A company sells a small list of items (products, or services in a service trade) with names of its own. Each item has a
/// revenue weight, a market price (the company's own going price times the item's price ratio), a player price (a plain real number, kept
/// unrounded, stored as a share of the market price so it follows the market), and an optional discount (percent, weeks).
///
/// Demand per item follows the trade's elasticity on price against market, kinked at a reference price (see `DemandShape`), clamped. The company-wide effect is
/// `demandFactor` (on `Pricing.demandEffect`) and `ticketFactor` (on `Pricing.ticket`); both are exactly 1 while every item is at the market
/// price with no discount, so a company that never touches its items plays as it did before. The record is `items27` on the company:
/// a list of { id, n, svc, q (unit share), r (price ratio, sum of q*r = 1), pm (price / market), dp (discount percent), dw (weeks left), lg (listed) }.
/// Until the player changes something nothing is stored: the default list is derived from the trade and company name.
public enum SalesItems {
    /// Elasticity of the sale-probability curve of one-off items (`ItemModels`), and the clamps on price ratio and on the demand multiplier.
    public static let elasticity = -1.5
    public static let ratioRange = 0.3...3.0
    /// The range a player price may take against the market price. The ceiling is well under what the demand curve is clamped at: no customer
    /// pays three times the going price, and a price that far out only sells through the clamp.
    public static let priceFloor = 0.3
    /// The default ceiling, for a trade with none of its own (see `ceiling(for:)`).
    public static let priceCeiling = 1.8
    public static let priceRange = priceFloor...priceCeiling

    /// Ceiling per trade, as a multiple of the market price: commodity and food trades sell close to the going price, luxury and professional trades
    /// can charge far above it. Trades not listed use their family's ceiling, then `priceCeiling`.
    static let tradeCeilings: [String: Double] = [
        "bakery": 1.5, "cafe": 1.5, "restaurant": 1.8, "foodtruck": 1.4, "grocery": 1.4, "kiosk": 1.4, "hardware": 1.5, "taxi": 1.4, "courier": 1.5,
        "parking": 1.5, "brewery": 1.6, "barber": 1.6, "carclean": 1.5, "cleaning": 1.5, "handy": 1.6, "gym": 1.7,
        "hotel": 2.2, "nightclub": 2.2, "boutique": 2.2, "cardealer": 1.6, "airline": 2.0, "event": 2.2, "photo": 2.2, "vineyard": 2.2,
        "law": 2.5, "acctfirm": 2.2, "cons": 2.5, "mktg": 2.3, "webdev": 2.2, "dental": 2.2, "physio": 2.0, "security": 1.8, "gamestudio": 2.2,
    ]
    static let familyCeilings: [String: Double] = ["prod": 1.6, "venue": 1.7, "project": 2.0, "logi": 1.5]

    /// The most a trade's item may be priced at, against its market price.
    public static func ceiling(for bd: Trade) -> Double { tradeCeilings[bd.id] ?? familyCeilings[bd.family] ?? priceCeiling }
    /// The range of price against market that the slider and the checks allow for a trade (floor 0.3).
    public static func range(for bd: Trade) -> ClosedRange<Double> { priceFloor...ceiling(for: bd) }
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

    /// Lets the trade's item module install its own starter items now instead of at the first weekly step, so the choice is made from, and
    /// hides, the list the company will really have. Idempotent (the modules install once); it moves no money.
    public static func seedStarters(_ s: inout GameState, _ i: Int, data: GameData) {
        let status = s.companies[i].status
        s.companies[i].status = .open
        ItemHooks.weekly(&s, i, data: data)
        s.companies[i].status = status
    }

    /// The item id without its module prefix ("w3-espresso", "w2_papers", "w9:x" give "espresso", "papers", "x"), as `starters` in trades.json names them.
    static func localID(_ id: String) -> String {
        guard id.hasPrefix("w"), let sep = id.firstIndex(where: { $0 == "-" || $0 == "_" || $0 == ":" }) else { return id }
        let digits = id[id.index(after: id.startIndex)..<sep]
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return id }
        return String(id[id.index(after: sep)...])
    }

    /// The three products a new company chooses its first from: the trade's `starters` ids when they all exist in `list`, else three of the
    /// list with distinct character (a cheap high-volume one, a middle one, a dearer one). A list of three or fewer is offered whole.
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

    /// Names of the items on sale now: what the add-item lists leave out. Unchosen starters and other items kept off the list can be added later.
    static func onSaleNames(_ co: Company, _ bd: Trade) -> Set<String> {
        let hidden = hiddenIDs(co)
        return Set(items(co, bd).filter { !hidden.contains($0.id) }.map { $0.name.lowercased() })
    }

    /// The first choice is made: every starter item except `keeping` (nil: all of them) stays out of the player's list, and the customers
    /// (unit shares, see `shaped`) go to what is left.
    public static func settlePick(_ s: inout GameState, companyID: Int, keeping: String?, data: GameData) {
        guard let i = s.companyIndex(companyID), firstChoicePending(s.companies[i]) else { return }
        seedStarters(&s, i, data: data)
        guard let bd = data.catalog[s.companies[i].type] else { return }
        let all = items(s.companies[i], bd)
        let hide = all.map(\.id).filter { $0 != keeping }
        let keep: [JSONValue] = keeping.map { [JSONValue.string($0)] } ?? []
        store(&s, i, all)   // a trade with no module of its own now has a stored list to hide from
        s.companies[i].set(pickKey, .object(["p": .bool(false), "hide": .array(hide.map { .string($0) }), "only": .bool(true), "keep": .array(keep)]))
    }

    /// Zero a company's sales for the week while its first choice of what to sell is still open. For the models that work out their own
    /// week (rental, developer, special families) and so do not pass through `DemandModel.compute`; costs run on.
    static func gate(_ ctx: inout CompanyWeek.WeekContext, _ co: Company) {
        guard firstChoicePending(co) else { return }
        ctx.units = 0; ctx.rev = 0; ctx.D = 0; ctx.util = 0
    }

    /// While the first choice is open nothing is on sale: 0 (customers), else 1.
    static func demandGate(_ co: Company) -> Double { firstChoicePending(co) ? 0 : 1 }

    /// Hidden starters sell nothing and their customers go to the items left: shares of the visible items add up to 1 again.
    static func shaped(_ co: Company, _ list: [Item]) -> [Item] {
        let hidden = hiddenIDs(co)
        guard !hidden.isEmpty else { return list }
        let total = list.filter { !hidden.contains($0.id) }.reduce(0.0) { $0 + $1.unitShare }
        guard total > 0 else { return list }
        return list.map { var it = $0; it.unitShare = hidden.contains(it.id) ? 0 : it.unitShare / total; return it }
    }

    /// Ids the player does not see (starter items left unchosen). After a choice (`only`), a starter a module installs later is hidden too:
    /// every stored id is hidden unless it was chosen, the owner added it (`n<k>`) or it follows an asset the owner bought (rental units).
    public static func hiddenIDs(_ co: Company) -> Set<String> {
        let pick = co.value(pickKey)
        var out = Set(pick["hide"].array.map(\.string))
        guard pick["only"].bool, !pick["p"].bool else { return out }
        let chosen = Set(pick["keep"].array.map(\.string))
        for id in co.value(key).array.map({ $0["id"].string }) where !chosen.contains(id) && !isOwnerItemID(id) { out.insert(id) }
        return out
    }

    /// Customers a narrow range draws against the full range: the square root of the visible share of customers (1 with nothing hidden), never
    /// below a quarter. A company that sells one chosen product does not get every customer the whole range would, and a dear product's ticket
    /// does not come on top of the full customer count.
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
        return shaped(co, raw.isNull ? defaults(co, bd) : raw.array.map(decode))
    }

    static func store(_ s: inout GameState, _ i: Int, _ items: [Item]) { s.companies[i].set(key, .array(items.map(encode))) }

    // MARK: Demand

    /// How one item's demand reacts to its price: the trade's elasticity, and the price (against market) customers see as fair. Above it demand
    /// is more elastic, below it less, so the best price follows the reference and the cost, not a fixed multiple of cost.
    public struct DemandShape: Equatable, Sendable {
        public var elasticity: Double
        public var reference: Double
        public init(elasticity: Double, reference: Double) { self.elasticity = elasticity; self.reference = reference }
        public static let standard = DemandShape(elasticity: 1.5, reference: 1)
        /// Elasticity below and above the reference, as multiples of the trade's.
        static let belowFactor = 0.75, aboveFactor = 1.3
    }

    /// The trade's elasticity (never under 0.8, so demand above the kink stays elastic) and a reference price that rises with quality and
    /// follows what the rivals in the city charge (size-weighted, damped). Close to 1 for a middling company with ordinary rivals.
    public static func shape(_ co: Company, _ bd: Trade, _ w: World) -> DemandShape {
        let rivals = Rivals.rivals(w.state, for: co)
        let size = rivals.reduce(0.0) { $0 + max(0.05, $1.size) }
        let avg = size > 0 ? rivals.reduce(0.0) { $0 + max(0.05, $1.size) * $1.priceFactor } / size : 1
        let quality = 1 + 0.2 * clamp((co.quality - 50) / 50, -1, 1)
        return DemandShape(elasticity: max(0.8, bd.elasticity), reference: clamp(pow(max(0.1, avg), 0.6) * quality, 0.8, 1.3))
    }

    /// Where a price against market sits against the reference (0.1 = 10% above what customers see as fair).
    public static func position(priceRatio r: Double, shape: DemandShape) -> Double { r / shape.reference - 1 }

    static func curve(_ r: Double, _ shape: DemandShape) -> Double {
        let x = r / shape.reference
        return pow(x, -shape.elasticity * (x < 1 ? DemandShape.belowFactor : DemandShape.aboveFactor))
    }

    /// Demand multiplier of one item against its market price: the kinked curve relative to its value at the market price, clamped.
    /// Exactly 1 at the market price whatever the shape.
    public static func demandMultiplier(priceRatio r: Double, shape: DemandShape = .standard) -> Double {
        if abs(r - 1) < 1e-12 { return 1 }
        let c = curve(clamp(r, ratioRange.lowerBound, ratioRange.upperBound), shape) / curve(1, shape)
        return clamp(c, demandRange.lowerBound, demandRange.upperBound)
    }

    static func isNeutral(_ items: [Item]) -> Bool { items.allSatisfy { $0.effectiveMultiplier == 1 } }

    /// The stored list as the sales maths see it (hidden starters carry no customers).
    static func loaded(_ co: Company) -> [Item]? {
        let raw = co.value(key)
        return raw.isNull ? nil : shaped(co, raw.array.map(decode))
    }

    /// The company-wide demand multiplier from its items (sum of unit share times item demand). Exactly 1 at market prices.
    public static func demandFactor(_ co: Company, _ bd: Trade? = nil, _ w: World? = nil) -> Double {
        guard let items = loaded(co) else { return 1 }
        guard !isNeutral(items) else { return 1 }
        let sh = bd.flatMap { b in w.map { shape(co, b, $0) } } ?? .standard
        return items.reduce(0.0) { $0 + $1.unitShare * demandMultiplier(priceRatio: $1.effectiveMultiplier, shape: sh) }
    }

    /// The multiplier on the average ticket: revenue per customer after the mix shifts towards the cheaper items. Exactly 1 at market prices.
    public static func ticketFactor(_ co: Company, _ bd: Trade? = nil, _ w: World? = nil) -> Double {
        guard let items = loaded(co) else { return 1 }
        // With starters hidden the mix itself moves the average ticket, even at market prices.
        guard !isNeutral(items) || !hiddenIDs(co).isEmpty else { return 1 }
        let sh = bd.flatMap { b in w.map { shape(co, b, $0) } } ?? .standard
        var g = 0.0, rev = 0.0
        for it in items {
            let d = it.unitShare * demandMultiplier(priceRatio: it.effectiveMultiplier, shape: sh)
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
