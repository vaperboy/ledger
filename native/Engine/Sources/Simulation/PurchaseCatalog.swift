import Foundation

public enum PurchaseItem: Hashable, Sendable {
    case plan(LedgerProduct)
    case goldPack(String)
    case seasonBundle
    case seasonLevels
    case perk(PlanPerk)
}

public enum PlanPerk: String, Hashable, Sendable, CaseIterable {
    case pro, founder, founderPass

    public static func perk(for product: LedgerProduct) -> PlanPerk? {
        switch product {
        case .pro, .proYearly: return .pro
        case .founder: return .founder
        case .plusMonthly, .plusYearly: return nil
        }
    }

    public func claimID(season: Int) -> String { self == .founderPass ? "perk.\(rawValue).s\(season)" : "perk.\(rawValue)" }
}

public enum PlanPerks {
    public static let plusFlair = "gold.flair.plus"
    public static let plusAvatar = "av.plus.ink"
    public static let proAvatar = "av.pro.gilded"
    public static let founderFlair = "gold.flair.founder"
    public static let founderLogoPerk = "founder"

    public static func founderOnSale(season: Int) -> Bool { season <= GoldPrices.founderLastSeason }

    public static func founderPassOpen(season: Int) -> Bool { season == 1 }

    public static func cosmetics(for p: LedgerProduct) -> [String] {
        switch p {
        case .plusMonthly, .plusYearly: return [plusFlair]
        case .founder: return [founderFlair]
        case .pro, .proYearly: return []
        }
    }

    public static func perks(owned: Set<LedgerProduct>) -> Set<String> {
        owned.contains(.founder) ? [founderLogoPerk] : []
    }
}

public enum PurchaseCatalog {
    public static let productPrefix = "com.ledger."
    public static let seasonBundleID = productPrefix + "season.bundle"
    public static let seasonLevelsID = productPrefix + "season.levels"

    public static func productID(_ item: PurchaseItem) -> String {
        switch item {
        case .plan(let p): return p.rawValue
        case .goldPack(let id): return productPrefix + id
        case .seasonBundle: return seasonBundleID
        case .seasonLevels: return seasonLevelsID
        case .perk(let k): return productPrefix + "perk." + k.rawValue
        }
    }

    public static var items: [PurchaseItem] {
        LedgerProduct.allCases.map { PurchaseItem.plan($0) } + GoldStore.packs.map { PurchaseItem.goldPack($0.id) } + [PurchaseItem.seasonBundle, PurchaseItem.seasonLevels]
    }

    public static var allProductIDs: [String] { items.map { productID($0) } }

    public static var consumableProductIDs: [String] { items.filter { isConsumable($0) }.map { productID($0) } }

    public static func item(forProductID id: String) -> PurchaseItem? { items.first { productID($0) == id } }

    public static func isConsumable(_ item: PurchaseItem) -> Bool {
        if case .plan = item { return false }
        return true
    }

    public static func goldGranted(_ item: PurchaseItem, firstPurchase: Bool) -> Int {
        switch item {
        case .plan: return 0
        case .goldPack(let id): return GoldStore.packs.first { $0.id == id }.map { GoldStore.totalGold($0, firstPurchase: firstPurchase) } ?? 0
        case .seasonBundle: return GoldStore.seasonBundle.gold
        case .seasonLevels: return GoldStore.seasonLevels.gold
        case .perk(let k):
            switch k {
            case .pro: return GoldPrices.proBundleGold
            case .founder: return GoldPrices.founderBundleGold
            case .founderPass: return 0
            }
        }
    }
}

public struct PurchaseDelivery: Codable, Equatable, Sendable {
    public var transactionID: String
    public var productID: String
    public var gold: Int
    public var revoked: Bool

    public init(transactionID: String, productID: String, gold: Int, revoked: Bool = false) {
        self.transactionID = transactionID; self.productID = productID; self.gold = gold; self.revoked = revoked
    }
}

public struct DeliveryLedger: Codable, Equatable, Sendable {
    public static let limit = 500
    public private(set) var entries: [PurchaseDelivery] = []

    public init() {}

    public func entry(_ transactionID: String) -> PurchaseDelivery? { entries.first { $0.transactionID == transactionID } }

    public func has(_ transactionID: String) -> Bool { entry(transactionID) != nil }

    @discardableResult
    public mutating func record(_ delivery: PurchaseDelivery) -> Bool {
        guard !has(delivery.transactionID) else { return false }
        entries.append(delivery)
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
        return true
    }

    public mutating func revoke(_ transactionID: String) -> PurchaseDelivery? {
        guard let i = entries.firstIndex(where: { $0.transactionID == transactionID }), !entries[i].revoked else { return nil }
        entries[i].revoked = true
        return entries[i]
    }
}

public enum PurchaseRules {
    public enum Verdict: Equatable, Sendable {
        case deliver, alreadyDelivered, revoked, entitlement, unknown
    }

    public static func verdict(productID: String, transactionID: String, revoked: Bool, ledger: DeliveryLedger) -> Verdict {
        guard let item = PurchaseCatalog.item(forProductID: productID) else { return .unknown }
        guard PurchaseCatalog.isConsumable(item) else { return .entitlement }
        if revoked { return .revoked }
        return ledger.has(transactionID) ? .alreadyDelivered : .deliver
    }
}
