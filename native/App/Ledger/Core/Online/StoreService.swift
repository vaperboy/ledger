import Foundation
import Simulation

// The contract between the app and the store side: gold, boxes, cosmetics, artifacts. The views only talk to `StoreService` and
// `AuctionService`; `MockStoreService` / `MockAuctionService` stand in for the server until one exists.

/// Everything the store side holds about the player.
struct StoreState: Codable, Equatable, Sendable {
    var wallet = GoldWallet()
    /// Unopened boxes by `BoxKind.rawValue` (free boxes from the Season Pass and boxes bought in bundles).
    var boxes: [String: Int] = [:]
    var pity = BoxPity()
    var firstPurchaseDone = false
    var cabinet = Cabinet()
    var boxesOpened = 0

    func count(_ kind: BoxKind) -> Int { boxes[kind.rawValue] ?? 0 }
}

struct BoxOpening: Sendable {
    var kind: BoxKind
    var results: [BoxResult]
    var state: StoreState
    var completed: [ArtifactCollection]
}

enum StoreError: Error, Equatable, LocalizedError, Sendable {
    case notEnoughGold(missing: Int), noBox, paidBoxesUnavailable, alreadyOwned, unknownItem, notAvailable, offline
    var errorDescription: String? {
        switch self {
        case .notEnoughGold(let n): return "You need \(n) more gold."
        case .noBox: return "You have no box of that kind."
        case .paidBoxesUnavailable: return "Paid boxes are not offered where you are."
        case .alreadyOwned: return "You already have this."
        case .unknownItem: return "That item is not in the store."
        case .notAvailable: return "Buying gold is not available in this build."
        case .offline: return "Could not reach the store."
        }
    }
}

protocol StoreService: Sendable {
    /// True while purchases of gold are stand-ins that charge nothing (every build until real payments are wired).
    var isVisualOnly: Bool { get }
    func state() async -> StoreState
    /// Buys a gold pack with real money (the stand-in grants the gold without charging).
    func buyPack(_ packID: String) async throws -> StoreState
    func buySeasonBundle() async throws -> StoreState
    /// Buys a box bundle with gold; the boxes wait unopened in the stock.
    func buyBoxBundle(_ bundleID: String, paidBoxesAllowed: Bool) async throws -> StoreState
    /// Spends gold on a store cosmetic. The caller adds it to the wardrobe.
    func buyCosmetic(_ id: String, owned: Set<String>) async throws -> StoreState
    /// Spends gold on a profile icon (`AvatarCatalog`). The caller adds it to the owned icons.
    func buyAvatar(_ id: String, owned: Set<String>) async throws -> StoreState
    func openBoxes(_ kind: BoxKind, count: Int, owned: Set<String>, paidBoxesAllowed: Bool) async throws -> BoxOpening
    /// Boxes and gold from the Season Pass.
    func grantFromSeason(boxes: Int, gold: Int) async -> StoreState
}

/// The auctions as the player sees them after a refresh.
struct AuctionsSnapshot: Sendable {
    var auctions: [Auction]
    var state: StoreState
    var now: Double
    /// Display names of the people in the auctions.
    var names: [String: String]
    /// Auctions that ended since the last look and touched the player.
    var settled: [AuctionSettlement]
}

protocol AuctionService: Sendable {
    func refresh(cash: Int, priceLevel: Double) async -> AuctionsSnapshot
    func placeBid(auctionID: String, amount: Int, cash: Int) async throws -> AuctionsSnapshot
    func buyNow(auctionID: String, cash: Int) async throws -> AuctionsSnapshot
    func list(itemID: String, startPrice: Int, reserve: Int?, buyNow: Int?, duration: AuctionDuration) async throws -> AuctionsSnapshot
    func cancel(auctionID: String) async throws -> AuctionsSnapshot
}

/// Which services the app uses. The real server replaces the stand-ins by returning its implementations here.
enum StoreBackend {
    static let serverURL: URL? = nil

    static func make() -> (store: any StoreService, auctions: any AuctionService) {
        let vault = GoldVault()
        return (MockStoreService(vault: vault), MockAuctionService(vault: vault))
    }
}

enum StoreGate {
    static func access(countryCode: String?) -> StoreAccess.Access {
        StoreAccess.access(adultConfirmed: true, countryCode: countryCode ?? Locale.current.region?.identifier)
    }
}
