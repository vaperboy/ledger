import Foundation

protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

extension URLSession: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await self.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

actor SupabaseOnlineService: OnlineService {
    private let base: URL
    private let apiKey: String
    private let tokens: any IdentityTokenProvider
    private let transport: any HTTPTransport
    private let decoder: JSONDecoder = SupabaseWire.makeDecoder()

    init(baseURL: URL, apiKey: String, tokens: any IdentityTokenProvider, transport: any HTTPTransport = URLSession.shared) {
        self.base = baseURL; self.apiKey = apiKey; self.tokens = tokens; self.transport = transport
    }

    nonisolated var createsAccountsItself: Bool { true }

    func currentAccount() async -> OnlineAccount? { try? await startSession(createIfMissing: false) }

    func startSession(createIfMissing: Bool) async throws -> OnlineAccount {
        account(from: try await tokens.establish(createIfMissing: createIfMissing))
    }

    func signIn(with provider: SignInProvider) async throws -> OnlineAccount {
        account(from: try await tokens.link(provider))
    }

    private func account(from session: SupabaseSession) -> OnlineAccount {
        OnlineAccount(playerID: session.userID, provider: session.provider, createdAt: session.createdAt)
    }

    func accountStatus() async throws -> AccountStatus { try decode(AccountStatus.self, try await rpcData("account_status")) }

    func createProfile(adultConfirmed: Bool) async throws -> PlayerProfile {
        try await profileRPC("ensure_profile", ["p_adult_confirmed": adultConfirmed])
    }

    func claimLinkReward() async throws -> LinkRewardResult { try decode(LinkRewardResult.self, try await rpcData("claim_link_reward")) }

    func signOut() async {}

    func deleteAccount() async throws {
        _ = try await rpcData("delete_my_account")
        await tokens.discard()
    }

    func exportMyData() async throws -> Data { try await rpcData("export_my_data") }

    func myProfile() async throws -> PlayerProfile { try await profileRPC("view_profile", [:]) }

    func updateMyProfile(_ update: ProfileUpdate) async throws -> PlayerProfile {
        var fields: [String: Any] = [:]
        if let colour = update.avatarColour { fields["p_avatar_colour"] = max(0, min(PlayerProfile.avatarColourCount - 1, colour)) }
        if let country = update.countryCode { fields["p_country_code"] = country.uppercased() }
        if let privacy = update.privacy { fields["p_privacy"] = SupabaseWire.privacyWire(privacy) }
        if let icon = update.avatarIcon { fields["p_avatar_icon"] = icon }
        if !fields.isEmpty { _ = try await rpcData("update_my_profile", fields) }
        // The look goes in its own call, so a server that does not know it yet still saves the rest.
        if let look = update.avatarLook { _ = try? await rpcData("update_my_profile", ["p_avatar_look": look]) }
        if update.level != nil || update.badges != nil || update.gameWeek != nil || update.companies != nil {
            struct Args: Encodable {
                var p_level: Int?; var p_badges: [String]?; var p_game_week: Int?; var p_companies: [OnlineCompany]?
            }
            let args = Args(p_level: update.level, p_badges: update.badges, p_game_week: update.gameWeek, p_companies: update.companies)
            _ = try await raw(path: "/rest/v1/rpc/share_progress", method: "POST", body: try SupabaseWire.makeEncoder().encode(args))
        }
        return try await myProfile()
    }

    func usernameAvailable(_ name: String) async throws -> UsernameResult {
        guard ProfileRules.problem(with: name) == nil else { return .invalid }
        return try usernameResult(try await rpcData("username_available", ["p_username": ProfileRules.clean(name)]))
    }

    func claimUsername(_ name: String) async throws -> UsernameResult {
        guard ProfileRules.problem(with: name) == nil else { return .invalid }
        return try usernameResult(try await rpcData("claim_username", ["p_username": ProfileRules.clean(name)]))
    }

    private func usernameResult(_ data: Data) throws -> UsernameResult {
        let word: String = try JSONDecoder().decode(String.self, from: data)
        return UsernameResult(rawValue: word) ?? .invalid
    }

    func profile(id: String) async throws -> PlayerProfile { try await profileRPC("view_profile", ["p_id": id]) }
    func profile(code: String) async throws -> PlayerProfile { try await profileRPC("profile_by_code", ["p_code": code]) }

    func searchPlayers(query: String) async throws -> [PlayerProfile] {
        let data: Data = try await rpcData("search_players", ["p_query": query])
        return try decode([PlayerProfile].self, data)
    }

    func friends() async throws -> FriendsOverview { try decode(FriendsOverview.self, try await rpcData("my_friends")) }

    func sendFriendRequest(to playerID: String) async throws { _ = try await rpcData("send_friend_request", ["p_target": playerID]) }
    func acceptFriendRequest(from playerID: String) async throws { _ = try await rpcData("accept_friend_request", ["p_from": playerID]) }

    func declineFriendRequest(from playerID: String) async throws {
        try await deleteFriendship(requester: playerID, addressee: try await liveSession().userID, status: "pending")
    }

    func cancelFriendRequest(to playerID: String) async throws {
        try await deleteFriendship(requester: try await liveSession().userID, addressee: playerID, status: "pending")
    }

    func removeFriend(_ playerID: String) async throws {
        let me: String = try await liveSession().userID
        _ = try await raw(path: "/rest/v1/friendships", method: "DELETE",
                          query: [SupabaseWire.pairFilter(me, playerID), URLQueryItem(name: "status", value: "eq.accepted")], prefer: "return=minimal")
    }

    func blockPlayer(_ playerID: String) async throws {
        let me: String = try await liveSession().userID
        if me == playerID { throw OnlineError.cannotTargetYourself }
        _ = try await raw(path: "/rest/v1/blocks", method: "POST", body: try JSONSerialization.data(withJSONObject: ["blocker_id": me, "blocked_id": playerID]),
                          prefer: "resolution=ignore-duplicates,return=minimal")
    }

    func unblockPlayer(_ playerID: String) async throws {
        let me: String = try await liveSession().userID
        _ = try await raw(path: "/rest/v1/blocks", method: "DELETE",
                          query: [URLQueryItem(name: "blocker_id", value: "eq." + me), URLQueryItem(name: "blocked_id", value: "eq." + playerID)],
                          prefer: "return=minimal")
    }

    func blockedPlayers() async throws -> [PlayerProfile] { try decode([PlayerProfile].self, try await rpcData("blocked_players")) }

    func report(_ playerID: String, reason: ReportReason, note: String) async throws {
        let me: String = try await liveSession().userID
        if me == playerID { throw OnlineError.cannotTargetYourself }
        let body: [String: Any] = ["reporter_id": me, "target_id": playerID, "reason": reason.rawValue, "note": String(note.prefix(500))]
        _ = try await raw(path: "/rest/v1/reports", method: "POST", body: try JSONSerialization.data(withJSONObject: body), prefer: "return=minimal")
    }

    func heartbeat() async throws -> WorldPulse { try decode(WorldPulse.self, try await rpcData("heartbeat")) }

    func registerDevice(_ device: String) async throws { _ = try await rpcData("register_device", ["p_device": device]) }

    func friendActivity() async throws -> FriendActivity { try decode(FriendActivity.self, try await rpcData("friend_activity", ["p_limit": 40])) }

    func pendingSettlements() async throws -> [OnlineSettlementRow] { try decode([OnlineSettlementRow].self, try await rpcData("pending_settlements")) }

    func acknowledgeSettlements(_ ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        _ = try await rpcData("ack_settlements", ["p_ids": ids])
    }

    private func deleteFriendship(requester: String, addressee: String, status: String) async throws {
        _ = try await raw(path: "/rest/v1/friendships", method: "DELETE",
                          query: [URLQueryItem(name: "requester_id", value: "eq." + requester), URLQueryItem(name: "addressee_id", value: "eq." + addressee),
                                  URLQueryItem(name: "status", value: "eq." + status)], prefer: "return=minimal")
    }

    func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try decoder.decode(type, from: data) } catch { throw OnlineError.offline }
    }

    private func profileRPC(_ name: String, _ params: [String: Any]) async throws -> PlayerProfile {
        try decode(PlayerProfile.self, try await rpcData(name, params))
    }

    func rpcData(_ name: String, _ params: [String: Any] = [:]) async throws -> Data {
        try await raw(path: "/rest/v1/rpc/" + name, method: "POST", body: try JSONSerialization.data(withJSONObject: params))
    }

    // Calls one of the project's edge functions as the signed-in player.
    func functionData(_ name: String, _ params: [String: Any]) async throws -> Data {
        try await raw(path: "/functions/v1/" + name, method: "POST", body: try JSONSerialization.data(withJSONObject: params))
    }

    func signedInUserID() async -> String? { try? await liveSession().userID }

    // Reads rows the signed-in player may see from one table.
    func tableData(_ table: String, query: [URLQueryItem]) async throws -> Data {
        try await raw(path: "/rest/v1/" + table, method: "GET", query: query)
    }

    private func liveSession() async throws -> SupabaseSession { try await tokens.validSession() }

    private func raw(path: String, method: String, query: [URLQueryItem] = [], body: Data? = nil, prefer: String? = nil) async throws -> Data {
        let session: SupabaseSession = try await liveSession()
        var (data, status) = try await exchange(path: path, method: method, query: query, body: body, token: session.accessToken, prefer: prefer)
        if status == 401 {
            let fresh: SupabaseSession = try await tokens.renewed(rejected: session)
            (data, status) = try await exchange(path: path, method: method, query: query, body: body, token: fresh.accessToken, prefer: prefer)
        }
        guard (200..<300).contains(status) else { throw SupabaseWire.mapError(status: status, body: data) }
        return data
    }

    private func exchange(path: String, method: String, query: [URLQueryItem], body: Data?, token: String, prefer: String?) async throws -> (Data, Int) {
        let req: URLRequest = SupabaseWire.request(base: base, path: path, method: method, query: query, body: body, apiKey: apiKey,
                                                   accessToken: token, prefer: prefer)
        do { return try await transport.send(req) } catch { throw OnlineError.offline }
    }
}
