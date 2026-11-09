import Foundation
import Businesses
import Simulation

// Leaderboards, accountant offices and the world rules over the Supabase functions of migration 0014. The server decides what a player
// may see and what a figure may be; nothing here filters or trusts anything. Nothing runs unless `OnlineConfig.useServer` is true.

// MARK: Leaderboards

/// One other player as `read_leaderboards` returns them.
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

/// The boards over the server. A guest or a failed call changes nothing: publishing is best effort and reading gives nobody.
actor SupabaseLeaderboardService: LeaderboardService {
    private let online: SupabaseOnlineService
    /// The engine has no public initialiser for a submission, so the player's own latest one is the template the other rows are copied from.
    private var template: LeaderboardSubmission?

    init(online: SupabaseOnlineService) { self.online = online }

    func publish(_ mine: LeaderboardSubmission) async {
        template = mine
        guard mine.netWorth.isFinite, mine.tradingResult.isFinite else { return }
        try? await online.publishLeaderboard(netWorth: mine.netWorth, tradingResult: mine.tradingResult, week: mine.week)
    }

    func submissions() async -> [LeaderboardSubmission] {
        guard let template, let rows = try? await online.leaderboardRows() else { return [] }
        return rows.map { (r: LeaderboardRow) -> LeaderboardSubmission in
            var s: LeaderboardSubmission = template
            s.playerID = r.playerID; s.name = r.name; s.week = r.week; s.netWorth = r.netWorth; s.tradingResult = r.tradingResult
            return s
        }
    }
}

// MARK: Accountant offices

/// One office as `list_accountant_offices` returns it. `rating` is nil until three clients have rated.
struct ServerAccountantOffice: Decodable, Equatable {
    var id: String
    var officeName: String
    var ownerName: String
    var city: String
    var countryCode: String
    var currency: String
    var hireFee: Double
    var isMine: Bool
    var rating: Double?
    var ratingCount: Int
    var hires: Int
    var activeClients: Int
}

extension SupabaseOnlineService {
    func accountantOfficeRows(countryCode: String) async throws -> [ServerAccountantOffice] {
        try decode([ServerAccountantOffice].self, try await rpcData("list_accountant_offices", ["p_country": countryCode]))
    }

    func hireAccountantOffice(officeID: String, companyKey: String, currency: String) async throws {
        _ = try await rpcData("hire_accountant_office", ["p_office": officeID, "p_company_key": companyKey, "p_currency": currency])
    }

    func rateAccountantHire(hireID: String, stars: Int) async throws {
        _ = try await rpcData("rate_accountant_hire", ["p_hire": hireID, "p_stars": stars])
    }
}

/// Offices other players run, over the server. The engine books the fee and the books' quality of an accountant on offer in the country, so
/// each office is billed as the engine accountant whose rating is nearest the office's own (3 while it has fewer than three ratings; the
/// cheaper one on a tie). The hiring fee itself moves through settlements on the server.
struct SupabaseAccountantOfficeService: AccountantOfficeService {
    let online: SupabaseOnlineService

    func offices(countryCode: String, offers: [AccountantOffer]) async -> [AccountantOffice] {
        guard !offers.isEmpty, let rows = try? await online.accountantOfficeRows(countryCode: countryCode) else { return [] }
        return rows.compactMap { (r: ServerAccountantOffice) -> AccountantOffice? in
            guard !r.isMine, let offer = Self.billedAs(rating: r.rating, in: offers) else { return nil }
            return AccountantOffice(id: r.id, officeName: r.officeName, ownerName: r.ownerName, city: r.city, offerID: offer.id,
                                    rating: r.rating, ratingCount: r.ratingCount, hireFee: r.hireFee, currencyCode: r.currency)
        }
    }

    func hire(officeID: String, companyKey: String, currency: String) async throws {
        try await online.hireAccountantOffice(officeID: officeID, companyKey: companyKey, currency: currency)
    }

    static func billedAs(rating: Double?, in offers: [AccountantOffer]) -> AccountantOffer? {
        let target: Double = rating ?? 3
        return offers.min { (a: AccountantOffer, b: AccountantOffer) -> Bool in
            let da: Double = abs(a.rating - target), db: Double = abs(b.rating - target)
            return da != db ? da < db : a.monthlyFee < b.monthlyFee
        }
    }
}

// MARK: World rules

/// `world_rules_read`: the administrator-set rules by key, and the exchange constants the server holds (the engine keeps the same ones in
/// `ExchangeRules`, so a client can tell when the two have drifted).
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
    /// The server's current rules; nil offline, as a guest, or when the call fails.
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

/// Where a snapshot goes once the engine can take one. The engine has no rules-snapshot protocol yet, so `apply` stays nil and a fetched
/// snapshot is only kept in `latest`; when the engine gets one, set `apply` once at start-up to hand the snapshot to it.
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
    /// The same service the session uses (one refresh token, one place that refreshes it); the offline stand-in has no rules to give.
    static var worldRules: any WorldRulesService { (shared as? SupabaseOnlineService) ?? OfflineWorldRulesService() }
}

extension LeaderboardBackend {
    static func online() -> any LeaderboardService {
        guard let service = OnlineBackend.shared as? SupabaseOnlineService else { return OfflineLeaderboardService() }
        return SupabaseLeaderboardService(online: service)
    }
}

enum AccountantOfficeBackend {
    static func make() -> any AccountantOfficeService {
        guard let service = OnlineBackend.shared as? SupabaseOnlineService else { return MockAccountantOfficeService() }
        return SupabaseAccountantOfficeService(online: service)
    }
}
