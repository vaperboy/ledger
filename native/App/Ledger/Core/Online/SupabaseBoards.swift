import Foundation
import Businesses
import Simulation

struct LeaderboardRow: Decodable, Equatable {
    var playerID: String
    var name: String
    var week: Int
    var netWorth: Double
    var tradingResult: Double
}

extension SupabaseOnlineService {
    func publishLeaderboard(netWorth: Double, tradingResult: Double, week: Int) async throws {
        _ = try await rpcData("publish_leaderboard", ["p_net_worth": netWorth, "p_trading_result": tradingResult, "p_game_week": week])
    }

    func leaderboardRows() async throws -> [LeaderboardRow] { try decode([LeaderboardRow].self, try await rpcData("read_leaderboards")) }
}

actor SupabaseLeaderboardService: LeaderboardService {
    private let online: SupabaseOnlineService

    init(online: SupabaseOnlineService) { self.online = online }

    func publish(_ mine: LeaderboardSubmission) async {
        guard mine.netWorth.isFinite, mine.tradingResult.isFinite else { return }
        try? await online.publishLeaderboard(netWorth: mine.netWorth, tradingResult: mine.tradingResult, week: mine.week)
    }

    func submissions() async -> [LeaderboardSubmission] {
        guard let rows = try? await online.leaderboardRows() else { return [] }
        return rows.map { (r: LeaderboardRow) -> LeaderboardSubmission in
            LeaderboardSubmission(playerID: r.playerID, name: r.name, week: r.week, netWorth: r.netWorth, tradingResult: r.tradingResult)
        }
    }
}

struct WorldRulesSnapshot: Decodable, Equatable, Sendable {
    struct Exchange: Decodable, Equatable, Sendable {
        var bandLow: Double
        var bandHigh: Double
        var dayMoveShare: Double
        var valueStepShare: Double
        var holderCapShare: Double
        var ownerFloorShare: Double
        var lockUpDays: Double
        var quarterDays: Double
        var blackoutBefore: Double
        var blackoutAfter: Double
    }
    var rules: [String: Double]
    var exchange: Exchange
    var updatedAt: Date?
}

protocol WorldRulesService: Sendable {
    func snapshot() async -> WorldRulesSnapshot?
}

struct OfflineWorldRulesService: WorldRulesService {
    func snapshot() async -> WorldRulesSnapshot? { nil }
}

extension SupabaseOnlineService: WorldRulesService {
    func snapshot() async -> WorldRulesSnapshot? {
        guard let data = try? await rpcData("world_rules_read") else { return nil }
        return try? decode(WorldRulesSnapshot.self, data)
    }
}

enum WorldRulesSync {
    nonisolated(unsafe) static var apply: ((WorldRulesSnapshot) -> Void)?
    nonisolated(unsafe) private(set) static var latest: WorldRulesSnapshot?

    static func refresh(from service: any WorldRulesService = OnlineBackend.worldRules) async {
        guard let s = await service.snapshot() else { return }
        latest = s
        apply?(s)
    }
}

extension OnlineBackend {
    static var worldRules: any WorldRulesService { (shared as? SupabaseOnlineService) ?? OfflineWorldRulesService() }
}

struct ServerPlayerEvent: Decodable, Equatable {
    var id: String
    var kind: String
    var playerID: String
    var playerName: String
    var countryCode: String
    var audience: String
    var day: Int
    var trade: String?
    var city: String?
    var company: String?
    var count: Int?
    var otherName: String?
    var club: String?
    var isFriend: Bool
    var namesVisible: Bool

    var event: PlayerEvent? {
        guard let k = PlayerEventKind(rawValue: kind) else { return nil }
        return PlayerEvent(id: id, kind: k, playerID: playerID, playerName: playerName, countryCode: countryCode, audience: PlayerEventAudience(rawValue: audience) ?? .friends,
                           day: day, trade: trade, city: city, company: company, count: count, otherName: otherName, club: club)
    }
}

final class SupabaseNewsFeedService: NewsFeedService, @unchecked Sendable {
    private let online: SupabaseOnlineService
    private let lock = NSLock()
    private var named: Set<String> = []

    init(online: SupabaseOnlineService) { self.online = online }

    func isFriend(_ playerID: String) -> Bool { lock.withLock { named.contains(playerID) } }

    func events(now: Date) async -> [PlayerEvent] {
        guard let data = try? await online.rpcData("news_feed", ["p_filter": "everyone", "p_limit": 60]),
              let rows = try? await online.decode([ServerPlayerEvent].self, data) else { return [] }
        lock.withLock { named = Set(rows.filter { $0.namesVisible }.map { $0.playerID }) }
        return rows.compactMap { $0.event }
    }
}

enum NewsFeedBackend {
    static func make() -> NewsFeedService {
        guard let service = OnlineBackend.shared as? SupabaseOnlineService else { return MockNewsFeedService() }
        return SupabaseNewsFeedService(online: service)
    }
}

extension LeaderboardBackend {
    static func online() -> any LeaderboardService {
        guard let service = OnlineBackend.shared as? SupabaseOnlineService else { return OfflineLeaderboardService() }
        return SupabaseLeaderboardService(online: service)
    }
}
