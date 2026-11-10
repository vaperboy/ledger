import Foundation
import GameCore
import Finance

public enum SupplyMarketCatalogue {
    public static let supplies: [String: [String]] = [
        "bakery": ["goods"], "brewery": ["goods"], "farm": ["goods"], "vineyard": ["goods"], "salmon": ["goods"],
        "factory": ["goods", "mat", "pack", "parts"], "furniture": ["goods", "mat"], "grocery": ["goods"], "hardware": ["supplies", "parts", "pack"],
        "cleaning": ["clean", "laundry"], "carclean": ["clean"],
        "carrepair": ["parts", "repair"], "handy": ["repair", "parts"], "electrician": ["repair", "parts"], "plumber": ["repair", "parts"],
        "oilgas": ["fuel"],
    ]

    public struct Line: Equatable, Identifiable, Sendable {
        public var id: String
        public var name: String
        public var group: String
    }

    public static func line(_ id: String) -> Line? {
        SupplyCatalogue.catalogue.templates[id].map { Line(id: id, name: $0.name, group: $0.group) }
    }

    public static func supplyableLines(tradeID: String) -> [Line] {
        (supplies[tradeID] ?? []).compactMap { line($0) }
    }

    public static var supplierTrades: [String] { supplies.keys.sorted() }

    public static func tradesSupplying(line id: String) -> [String] { supplies.filter { $0.value.contains(id) }.map { $0.key }.sorted() }

    public static func canSupply(tradeID: String) -> Bool { !(supplies[tradeID] ?? []).isEmpty }

    public static let priceTiers: [String] = ["Basic", "Standard", "Premium"]
    public static let qualityTiers: [String] = SupplyCatalogue.qualityWords
    public static let termOptions: [Int] = [0, 14, 30]
}

public struct DeliveryRecord: Equatable, Sendable {
    public var weeksTrading: Int
    public var ordersTotal: Int
    public var ordersOnTime: Int
    public var unitsPromised: Int
    public var unitsDelivered: Int
    public var complaints: Int
    public var disputes: Int
    public var priceChanges: Int
    public var cleanWeeks: Int
    public var deliveredTrend: Double?
    public var onTimeTrend: Double?
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
    public static func isUnproven(_ r: DeliveryRecord) -> Bool { r.weeksTrading < 4 || r.ordersTotal < 5 }

    public static func score(_ r: DeliveryRecord) -> Double {
        let penalty = min(1, (Double(r.complaints) + 3 * Double(r.disputes) + 2 * Double(r.priceChanges)) / Double(max(10, r.ordersTotal)))
        return 0.5 * r.deliveredShare + 0.3 * r.onTimeShare + 0.2 * (1 - penalty)
    }

    public static func word(_ r: DeliveryRecord) -> DeliveryWord {
        if isUnproven(r) { return .unproven }
        let s = score(r)
        return s >= 0.93 ? .reliable : s >= 0.82 ? .mostlyReliable : .struggling
    }

    public static func wellKnownOrder(_ a: SupplyListing, _ b: SupplyListing) -> Bool {
        if a.isFriend != b.isFriend { return a.isFriend }
        let sa = isUnproven(a.record) ? 0 : score(a.record), sb = isUnproven(b.record) ? 0 : score(b.record)
        if abs(sa - sb) > 0.02 { return sa > sb }
        if a.record.lifetimeUnits != b.record.lifetimeUnits { return a.record.lifetimeUnits > b.record.lifetimeUnits }
        return a.id < b.id
    }

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

public struct SupplyListing: Identifiable, Equatable, Sendable {
    public var id: String
    public var ownerID: String
    public var ownerName: String
    public var profileCode: String
    public var companyName: String
    public var companyID: Int?
    public var tradeID: String
    public var tradeName: String
    public var city: String
    public var region: String
    public var country: String
    public var lineID: String
    public var lineName: String
    public var priceTier: Int
    public var qualityTier: Int
    public var capacityPerWeek: Int
    public var leadDays: Int
    public var minOrder: Int
    public var termsDays: Int
    public var linkKey: String
    public var record: DeliveryRecord
    public var isFriend: Bool
    public var isHouse: Bool
    public var paused: Bool
    public var stopped: Bool
    public var expiresDay: Int?
    public var committedUnits: Int
    public var stopsDay: Int?

