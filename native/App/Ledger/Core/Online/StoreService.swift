import Foundation
import Simulation

struct StoreState: Codable, Equatable, Sendable {
    var wallet = GoldWallet()
    var boxes: [String: Int] = [:]
    var pity = BoxPity()
    var firstPurchaseDone = false
    var cabinet = Cabinet()
    var boxesOpened = 0

    func count(_ kind: BoxKind) -> Int { boxes[kind.rawValue] ?? 0 }
}

struct PurchaseDeliveryResult: Sendable {
    var state: StoreState
    var delivered: Bool
    var gold: Int
    /// Pass tiers the purchase unlocked (Battle Pass Plus Levels, the Founder pass).
    var passTiers: Int = 0
}

/// One App Store transaction as StoreKit verified it; the server checks Apple's signature again from `jws`.
struct PurchaseReceipt: Sendable {
    var transactionID: String
    var originalID: String
    var jws: String
}

struct BoxOpening: Sendable {
    var kind: BoxKind
    var results: [BoxResult]
    var state: StoreState
    var completed: [ArtifactCollection]
}

struct QuickSale: Sendable {
    var state: StoreState
    var cash: Int
    var sold: [ArtifactItem]
}

enum StoreError: Error, Equatable, LocalizedError, Sendable {
    case notEnoughGold(missing: Int), noBox, paidBoxesUnavailable, alreadyOwned, unknownItem, offline, auctionsClosed
    var errorDescription: String? {
        switch self {
        case .auctionsClosed: return "The auction house is closed for now. Quick sale still pays at once."
        case .notEnoughGold(let n): return "You need \(n) more gold."
        case .noBox: return "You have no box of that kind."
        case .paidBoxesUnavailable: return "Paid boxes are not offered where you are."
        case .alreadyOwned: return "You already have this."
        case .unknownItem: return "That item is not in the store."
        case .offline: return "You are offline. Your gold is safe on the server; spending and rewards need a connection."
        }
    }
}

protocol StoreService: Sendable {
    func state() async -> StoreState
    func deliver(_ item: PurchaseItem, transactionID: String) async throws -> PurchaseDeliveryResult
    func revoke(transactionID: String) async -> StoreState
    func buyBoxBundle(_ bundleID: String, paidBoxesAllowed: Bool) async throws -> StoreState
    func buyCosmetic(_ id: String, owned: Set<String>) async throws -> StoreState
    func buyAvatar(_ id: String, owned: Set<String>) async throws -> StoreState
    func spendGold(_ amount: Int) async throws -> StoreState
    func openBoxes(_ kind: BoxKind, count: Int, owned: Set<String>, paidBoxesAllowed: Bool) async throws -> BoxOpening
    func grantFromSeason(boxes: Int, gold: Int) async -> StoreState
    func grantCard(defID: String, roll: Double) async -> StoreState
    func quickSell(itemIDs: [String], priceLevel: Double) async throws -> QuickSale
    func giveAway(itemID: String) async throws -> StoreState
    func receiveGift(_ item: ArtifactItem) async -> (state: StoreState, completed: [ArtifactCollection])
}

struct AuctionsSnapshot: Sendable {
    var auctions: [Auction]
    var state: StoreState
    var now: Double
    var names: [String: String]
    var settled: [AuctionSettlement]
}

protocol AuctionService: Sendable {
    func refresh(cash: Int, priceLevel: Double) async -> AuctionsSnapshot
    func placeBid(auctionID: String, amount: Int, cash: Int) async throws -> AuctionsSnapshot
    func buyNow(auctionID: String, cash: Int) async throws -> AuctionsSnapshot
    func list(itemID: String, startPrice: Int, reserve: Int?, buyNow: Int?, duration: AuctionDuration) async throws -> AuctionsSnapshot
    func cancel(auctionID: String) async throws -> AuctionsSnapshot
}

enum StoreBackend {
    /// With the online server the wallet lives there and the phone's vault is only read once, to move it over.
    /// Previews and tests keep the local vault.
    static func make() -> (store: any StoreService, auctions: any AuctionService, server: ServerStore?, vault: GoldVault) {
        let vault = GoldVault()
        if let online = OnlineBackend.shared as? SupabaseOnlineService {
            return (LocalStoreService(vault: vault), ClosedAuctionService(), ServerStore(online: online), vault)
        }
        return (LocalStoreService(vault: vault), MockAuctionService(vault: vault), nil, vault)
    }
}

enum StoreGate {
    static func access(countryCode: String?) -> StoreAccess.Access {
        StoreAccess.access(adultConfirmed: true, countryCode: countryCode ?? Locale.current.region?.identifier)
    }
}
