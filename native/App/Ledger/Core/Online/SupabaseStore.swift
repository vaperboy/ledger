import Foundation
import Simulation

/// Server answers the store reacts to, shared with the error mapping.
enum StoreWireText {
    static let alreadyClaimed = "This has already been claimed."
    static let noReward = "There is no reward for that."
}

/// What the server keeps for the account besides the wallet, boxes and cabinet the Store shows.
struct ServerStoreInfo: Codable, Equatable, Sendable {
    struct Streak: Codable, Equatable, Sendable { var count: Int; var best: Int; var openedToday: Bool }
    struct MoneyWeek: Codable, Equatable, Sendable { var used: Int; var cap: Int }
    struct UnpaidMoney: Codable, Equatable, Sendable { var id: String; var kind: String; var pack: String?; var amount: Int }
    var account: String
    var serverTime: Double
    var season: Int
    var debt: Int
    var cosmetics: [String]
    var premium: Bool
    var passBonusTiers: Int
    var passClaims: [String]
    var levelGoldPaid: Int
    var streak: Streak
    var freeMoneyLeft: Int
    var moneyWeek: MoneyWeek
    var unpaidMoney: [UnpaidMoney]
    var imported: Bool
    var importsGold: Bool
    /// Fields from the store extras; optional so answers and cached copies from before them still decode.
    var isAdmin: Bool?
    var supporter: Bool?
    var ads: AdTerms?
    var shelf: Shelf?
    var betaRedeemed: Bool?

    /// Rewarded-ad gold right now, with the plain and supporter terms the Store explains.
    struct AdTerms: Codable, Equatable, Sendable {
        var perDay: Int
        var used: Int
        var gold: Int
        var cooldown: Int
        /// When the next ad can pay, in seconds since 1970; nil when it can pay now.
        var nextAt: Double?
        var baseGold: Int
        var supporterGold: Int
        var baseCooldown: Int
        var supporterCooldown: Int
        var supporterAds: Int
        var watched: Int
        var left: Int { max(0, perDay - used) }
    }

    /// The cosmetics shelf of a server day.
    struct Shelf: Codable, Equatable, Sendable {
        struct Item: Codable, Equatable, Sendable { var id: String; var price: Int }
        var day: Int
        var items: [Item]
    }
}

struct ServerStoreSnapshot: Codable, Equatable, Sendable {
    var state: StoreState
    var info: ServerStoreInfo
}

/// A piece or prize the server rolled or granted.
struct ServerPiece: Codable, Equatable, Sendable { var defID: String; var serial: Int }

struct ServerBoxRoll: Decodable, Sendable {
    struct Content: Decodable, Sendable {
        var type: String
        var amount: Int?
        var doubled: Bool?
        var defID: String?
        var serial: Int?
        var id: String?
        var claimID: String?
    }
    var rarity: String
    var guaranteed: Bool
    var content: Content

    var result: BoxResult {
        let r: BoxRarity = BoxRarity(rawValue: rarity) ?? .common
        let c: BoxResult.Content
        switch content.type {
        case "gold": c = .gold(content.amount ?? 0, doubled: content.doubled ?? false)
        case "money": c = .money(content.amount ?? 0)
        case "cosmetic": c = .cosmetic(content.id ?? "")
        default: c = .artifact(ArtifactItem(defID: content.defID ?? "", serial: content.serial ?? 1))
        }
        return BoxResult(rarity: r, content: c, guaranteed: guaranteed)
    }
}

struct ServerBoxOpening: Decodable, Sendable { var kind: String; var results: [ServerBoxRoll]; var completed: [String] }
struct ServerSpend: Decodable, Sendable { var claimID: String? }
struct ServerPassClaim: Decodable, Sendable {
    struct Reward: Decodable, Sendable { var id: String; var kind: String; var amount: Int; var item: ServerPiece? }
    var reward: Reward
    var completed: [String]
}
struct ServerLevelClaim: Decodable, Sendable { var gold: Int; var paidTo: Int; var cards: [ServerPiece]; var completed: [String] }
struct ServerLoginDay: Decodable, Sendable { var opened: Bool; var count: Int; var best: Int; var gold: Int; var boxes: Int }
struct ServerGold: Decodable, Sendable { var gold: Int }
struct ServerQuickSale: Decodable, Sendable {
    struct Sold: Decodable, Sendable { var defID: String; var serial: Int; var rarity: String? }
    var sold: [Sold]
}
/// The answer to a typed code: an administrator code or a beta key.
struct ServerRedeem: Decodable, Sendable { var ok: Bool; var kind: String?; var reason: String; var gold: Int? }
/// The answer to an ad or mission gold claim.
struct ServerGoldClaim: Decodable, Sendable { var ok: Bool; var gold: Int?; var reason: String?; var wait: Int? }
struct ServerImport: Decodable, Sendable { var imported: Bool; var reason: String?; var gold: Int?; var items: Int? }
struct ServerPurchase: Decodable, Sendable {
    var granted: Bool?
    var revoked: Bool?
    var reason: String?
    var gold: Int?
    var passTiers: Int?
}

/// The phone's wallet from before the server kept it, sent once so nothing is lost and nothing is paid twice.
struct LocalStoreExport: Encodable, Sendable {
    var gold: Int
    var boxes: [String: Int]
    var pity: Int
    var firstPurchaseDone: Bool
    var items: [ArtifactItem]
    var cosmetics: [String]
    var passClaims: [String]
    var premiumSeason: Int
    var levelGoldPaid: Int
    var levelCards: [String]
    var refunded: [String]
    var streak: Int
    var streakBest: Int
    var streakOpenedToday: Bool