    public init(id: String, ownerID: String, ownerName: String, profileCode: String, companyName: String, companyID: Int? = nil, tradeID: String, tradeName: String,
                city: String, region: String, lineID: String, lineName: String, priceTier: Int, qualityTier: Int, capacityPerWeek: Int, leadDays: Int, minOrder: Int,
                termsDays: Int, linkKey: String, record: DeliveryRecord = DeliveryRecord(), isFriend: Bool = false, isHouse: Bool = false, paused: Bool = false,
                stopped: Bool = false, expiresDay: Int? = nil, committedUnits: Int = 0, country: String = "", stopsDay: Int? = nil) {
        self.id = id; self.ownerID = ownerID; self.ownerName = ownerName; self.profileCode = profileCode; self.companyName = companyName; self.companyID = companyID
        self.tradeID = tradeID; self.tradeName = tradeName; self.city = city; self.region = region; self.lineID = lineID; self.lineName = lineName
        self.priceTier = priceTier; self.qualityTier = qualityTier; self.capacityPerWeek = capacityPerWeek; self.leadDays = leadDays; self.minOrder = minOrder
        self.termsDays = termsDays; self.linkKey = linkKey; self.record = record; self.isFriend = isFriend; self.isHouse = isHouse; self.paused = paused
        self.stopped = stopped; self.expiresDay = expiresDay; self.committedUnits = committedUnits; self.country = country; self.stopsDay = stopsDay
    }

    public var word: DeliveryWord { SupplyRecordRules.word(record) }
    public var priceFactor: Double { FriendTies.price(SupplyCatalogue.tierPrice[min(2, max(0, priceTier))], friend: isFriend) }
}

public enum SupplyAvailability: Equatable, Sendable {
    case available
    case linkedAccount
    case notOffered(String)
    case full
    case belowMinimum(Int)

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
    public static let graduationWeeks = 10

    public static func newSupplierCap(_ r: DeliveryRecord) -> Int? {
        if r.cleanWeeks >= graduationWeeks && r.disputes == 0 { return nil }
        return newSupplierStart + newSupplierStep * r.cleanWeeks
    }

    public static func effectiveCapacity(_ l: SupplyListing) -> Int {
        guard let cap = newSupplierCap(l.record) else { return l.capacityPerWeek }
        return min(l.capacityPerWeek, cap)
    }

    public static func limitText(_ l: SupplyListing) -> String? {
        newSupplierCap(l.record).map { "Limit while new: \($0) units/week" }
    }

    public static func availability(_ l: SupplyListing, buyerLinkKeys: Set<String>, units: Int, today: Int) -> SupplyAvailability {
        if buyerLinkKeys.contains(l.linkKey) { return .linkedAccount }
        if l.stopped { return .notOffered("Not available: stopped supplying") }
        if l.paused { return .notOffered("Not available: paused") }
        if let e = l.expiresDay, today > e { return .notOffered("Not available: offer ended") }
        if l.stopsDay != nil { return .notOffered("Not available: stopping soon") }
        if effectiveCapacity(l) - l.committedUnits < max(1, l.minOrder) { return .full }
        if units < l.minOrder { return .belowMinimum(l.minOrder) }
        return .available
    }

    public static let stopNoticeWeeks = 2

    public enum StopPlan: Equatable, Sendable {
        case now
        case afterNotice(endsDay: Int)
    }

    public static func stopPlan(openContracts: Int, companyGone: Bool, today: Int) -> StopPlan {
        companyGone || openContracts == 0 ? .now : .afterNotice(endsDay: today + stopNoticeWeeks * 7)
    }

    public static func accountDeletion(openContracts: Int) -> (allowed: Bool, reason: String?) {
        openContracts > 0 ? (false, "You supply \(openContracts) \(openContracts == 1 ? "buyer" : "buyers") under open contracts. Serve them out or hand them over first.") : (true, nil)
    }
}

public enum SupplyChoice {
    public static let fairPriceSlack = 1.12

    public static func randomPool(_ all: [SupplyListing], units: Int, buyerLinkKeys: Set<String>, today: Int) -> [SupplyListing] {
        let usable = all.filter { SupplyGuards.availability($0, buyerLinkKeys: buyerLinkKeys, units: units, today: today) == .available && !$0.isHouse }
        guard !usable.isEmpty else { return [] }
        let prices = usable.map { $0.priceFactor }.sorted()
        let median = prices[prices.count / 2]
        return usable.filter { $0.priceFactor <= median * fairPriceSlack && $0.word != .struggling && $0.record.disputes < 3 }
    }

    public static func weight(_ l: SupplyListing) -> Double {
        let share = Double(l.committedUnits) / Double(max(1, SupplyGuards.effectiveCapacity(l)))
        return FriendTies.weight((l.word == .unproven ? 1.25 : 1) * (1.2 - min(1, share)), friend: l.isFriend)
    }

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
    case bankrupt, accountDeleted, stopped, expired, silent

    public var phrase: String {
        switch self {
        case .bankrupt: return "went bankrupt"
        case .accountDeleted: return "closed their account"
        case .stopped: return "stopped supplying"
        case .expired: return "ended their offer"
        case .silent: return "has not reported a delivery for weeks"
        }
    }
}

public struct SupplyFallback: Equatable, Sendable {
    public var contract: SupplyContract
    public var reason: SupplyEnd
    public let title = "Your supplier stopped supplying"
    public var body: String {
        "\(contract.supplierName) \(reason.phrase). The contract ended at once and this line now comes from a market supplier at market price."
    }
}

public enum SupplyContracts {
    public static func end(_ contracts: [SupplyContract], supplierOwnerID: String, reason: SupplyEnd) -> (kept: [SupplyContract], fallbacks: [SupplyFallback]) {
        let gone = contracts.filter { $0.supplierOwnerID == supplierOwnerID }
        return (contracts.filter { $0.supplierOwnerID != supplierOwnerID }, gone.map { SupplyFallback(contract: $0, reason: reason) })
    }

