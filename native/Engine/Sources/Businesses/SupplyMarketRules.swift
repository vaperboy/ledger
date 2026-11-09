import Foundation
import GameCore
import Finance

/// The rules of supplying other players, kept pure so the app's stand-in server and the real one share them: what a trade may supply (only lines
/// of the fixed supply catalogue), how a buyer reads a delivery record, who may supply whom, the cap on new suppliers, the random pool, what
/// happens when a supplier stops, and the books of a sale to another player.

// MARK: Catalogue

public enum SupplyMarketCatalogue {
    /// What each trade can supply, as catalogue line ids. A trade not listed supplies nothing to other players.
    public static let supplies: [String: [String]] = [
        "bakery": ["goods", "pack"], "brewery": ["goods", "pack"], "farm": ["goods"], "vineyard": ["goods"], "salmon": ["goods"],
        "factory": ["goods", "mat", "pack", "parts"], "furniture": ["goods", "mat"], "grocery": ["goods"], "hardware": ["supplies", "parts", "pack"],
        "cleaning": ["clean", "laundry"], "carclean": ["clean"], "webdev": ["software"], "gamestudio": ["software"], "startup": ["software"],
        "carrepair": ["parts", "repair"], "handy": ["repair", "parts"], "electrician": ["repair", "parts"], "plumber": ["repair", "parts"],
        "power": ["power"], "oilgas": ["fuel", "power"], "courier": ["fuel"],
    ]

    public struct Line: Equatable, Identifiable, Sendable {
        public var id: String
        public var name: String
        public var group: String
    }

    /// The catalogue's name and group for a line id; nil for an id that is not in the catalogue.
    public static func line(_ id: String) -> Line? {
        SupplyCatalogue.catalogue.templates[id].map { Line(id: id, name: $0.name, group: $0.group) }
    }

    /// The lines a trade may offer, from the catalogue only.
    public static func supplyableLines(tradeID: String) -> [Line] {
        (supplies[tradeID] ?? []).compactMap { line($0) }
    }

    public static var supplierTrades: [String] { supplies.keys.sorted() }

    /// Trades that can supply this line.
    public static func tradesSupplying(line id: String) -> [String] { supplies.filter { $0.value.contains(id) }.map { $0.key }.sorted() }

    public static let priceTiers: [String] = ["Basic", "Standard", "Premium"]
    public static let qualityTiers: [String] = SupplyCatalogue.qualityWords
    public static let durations: [Int] = [1, 3, 7, 14]
    public static let termOptions: [Int] = [0, 14, 30]
}

// MARK: Delivery record

/// What a buyer sees of a supplier: the plain history behind the word.
public struct DeliveryRecord: Equatable, Sendable {
    public var weeksTrading: Int
    public var ordersTotal: Int
    public var ordersOnTime: Int
    public var unitsPromised: Int
    public var unitsDelivered: Int
    public var complaints: Int
    public var disputes: Int
    public var priceChanges: Int
    /// Weeks in a row without a late order, a complaint or a dispute.
    public var cleanWeeks: Int
    /// Change in points of share over the last four weeks (positive = better); nil with too little history.
    public var deliveredTrend: Double?
    public var onTimeTrend: Double?
    /// Units this supplier has delivered in all, for "well known".
    public var lifetimeUnits: Int

    public init(weeksTrading: Int = 0, ordersTotal: Int = 0, ordersOnTime: Int = 0, unitsPromised: Int = 0, unitsDelivered: Int = 0, complaints: Int = 0,
                disputes: Int = 0, priceChanges: Int = 0, cleanWeeks: Int = 0, deliveredTrend: Double? = nil, onTimeTrend: Double? = nil, lifetimeUnits: Int = 0) {
        self.weeksTrading = weeksTrading; self.ordersTotal = ordersTotal; self.ordersOnTime = ordersOnTime; self.unitsPromised = unitsPromised
        self.unitsDelivered = unitsDelivered; self.complaints = complaints; self.disputes = disputes; self.priceChanges = priceChanges
        self.cleanWeeks = cleanWeeks; self.deliveredTrend = deliveredTrend; self.onTimeTrend = onTimeTrend; self.lifetimeUnits = lifetimeUnits
    }

