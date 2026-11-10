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
    case notEnoughGold(missing: Int), noBox, paidBoxesUnavailable, alreadyOwned, unknownItem, offline
    var errorDescription: String? {
        switch self {
        case .notEnoughGold(let n): return "You need \(n) more gold."
        case .noBox: return "You have no box of that kind."
        case .paidBoxesUnavailable: return "Paid boxes are not offered where you are."
        case .alreadyOwned: return "You already have this."
        case .unknownItem: return "That item is not in the store."
        case .offline: return "Could not reach the store."
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
    static let serverURL: URL? = nil

    static func make() -> (store: any StoreService, auctions: any AuctionService) {
        let vault = GoldVault()
        return (LocalStoreService(vault: vault), MockAuctionService(vault: vault))
    }
}

enum StoreGate {
    static func access(countryCode: String?) -> StoreAccess.Access {
        StoreAccess.access(adultConfirmed: true, countryCode: countryCode ?? Locale.current.region?.identifier)
    }
}
