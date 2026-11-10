import Foundation

public enum PurchaseItem: Hashable, Sendable {
    case plan(LedgerProduct)
    case goldPack(String)
    case seasonBundle
}

public enum PurchaseCatalog {
    public static let productPrefix = "com.ledger."
    public static let seasonBundleID = productPrefix + "season.bundle"

    public static func productID(_ item: PurchaseItem) -> String {
        switch item {
        case .plan(let p): return p.rawValue
        case .goldPack(let id): return productPrefix + id
        case .seasonBundle: return seasonBundleID
        }
    }

    public static var items: [PurchaseItem] {
        LedgerProduct.allCases.map { PurchaseItem.plan($0) } + GoldStore.packs.map { PurchaseItem.goldPack($0.id) } + [PurchaseItem.seasonBundle]
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