    public var deliveredShare: Double { unitsPromised > 0 ? Double(unitsDelivered) / Double(unitsPromised) : 1 }
    public var onTimeShare: Double { ordersTotal > 0 ? Double(ordersOnTime) / Double(ordersTotal) : 1 }
}

public enum DeliveryWord: String, Sendable, CaseIterable {
    case reliable = "Reliable"
    case mostlyReliable = "Mostly reliable"
    case unproven = "Unproven"
    case struggling = "Struggling"
}

public enum SupplyRecordRules {
    /// Under four weeks or five orders there is too little to judge.
    public static func isUnproven(_ r: DeliveryRecord) -> Bool { r.weeksTrading < 4 || r.ordersTotal < 5 }

    /// 0...1: delivered units count most, then punctuality, then a clean sheet (complaints, disputes and price changes after signing).
    public static func score(_ r: DeliveryRecord) -> Double {
        let penalty = min(1, (Double(r.complaints) + 3 * Double(r.disputes) + 2 * Double(r.priceChanges)) / Double(max(10, r.ordersTotal)))
        return 0.5 * r.deliveredShare + 0.3 * r.onTimeShare + 0.2 * (1 - penalty)
    }

    public static func word(_ r: DeliveryRecord) -> DeliveryWord {
        if isUnproven(r) { return .unproven }
        let s = score(r)
        return s >= 0.93 ? .reliable : s >= 0.82 ? .mostlyReliable : .struggling
    }

    /// Rank for "Well known": a proven record first, then volume delivered.
    public static func wellKnownOrder(_ a: SupplyListing, _ b: SupplyListing) -> Bool {
        let sa = isUnproven(a.record) ? 0 : score(a.record), sb = isUnproven(b.record) ? 0 : score(b.record)
        if abs(sa - sb) > 0.02 { return sa > sb }
        if a.record.lifetimeUnits != b.record.lifetimeUnits { return a.record.lifetimeUnits > b.record.lifetimeUnits }
        return a.id < b.id
    }

    /// The record after one more week of orders (units asked, units delivered, orders late, complaints raised).
    public static func applying(_ r: DeliveryRecord, promised: Int, delivered: Int, orders: Int, late: Int, complaints: Int, disputes: Int = 0, priceChanges: Int = 0) -> DeliveryRecord {
        var n = r
        n.weeksTrading += 1
        n.ordersTotal += orders
        n.ordersOnTime += max(0, orders - late)
        n.unitsPromised += promised
        n.unitsDelivered += delivered
        n.lifetimeUnits += delivered
        n.complaints += complaints
        n.disputes += disputes
        n.priceChanges += priceChanges
        n.cleanWeeks = (late == 0 && complaints == 0 && disputes == 0 && delivered >= promised) ? r.cleanWeeks + 1 : 0
        let dNow = promised > 0 ? Double(delivered) / Double(promised) : 1
        n.deliveredTrend = (dNow - r.deliveredShare) * 100
        let oNow = orders > 0 ? Double(max(0, orders - late)) / Double(orders) : 1
        n.onTimeTrend = (oNow - r.onTimeShare) * 100
        return n
    }
}

// MARK: Listing

public struct SupplyListing: Identifiable, Equatable, Sendable {
    public var id: String
    public var ownerID: String
    public var ownerName: String
    public var profileCode: String
    public var companyName: String
    /// Set when the company is one of the local player's own (its books take the sales).
    public var companyID: Int?
    public var tradeID: String
    public var tradeName: String
    public var city: String
    public var region: String
    public var lineID: String
    public var lineName: String
    public var priceTier: Int
    public var qualityTier: Int
    public var capacityPerWeek: Int
    public var leadDays: Int
    public var minOrder: Int
    public var termsDays: Int
    /// Accounts that share an owner or are otherwise linked carry the same key, and cannot supply each other.
    public var linkKey: String
    public var record: DeliveryRecord
    public var isFriend: Bool
    public var isHouse: Bool
    public var paused: Bool
    public var stopped: Bool
    /// Last day offered (the app's day count); nil = until stopped.
    public var expiresDay: Int?
    /// Units already promised this week.
    public var committedUnits: Int