    var isEmpty: Bool {
        gold == 0 && boxes.values.allSatisfy { $0 <= 0 } && items.isEmpty && cosmetics.isEmpty && passClaims.isEmpty && premiumSeason == 0
            && levelGoldPaid == 0 && levelCards.isEmpty && refunded.isEmpty && streak == 0
    }
}

extension SupabaseOnlineService {
    func storeState() async throws -> Data { try await rpcData("store_state") }
    func storeBuy(kind: String, id: String, request: String) async throws -> Data {
        try await rpcData("store_buy", ["p_kind": kind, "p_id": id, "p_request": request])
    }
    func storeOpen(kind: String, count: Int, request: String) async throws -> Data {
        try await rpcData("open_boxes", ["p_kind": kind, "p_count": count, "p_request": request])
    }
    func storeFreeMoney(request: String) async throws -> Data { try await rpcData("claim_free_money", ["p_request": request]) }
    func storeConfirmMoney(_ ids: [String]) async throws -> Data { try await rpcData("confirm_money_claims", ["p_ids": ids]) }
    func storeClaimPass(season: Int, track: String, tier: Int) async throws -> Data {
        try await rpcData("claim_pass_tier", ["p_season": season, "p_track": track, "p_tier": tier])
    }
    func storeClaimLevel(_ level: Int) async throws -> Data { try await rpcData("claim_level_gold", ["p_level": level]) }
    func storeClaimLogin() async throws -> Data { try await rpcData("claim_login_day") }
    func storeClaimRace(week: Int) async throws -> Data { try await rpcData("claim_race_gold", ["p_week": week]) }
    func storeClaimRefunds() async throws -> Data { try await rpcData("claim_refund_retired") }
    func storeQuickSell(_ items: [ServerPiece], request: String) async throws -> Data {
        let list: [[String: Any]] = items.map { (p: ServerPiece) -> [String: Any] in ["defID": p.defID, "serial": p.serial] }
        return try await rpcData("quick_sell", ["p_items": list, "p_request": request])
    }
    func storeImport(device: String, payload: Data) async throws -> Data {
        let body: Any = try JSONSerialization.jsonObject(with: payload)
        return try await rpcData("import_local_store", ["p_device": device, "p_store": body])
    }
    func storeRedeem(code: String) async throws -> Data { try await rpcData("redeem_code", ["p_code": code]) }
    func storeClaimAd(claim: String) async throws -> Data { try await rpcData("claim_ad_gold", ["p_claim": claim]) }
    func storeClaimMission(id: String, period: String, gold: Int) async throws -> Data {
        try await rpcData("claim_mission_gold", ["mission_id": id, "period_key": period, "gold": gold])
    }
    func storePurchase(jws: String) async throws -> Data { try await functionData("store-purchase", ["jws": jws]) }
}

/// Talks to the server wallet. Every answer carries the account's fresh state.
struct ServerStore: Sendable {
    let online: SupabaseOnlineService

    private struct Envelope<T: Decodable>: Decodable { var state: T }

    private func decoder() -> JSONDecoder { JSONDecoder() }

    func snapshot(_ data: Data, nested: Bool = true) throws -> ServerStoreSnapshot {
        do {
            if nested {
                return ServerStoreSnapshot(state: try decoder().decode(Envelope<StoreState>.self, from: data).state,
                                           info: try decoder().decode(Envelope<ServerStoreInfo>.self, from: data).state)
            }
            return ServerStoreSnapshot(state: try decoder().decode(StoreState.self, from: data), info: try decoder().decode(ServerStoreInfo.self, from: data))
        } catch { throw OnlineError.offline }
    }

    func body<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try decoder().decode(type, from: data) } catch { throw OnlineError.offline }
    }

    func account() async -> String? { await online.signedInUserID() }

    func state() async throws -> ServerStoreSnapshot { try snapshot(try await online.storeState(), nested: false) }
}

/// The last server answer, shown read-only while the server cannot be reached.
enum ServerStoreCache {
    private static let key = "ledger.store.server.v1"
    private static let timeKey = "ledger.store.serverTime"

    static func load() -> ServerStoreSnapshot? {
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ServerStoreSnapshot.self, from: d)
    }

    static func save(_ s: ServerStoreSnapshot) {
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: key) }
        UserDefaults.standard.set(s.info.serverTime, forKey: timeKey)
    }

    static var lastServerTime: Double { UserDefaults.standard.double(forKey: timeKey) }
}

/// Auctions run against the shared cabinet, which now lives on the server; the stand-in bidders cannot settle there.
struct ClosedAuctionService: AuctionService {
    func refresh(cash: Int, priceLevel: Double) async -> AuctionsSnapshot {
        AuctionsSnapshot(auctions: [], state: StoreState(), now: Date().timeIntervalSince1970, names: [:], settled: [])
    }
    func placeBid(auctionID: String, amount: Int, cash: Int) async throws -> AuctionsSnapshot { throw StoreError.auctionsClosed }
    func buyNow(auctionID: String, cash: Int) async throws -> AuctionsSnapshot { throw StoreError.auctionsClosed }
    func list(itemID: String, startPrice: Int, reserve: Int?, buyNow: Int?, duration: AuctionDuration) async throws -> AuctionsSnapshot {
        throw StoreError.auctionsClosed
    }
    func cancel(auctionID: String) async throws -> AuctionsSnapshot { throw StoreError.auctionsClosed }
}
