import Foundation
import Security

// The real online side: `OnlineService` over the Supabase Auth (GoTrue) and REST (PostgREST) HTTP APIs with URLSession only.
// Privacy is decided by the server's functions (see supabase/migrations); this file never filters what it receives, so a field the
// server hides stays nil. Nothing here runs unless `OnlineConfig.useServer` is true.

/// An identity token from Apple or Google and the raw nonce it was requested with, if any.
struct IdentityToken: Sendable {
    var token: String
    var nonce: String?
}

/// Obtains the provider's identity token through the system sign-in flow (Sign in with Apple, Google Sign-In).
protocol IdentityTokenProvider: Sendable {
    func identityToken(for provider: SignInProvider) async throws -> IdentityToken
}

/// Placeholder until the system sign-in flows are wired: always fails as "not signed in".
struct UnavailableIdentityTokenProvider: IdentityTokenProvider {
    func identityToken(for provider: SignInProvider) async throws -> IdentityToken { throw OnlineError.notSignedIn }
}

protocol SessionStore: Sendable {
    func load() -> SupabaseSession?
    func save(_ session: SupabaseSession)
    func clear()
}

/// Keeps the session in the Keychain, readable after the first unlock and never synced or backed up.
struct KeychainSessionStore: SessionStore {
    var service: String = "ledger.online.session"
    var account: String = "supabase"

    private var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func load() -> SupabaseSession? {
        var query: [String: Any] = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? SupabaseWire.makeDecoder().decode(SupabaseSession.self, from: data)
    }

    func save(_ session: SupabaseSession) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(session) else { return }
        let update: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(base as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add: [String: Any] = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    func clear() { SecItemDelete(base as CFDictionary) }
}

/// Network seam so the service can be driven without a network.
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
    private let store: any SessionStore
    private let transport: any HTTPTransport
    private let decoder: JSONDecoder = SupabaseWire.makeDecoder()
    private var refreshTask: Task<SupabaseSession, Error>?

    init(baseURL: URL, apiKey: String, tokens: any IdentityTokenProvider, store: any SessionStore = KeychainSessionStore(),
         transport: any HTTPTransport = URLSession.shared) {
        self.base = baseURL; self.apiKey = apiKey; self.tokens = tokens; self.store = store; self.transport = transport
    }

    // MARK: Account and session

    func currentAccount() async -> OnlineAccount? {
        guard var session = store.load(), !session.isAnonymous else { return nil }
        if session.needsRefresh() {
            do { session = try await refreshed(session) } catch OnlineError.notSignedIn { store.clear(); return nil } catch {}
        }
        return OnlineAccount(playerID: session.userID, provider: session.provider ?? .apple, createdAt: session.createdAt)
    }

    func signIn(with provider: SignInProvider) async throws -> OnlineAccount {
        let identity: IdentityToken = try await tokens.identityToken(for: provider)
        var body: [String: Any] = ["provider": provider.rawValue, "id_token": identity.token]
        if let nonce = identity.nonce { body["nonce"] = nonce }
        let data: Data = try await raw(path: "/auth/v1/token", method: "POST", query: [URLQueryItem(name: "grant_type", value: "id_token")],
                                       body: try JSONSerialization.data(withJSONObject: body), authorised: false)
        let session: SupabaseSession = try decoder.decode(SupabaseTokenResponse.self, from: data).session(fallbackProvider: provider)
        store.save(session)
        return OnlineAccount(playerID: session.userID, provider: session.provider ?? provider, createdAt: session.createdAt)
    }

    /// A guest session with no profile, for server features that need a user id but no account.
    func signInAnonymously() async throws {
        let data: Data = try await raw(path: "/auth/v1/signup", method: "POST", body: Data("{}".utf8), authorised: false)
        store.save(try decoder.decode(SupabaseTokenResponse.self, from: data).session())
    }

    func linkAccount(with provider: SignInProvider) async throws -> OnlineAccount { try await signIn(with: provider) }

    func accountStatus() async throws -> AccountStatus { try decode(AccountStatus.self, try await rpcData("account_status")) }

    /// The server makes the profile only when the confirmation is a yes (anything else is refused there as `adult_required`).
    func createProfile(adultConfirmed: Bool) async throws -> PlayerProfile {
        try await profileRPC("ensure_profile", ["p_adult_confirmed": adultConfirmed])
    }

    func claimLinkReward() async throws -> LinkRewardResult { try decode(LinkRewardResult.self, try await rpcData("claim_link_reward")) }

    func signOut() async {
        _ = try? await raw(path: "/auth/v1/logout", method: "POST")
        store.clear()
    }

    func deleteAccount() async throws {
        _ = try await rpcData("delete_my_account")
        store.clear()
    }