    public init(id: String, ownerID: String, ownerName: String, profileCode: String, companyName: String, companyID: Int? = nil, tradeID: String, tradeName: String,
                city: String, region: String, lineID: String, lineName: String, priceTier: Int, qualityTier: Int, capacityPerWeek: Int, leadDays: Int, minOrder: Int,
                termsDays: Int, linkKey: String, record: DeliveryRecord = DeliveryRecord(), isFriend: Bool = false, isHouse: Bool = false, paused: Bool = false,
                stopped: Bool = false, expiresDay: Int? = nil, committedUnits: Int = 0) {
        self.id = id; self.ownerID = ownerID; self.ownerName = ownerName; self.profileCode = profileCode; self.companyName = companyName; self.companyID = companyID
        self.tradeID = tradeID; self.tradeName = tradeName; self.city = city; self.region = region; self.lineID = lineID; self.lineName = lineName
        self.priceTier = priceTier; self.qualityTier = qualityTier; self.capacityPerWeek = capacityPerWeek; self.leadDays = leadDays; self.minOrder = minOrder
        self.termsDays = termsDays; self.linkKey = linkKey; self.record = record; self.isFriend = isFriend; self.isHouse = isHouse; self.paused = paused
        self.stopped = stopped; self.expiresDay = expiresDay; self.committedUnits = committedUnits
    }

    public var word: DeliveryWord { SupplyRecordRules.word(record) }
    public var priceFactor: Double { SupplyCatalogue.tierPrice[min(2, max(0, priceTier))] }
}

public enum SupplyAvailability: Equatable, Sendable {
    case available
    case linkedAccount
    case notOffered(String)
    case full
    case belowMinimum(Int)

    /// What the listing says when it cannot be used.
    public var message: String? {
        switch self {
        case .available: return nil
        case .linkedAccount: return "Not available: linked account"
        case .notOffered(let why): return why
        case .full: return "Not available: fully booked this week"
        case .belowMinimum(let n): return "Minimum order is \(n) units a week"
        }
    }
}

public enum SupplyGuards {
    public static let newSupplierStart = 20
    public static let newSupplierStep = 12
    /// A clean record this long ends the limit.
    public static let graduationWeeks = 10

    /// The weekly units a new supplier may take; nil once its record is clean enough to lift the limit.
    public static func newSupplierCap(_ r: DeliveryRecord) -> Int? {
        if r.cleanWeeks >= graduationWeeks && r.disputes == 0 { return nil }
        return newSupplierStart + newSupplierStep * r.cleanWeeks
    }

    /// What the supplier can really take a week: what it listed, cut by the limit while it is new.
    public static func effectiveCapacity(_ l: SupplyListing) -> Int {
        guard let cap = newSupplierCap(l.record) else { return l.capacityPerWeek }
        return min(l.capacityPerWeek, cap)
    }

    public static func limitText(_ l: SupplyListing) -> String? {
        newSupplierCap(l.record).map { "Limit while new: \($0) units/week" }
    }

    /// Whether the buyer may use the listing: not the buyer's own or linked account, still on offer, with room and a minimum it can meet.
    public static func availability(_ l: SupplyListing, buyerLinkKeys: Set<String>, units: Int, today: Int) -> SupplyAvailability {
        if buyerLinkKeys.contains(l.linkKey) { return .linkedAccount }
        if l.stopped { return .notOffered("Not available: stopped supplying") }
        if l.paused { return .notOffered("Not available: paused") }
        if let e = l.expiresDay, today > e { return .notOffered("Not available: offer ended") }
        if effectiveCapacity(l) - l.committedUnits < max(1, l.minOrder) { return .full }
        if units < l.minOrder { return .belowMinimum(l.minOrder) }
        return .available
    }