    public static func end(_ contracts: [SupplyContract], listingID: String, reason: SupplyEnd) -> (kept: [SupplyContract], fallbacks: [SupplyFallback]) {
        let gone = contracts.filter { $0.listingID == listingID }
        return (contracts.filter { $0.listingID != listingID }, gone.map { SupplyFallback(contract: $0, reason: reason) })
    }
}

public enum SupplyMarketBooks {
    public static func capacity(_ co: Company, bd: Trade) -> (maxUnits: Int, why: String?) {
        guard co.status == .open else { return (0, "The company is not open yet.") }
        guard !SupplyMarketCatalogue.supplyableLines(tradeID: bd.id).isEmpty else { return (0, "This trade has nothing to supply to other players.") }
        let cap = co.value("lastW")["cap"].double
        guard cap >= 10 else { return (0, "It has no spare capacity yet. Run a full week first.") }
        return (Int(cap * 0.5), nil)
    }

    public static func unitValue(_ co: Company) -> Double {
        let cap = co.value("lastW")["cap"].double
        guard cap > 0 else { return 0 }
        return max(1, co.lastWeekRevenue / cap * 0.6)
    }

    public static let standInCostShare = 0.85

    @discardableResult
    package static func bookSaleToPlayer(_ s: inout GameState, supplierCompanyID: Int, units: Int, unitPrice: Double, unitCost: Double) -> Double {
        guard units > 0, let co = s.company(supplierCompanyID), co.status == .open else { return 0 }
        let revenue = Double(units) * unitPrice
        Payments.companyReceives(&s, companyID: supplierCompanyID, amount: revenue, category: "rev", label: "Sold to other players")
        Payments.companyPays(&s, companyID: supplierCompanyID, amount: Double(units) * unitCost, category: "cogs")
        return revenue
    }

    @discardableResult
    public static func settleSupply(_ s: inout GameState, supplierCompanyID: Int?, buyerCompanyID: Int?, units: Int, unitPrice: Double, unitCost: Double, buyerSaving: Double = 0, friend: Bool = false) -> Double? {
        let unitPrice = FriendTies.price(unitPrice, friend: friend)
        guard supplierCompanyID != nil || buyerCompanyID != nil, supplierCompanyID != buyerCompanyID else { return nil }
        if let sid = supplierCompanyID {
            guard units > 0, unitPrice >= 0, unitCost >= 0, s.company(sid)?.status == .open else { return nil }
        }
        if let bid = buyerCompanyID {
            guard let b = s.company(bid), b.status == .open else { return nil }
            if supplierCompanyID != nil, b.cash < Double(units) * unitPrice { return nil }
        }
        var revenue = 0.0
        if let sid = supplierCompanyID {
            var n = units
            var cost = unitCost
            if buyerCompanyID == nil, let i = s.companyIndex(sid) {
                let cap = s.companies[i].value("lastW")["cap"].double
                if cap > 0 { n = min(n, Int(cap * 0.5)) }
                if s.companies[i].inventory > 0 { n = min(n, Int(s.companies[i].inventory)) }
                guard n > 0 else { return nil }
                cost = max(cost, unitPrice * standInCostShare)
                if s.companies[i].inventory > 0 { s.companies[i].inventory -= Double(n) }
            }
            revenue = bookSaleToPlayer(&s, supplierCompanyID: sid, units: n, unitPrice: unitPrice, unitCost: cost)
            if let bid = buyerCompanyID { Payments.companyPays(&s, companyID: bid, amount: revenue, category: "cogs") }
        } else if let bid = buyerCompanyID {
            bookPurchaseDifference(&s, buyerCompanyID: bid, saving: buyerSaving)
        }
        return revenue
    }

    package static func bookPurchaseDifference(_ s: inout GameState, buyerCompanyID: Int, saving: Double) {
        guard s.company(buyerCompanyID) != nil else { return }
        if saving > 0 {
            Payments.companyReceives(&s, companyID: buyerCompanyID, amount: saving, category: nil, label: nil)
            Payments.book(&s, companyID: buyerCompanyID, category: "cogs", amount: -jsRound(saving))
        } else if saving < 0 {
            Payments.companyPays(&s, companyID: buyerCompanyID, amount: -saving, category: "cogs")
        }
    }

    public static func tellBuyer(_ s: inout GameState, fallback f: SupplyFallback) {
        s.addMessage(kind: "info", from: f.contract.supplierName, title: f.title, body: f.body, companyID: f.contract.buyerCompanyID, tone: "bad")
    }
}