    func exportMyData() async throws -> Data { try await rpcData("export_my_data") }

    // MARK: Profiles

    func myProfile() async throws -> PlayerProfile { try await profileRPC("view_profile", [:]) }

    func updateMyProfile(_ update: ProfileUpdate) async throws -> PlayerProfile {
        var fields: [String: Any] = [:]   // update_my_profile reads a missing key as "leave as is"
        if let name = update.displayName {
            if let why = ProfileRules.problem(with: name) { throw OnlineError.nameRejected(why) }
            fields["p_display_name"] = ProfileRules.clean(name)
        }
        if let colour = update.avatarColour { fields["p_avatar_colour"] = max(0, min(PlayerProfile.avatarColourCount - 1, colour)) }
        if let country = update.countryCode { fields["p_country_code"] = country.uppercased() }
        if let privacy = update.privacy { fields["p_privacy"] = SupabaseWire.privacyWire(privacy) }
        if let icon = update.avatarIcon { fields["p_avatar_icon"] = icon }
        if !fields.isEmpty { _ = try await rpcData("update_my_profile", fields) }
        if update.level != nil || update.badges != nil || update.gameWeek != nil || update.companies != nil {
            struct Args: Encodable {   // nil members are omitted, which the function reads as "leave as is"
                var p_level: Int?; var p_badges: [String]?; var p_game_week: Int?; var p_companies: [OnlineCompany]?
            }
            let args = Args(p_level: update.level, p_badges: update.badges, p_game_week: update.gameWeek, p_companies: update.companies)
            _ = try await raw(path: "/rest/v1/rpc/share_progress", method: "POST", body: try SupabaseWire.makeEncoder().encode(args))
        }
        return try await myProfile()
    }

    func profile(id: String) async throws -> PlayerProfile { try await profileRPC("view_profile", ["p_id": id]) }
    func profile(code: String) async throws -> PlayerProfile { try await profileRPC("profile_by_code", ["p_code": code]) }

    func searchPlayers(query: String) async throws -> [PlayerProfile] {
        let data: Data = try await rpcData("search_players", ["p_query": query])
        return try decode([PlayerProfile].self, data)
    }

    // MARK: Friends

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

    // MARK: Plumbing

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

    /// The stored session, refreshed when it is about to expire. Throws `.notSignedIn` without one or for a guest.
    private func liveSession() async throws -> SupabaseSession {
        guard let session = store.load(), !session.isAnonymous else { throw OnlineError.notSignedIn }
        return session.needsRefresh() ? try await refreshed(session) : session
    }

    /// One refresh at a time: refresh tokens rotate, so a second concurrent refresh would fail.
    private func refreshed(_ old: SupabaseSession) async throws -> SupabaseSession {
        if let task = refreshTask { return try await task.value }
        let task = Task { () throws -> SupabaseSession in
            let body: Data = try JSONSerialization.data(withJSONObject: ["refresh_token": old.refreshToken])
            let data: Data = try await self.send(path: "/auth/v1/token", method: "POST",
                                                 query: [URLQueryItem(name: "grant_type", value: "refresh_token")], body: body, token: nil, prefer: nil)
            var fresh: SupabaseSession = try self.decoder.decode(SupabaseTokenResponse.self, from: data).session(fallbackProvider: old.provider)
            if fresh.provider == nil { fresh.provider = old.provider }
            self.store.save(fresh)
            return fresh
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    /// A request with the user's token (refreshed first), retried once after a 401 with a fresh token.
    private func raw(path: String, method: String, query: [URLQueryItem] = [], body: Data? = nil, prefer: String? = nil,
                     authorised: Bool = true) async throws -> Data {
        guard authorised else { return try await send(path: path, method: method, query: query, body: body, token: nil, prefer: prefer) }
        let session: SupabaseSession = try await liveSession()
        do {
            return try await send(path: path, method: method, query: query, body: body, token: session.accessToken, prefer: prefer)
        } catch OnlineError.notSignedIn {
            let fresh: SupabaseSession = try await refreshed(session)
            return try await send(path: path, method: method, query: query, body: body, token: fresh.accessToken, prefer: prefer)
        }
    }

    private func send(path: String, method: String, query: [URLQueryItem], body: Data?, token: String?, prefer: String?) async throws -> Data {
        let req: URLRequest = SupabaseWire.request(base: base, path: path, method: method, query: query, body: body, apiKey: apiKey,
                                                   accessToken: token, prefer: prefer)
        let data: Data, status: Int
        do { (data, status) = try await transport.send(req) } catch { throw OnlineError.offline }
        guard (200..<300).contains(status) else { throw SupabaseWire.mapError(status: status, body: data) }
        return data
    }
}