    /// An owner with open supply contracts has to serve them out or hand them over before deleting the account.
    public static func accountDeletion(openContracts: Int) -> (allowed: Bool, reason: String?) {
        openContracts > 0 ? (false, "You supply \(openContracts) \(openContracts == 1 ? "buyer" : "buyers") under open contracts. Serve them out or hand them over first.") : (true, nil)
    }
}

// MARK: Choosing

public enum SupplyChoice {
    /// A supplier counts as fairly priced at no more than this share above the line's median price.
    public static let fairPriceSlack = 1.12

    /// The pool a random pick draws from: usable, fairly priced for the line, not struggling. Newcomers with a clean start are in it.
    public static func randomPool(_ all: [SupplyListing], units: Int, buyerLinkKeys: Set<String>, today: Int) -> [SupplyListing] {
        let usable = all.filter { SupplyGuards.availability($0, buyerLinkKeys: buyerLinkKeys, units: units, today: today) == .available && !$0.isHouse }
        guard !usable.isEmpty else { return [] }
        let prices = usable.map { $0.priceFactor }.sorted()
        let median = prices[prices.count / 2]
        return usable.filter { $0.priceFactor <= median * fairPriceSlack && $0.word != .struggling && $0.record.disputes < 3 }
    }

    /// Weight of a listing in the draw: fewer orders so far means a better chance, so one name does not take every random pick.
    public static func weight(_ l: SupplyListing) -> Double {
        let share = Double(l.committedUnits) / Double(max(1, SupplyGuards.effectiveCapacity(l)))
        return (l.word == .unproven ? 1.25 : 1) * (1.2 - min(1, share))
    }

    /// One listing drawn from the pool by weight; the same seed gives the same draw. `excluding` leaves out the one already offered.
    public static func draw(_ pool: [SupplyListing], seed: String, excluding: Set<String> = []) -> SupplyListing? {
        let p = pool.filter { !excluding.contains($0.id) }.sorted { $0.id < $1.id }
        guard !p.isEmpty else { return nil }
        let total = p.reduce(0) { $0 + weight($1) }
        var x = HashedRandom.first("supplydraw:" + seed) * total
        for l in p { x -= weight(l); if x < 0 { return l } }
        return p.last
    }

    public static func wellKnown(_ all: [SupplyListing], units: Int, buyerLinkKeys: Set<String>, today: Int, limit: Int = 5) -> [SupplyListing] {
        Array(all.filter { SupplyGuards.availability($0, buyerLinkKeys: buyerLinkKeys, units: units, today: today) == .available && !$0.isHouse }
            .sorted(by: SupplyRecordRules.wellKnownOrder).prefix(limit))
    }
}

// MARK: Contracts

public struct SupplyContract: Identifiable, Equatable, Sendable {
    public var id: String
    public var buyerCompanyID: Int
    public var lineID: String
    public var listingID: String
    public var supplierOwnerID: String
    public var supplierName: String
    public var unitsPerWeek: Int
    public var startDay: Int

    public init(id: String, buyerCompanyID: Int, lineID: String, listingID: String, supplierOwnerID: String, supplierName: String, unitsPerWeek: Int, startDay: Int) {
        self.id = id
        self.buyerCompanyID = buyerCompanyID
        self.lineID = lineID
        self.listingID = listingID
        self.supplierOwnerID = supplierOwnerID
        self.supplierName = supplierName
        self.unitsPerWeek = unitsPerWeek
        self.startDay = startDay
    }
}

public enum SupplyEnd: String, Sendable {
    case bankrupt, accountDeleted, stopped, expired

    public var phrase: String {
        switch self {
        case .bankrupt: return "went bankrupt"
        case .accountDeleted: return "closed their account"
        case .stopped: return "stopped supplying"
        case .expired: return "ended their offer"
        }
    }
}

public struct SupplyFallback: Equatable, Sendable {
    public var contract: SupplyContract
    public var reason: SupplyEnd
    public let title = "Your supplier stopped supplying"
    /// One statement of what changed, for the popup and the Inbox.
    public var body: String {
        "\(contract.supplierName) \(reason.phrase). The contract ended at once and this line now comes from the House supplier at market price."
    }
}

public enum SupplyContracts {
    /// Ends every contract with the supplier at once. The buyers fall back to the House supplier.
    public static func end(_ contracts: [SupplyContract], supplierOwnerID: String, reason: SupplyEnd) -> (kept: [SupplyContract], fallbacks: [SupplyFallback]) {
        let gone = contracts.filter { $0.supplierOwnerID == supplierOwnerID }
        return (contracts.filter { $0.supplierOwnerID != supplierOwnerID }, gone.map { SupplyFallback(contract: $0, reason: reason) })
    }

    public static func end(_ contracts: [SupplyContract], listingID: String, reason: SupplyEnd) -> (kept: [SupplyContract], fallbacks: [SupplyFallback]) {
        let gone = contracts.filter { $0.listingID == listingID }
        return (contracts.filter { $0.listingID != listingID }, gone.map { SupplyFallback(contract: $0, reason: reason) })
    }
}

// MARK: Own companies

public enum SupplyMarketBooks {
    /// Whether the company can supply others: open, a trade with something in the catalogue to supply, and real capacity (what it carried last week).
    public static func capacity(_ co: Company, bd: Trade) -> (maxUnits: Int, why: String?) {
        guard co.status == .open else { return (0, "The company is not open yet.") }
        guard !SupplyMarketCatalogue.supplyableLines(tradeID: bd.id).isEmpty else { return (0, "This trade has nothing to supply to other players.") }
        let cap = co.value("lastW")["cap"].double
        guard cap >= 10 else { return (0, "It has no spare capacity yet. Run a full week first.") }
        return (Int(cap * 0.5), nil)
    }

    /// What one unit sold on to another player is worth: the company's takings per unit of capacity, at wholesale (60%).
    public static func unitValue(_ co: Company) -> Double {
        let cap = co.value("lastW")["cap"].double
        guard cap > 0 else { return 0 }
        return max(1, co.lastWeekRevenue / cap * 0.6)
    }

    /// A sale to another player: revenue for the supplier company and the cost of what it delivered. Returns the revenue.
    @discardableResult
    public static func bookSaleToPlayer(_ s: inout GameState, supplierCompanyID: Int, units: Int, unitPrice: Double, unitCost: Double) -> Double {
        guard units > 0, let co = s.company(supplierCompanyID), co.status == .open else { return 0 }
        let revenue = Double(units) * unitPrice
        Payments.companyReceives(&s, companyID: supplierCompanyID, amount: revenue, category: "rev", label: "Sold to other players")
        Payments.companyPays(&s, companyID: supplierCompanyID, amount: Double(units) * unitCost, category: "cogs")
        return revenue
    }

    /// A purchase of the player's company from another player, against what the market supplier would have charged: a saving comes back as a
    /// lower cost of sales, extra cost is paid and booked as cost of sales (the same shape as an own-company supply).
    public static func bookPurchaseDifference(_ s: inout GameState, buyerCompanyID: Int, saving: Double) {
        guard s.company(buyerCompanyID) != nil else { return }
        if saving > 0 {
            Payments.companyReceives(&s, companyID: buyerCompanyID, amount: saving, category: nil, label: nil)
            Payments.book(&s, companyID: buyerCompanyID, category: "cogs", amount: -jsRound(saving))
        } else if saving < 0 {
            Payments.companyPays(&s, companyID: buyerCompanyID, amount: -saving, category: "cogs")
        }
    }

    /// The Inbox message for a buyer whose supplier stopped.
    public static func tellBuyer(_ s: inout GameState, fallback f: SupplyFallback) {
        s.addMessage(kind: "info", from: f.contract.supplierName, title: f.title, body: f.body, companyID: f.contract.buyerCompanyID, tone: "bad")
    }
}
