import XCTest
@testable import Ledger

final class MemorySessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var held: SupabaseSession?

    init(_ session: SupabaseSession? = nil) { held = session }

    func load() -> SupabaseSession? { lock.withLock { held } }
    func save(_ session: SupabaseSession) { lock.withLock { held = session } }
    func clear() { lock.withLock { held = nil } }
}

final class FakeTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Data, Int)
    private let lock = NSLock()
    private var log: [URLRequest] = []
    private let handler: Handler
    private let delay: UInt64

    init(delayMilliseconds: UInt64 = 0, _ handler: @escaping Handler) {
        self.handler = handler
        self.delay = delayMilliseconds * 1_000_000
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        lock.withLock { log.append(request) }
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
        return try handler(request)
    }

    var requests: [URLRequest] { lock.withLock { log } }
    var paths: [String] { requests.map { $0.url?.path ?? "" } }
}

struct FakeAuthenticator: WebAuthenticator {
    var result: Result<URL, OnlineError>
    func authenticate(url: URL, callbackScheme: String) async throws -> URL { try result.get() }
}

enum AuthFixtures {
    static let base = URL(string: "https://example.supabase.co")!

    static func token(access: String, refresh: String, user: String = "u1", expiresAt: Double = Date().timeIntervalSince1970 + 3600,
                      provider: String = "anonymous", identities: [String] = []) -> Data {
        let body: [String: Any] = [
            "access_token": access, "refresh_token": refresh, "expires_in": 3600, "expires_at": expiresAt,
            "user": ["id": user, "created_at": "2026-11-10T09:30:00.123456+00:00", "is_anonymous": identities.isEmpty,
                     "app_metadata": ["provider": provider, "providers": [provider] + identities],
                     "identities": identities.map { ["provider": $0] }],
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    static func session(access: String = "old", refresh: String = "r1", expiresIn: TimeInterval = 3600, provider: SignInProvider? = nil) -> SupabaseSession {
        SupabaseSession(accessToken: access, refreshToken: refresh, expiresAt: Date().addingTimeInterval(expiresIn), userID: "u1", createdAt: Date(), provider: provider)
    }

    static func provider(store: any SessionStore, transport: any HTTPTransport, authenticator: any WebAuthenticator = FakeAuthenticator(result: .failure(.cancelled))) -> SupabaseIdentityProvider {
        SupabaseIdentityProvider(baseURL: base, apiKey: "key", store: store, transport: transport, authenticator: authenticator)
    }

    static func json(_ text: String) -> Data { Data(text.utf8) }

    static let profileJSON = #"{"id":"u1","code":"K7M-4PQ2","displayName":"Player AB12","avatarColour":3,"countryCode":"GB","level":null,"badges":[],"privacy":"everyone","companyCount":null,"companies":null,"gameWeek":null,"tradesCompleted":null,"relation":"you"}"#
}

final class SupabaseAuthTests: XCTestCase {
    func testAnonymousSignUpResponseParses() throws {
        let response = try SupabaseWire.makeDecoder().decode(SupabaseTokenResponse.self, from: AuthFixtures.token(access: "a", refresh: "r", user: "anon-1", expiresAt: 2_000_000_000))
        let session = response.session()
        XCTAssertEqual(session.userID, "anon-1")
        XCTAssertEqual(session.accessToken, "a")
        XCTAssertEqual(session.refreshToken, "r")
        XCTAssertEqual(session.expiresAt, Date(timeIntervalSince1970: 2_000_000_000))
        XCTAssertNil(session.provider)
    }

    func testLinkedIdentityShowsThroughAnonymousProviderName() throws {
        let data = AuthFixtures.token(access: "a", refresh: "r", provider: "anonymous", identities: ["google"])
        let session = try SupabaseWire.makeDecoder().decode(SupabaseTokenResponse.self, from: data).session()
        XCTAssertEqual(session.provider, .google)
    }

    func testExpiresInIsUsedWhenThereIsNoExpiryDate() throws {
        let json = #"{"access_token":"a","refresh_token":"r","expires_in":600,"user":{"id":"u"}}"#
        let now = Date(timeIntervalSince1970: 1_000)
        let session = try SupabaseWire.makeDecoder().decode(SupabaseTokenResponse.self, from: AuthFixtures.json(json)).session(now: now)
        XCTAssertEqual(session.expiresAt, now.addingTimeInterval(600))
    }

    func testFirstLaunchCreatesAnAnonymousAccountOnce() async throws {
        let store = MemorySessionStore()
        let transport = FakeTransport { _ in (AuthFixtures.token(access: "a1", refresh: "r1", user: "anon-1"), 200) }
        let provider = AuthFixtures.provider(store: store, transport: transport)
        let first = try await provider.establish(createIfMissing: true)
        let second = try await provider.establish(createIfMissing: true)
        XCTAssertEqual(first.userID, "anon-1")
        XCTAssertEqual(second, first)
        XCTAssertEqual(store.load(), first)
        XCTAssertEqual(transport.paths, ["/auth/v1/signup"])
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "key")
        XCTAssertEqual(request.httpBody, Data("{}".utf8))
        let id = await provider.currentUserID()
        XCTAssertEqual(id, "anon-1")
    }

    func testNothingIsCreatedWhenCreationIsNotAllowed() async {
        let transport = FakeTransport { _ in XCTFail("no request expected"); return (Data(), 500) }
        let provider = AuthFixtures.provider(store: MemorySessionStore(), transport: transport)
        do {
            _ = try await provider.establish(createIfMissing: false)
            XCTFail("expected notSignedIn")
        } catch {
            XCTAssertEqual(error as? OnlineError, .notSignedIn)
        }
    }

    func testSignUpOffline() async {
        let store = MemorySessionStore()
        let transport = FakeTransport { _ in throw URLError(.notConnectedToInternet) }
        let provider = AuthFixtures.provider(store: store, transport: transport)
        do {
            _ = try await provider.establish(createIfMissing: true)
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? OnlineError, .offline)
        }
        XCTAssertNil(store.load())
    }

    func testAnExpiringSessionIsRefreshedBeforeUse() async throws {
        let store = MemorySessionStore(AuthFixtures.session(expiresIn: 30, provider: .google))
        let transport = FakeTransport { _ in (AuthFixtures.token(access: "new", refresh: "r2"), 200) }
        let provider = AuthFixtures.provider(store: store, transport: transport)
        let session = try await provider.validSession()
        XCTAssertEqual(session.accessToken, "new")
        XCTAssertEqual(session.provider, .google)
        XCTAssertEqual(store.load()?.refreshToken, "r2")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/auth/v1/token")
        XCTAssertEqual(request.url?.query, "grant_type=refresh_token")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: body) as? [String: String])?["refresh_token"], "r1")
    }

    func testAFreshSessionIsReusedWithoutTheNetwork() async throws {
        let store = MemorySessionStore(AuthFixtures.session())
        let transport = FakeTransport { _ in XCTFail("no request expected"); return (Data(), 500) }
        let session = try await AuthFixtures.provider(store: store, transport: transport).validSession()
        XCTAssertEqual(session.accessToken, "old")
    }

    func testConcurrentCallsShareOneRefresh() async throws {
        let store = MemorySessionStore(AuthFixtures.session(expiresIn: -10))
        let transport = FakeTransport(delayMilliseconds: 80) { _ in (AuthFixtures.token(access: "new", refresh: "r2"), 200) }
        let provider = AuthFixtures.provider(store: store, transport: transport)
        async let a = provider.validSession()
        async let b = provider.validSession()
        async let c = provider.validSession()
        let results = try await [a, b, c]
        XCTAssertEqual(results.map { $0.accessToken }, ["new", "new", "new"])
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testADeadRefreshTokenClearsTheSessionAndAsksForSignIn() async {
        let store = MemorySessionStore(AuthFixtures.session(expiresIn: -10))
        let transport = FakeTransport { _ in (AuthFixtures.json(#"{"code":400,"error_code":"refresh_token_not_found","msg":"Invalid Refresh Token: Refresh Token Not Found"}"#), 400) }
        do {
            _ = try await AuthFixtures.provider(store: store, transport: transport).validSession()
            XCTFail("expected notSignedIn")
        } catch {
            XCTAssertEqual(error as? OnlineError, .notSignedIn)
        }
        XCTAssertNil(store.load())
    }

    func testRefreshOfflineKeepsTheSession() async {
        let store = MemorySessionStore(AuthFixtures.session(expiresIn: -10))
        let transport = FakeTransport { _ in throw URLError(.timedOut) }
        do {
            _ = try await AuthFixtures.provider(store: store, transport: transport).validSession()
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? OnlineError, .offline)
        }
        XCTAssertNotNil(store.load())
    }

    func testEstablishStartsOverAfterADeadRefreshToken() async throws {
        let store = MemorySessionStore(AuthFixtures.session(expiresIn: -10))
        let transport = FakeTransport { request in
            if request.url?.path == "/auth/v1/signup" { return (AuthFixtures.token(access: "a2", refresh: "r9", user: "anon-2"), 200) }
            return (AuthFixtures.json(#"{"error":"invalid_grant","error_description":"Invalid Refresh Token: Already Used"}"#), 400)
        }
        let session = try await AuthFixtures.provider(store: store, transport: transport).establish(createIfMissing: true)
        XCTAssertEqual(session.userID, "anon-2")
        XCTAssertEqual(transport.paths, ["/auth/v1/token", "/auth/v1/signup"])
    }

    func testARejectedTokenIsRenewedOnceAndTheCallRetried() async throws {
        let store = MemorySessionStore(AuthFixtures.session())
        let transport = FakeTransport { request in
            switch request.url?.path {
            case "/auth/v1/token":
                return (AuthFixtures.token(access: "new", refresh: "r2"), 200)
            default:
                if request.value(forHTTPHeaderField: "Authorization") == "Bearer old" {
                    return (AuthFixtures.json(#"{"code":"PGRST301","message":"JWT expired"}"#), 401)
                }
                return (AuthFixtures.json(#"{"hasProfile":true,"adultConfirmed":true,"isAdmin":false,"linkRewardGold":100,"linkRewardClaimed":false}"#), 200)
            }
        }
        let service = SupabaseOnlineService(baseURL: AuthFixtures.base, apiKey: "key", tokens: AuthFixtures.provider(store: store, transport: transport), transport: transport)
        let status = try await service.accountStatus()
        XCTAssertTrue(status.adultConfirmed)
        XCTAssertEqual(transport.paths, ["/rest/v1/rpc/account_status", "/auth/v1/token", "/rest/v1/rpc/account_status"])
        XCTAssertEqual(transport.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer new")
        XCTAssertEqual(store.load()?.refreshToken, "r2")
    }

    func testServiceCallsBeforeAnyAccountAskForSignIn() async {
        let transport = FakeTransport { _ in XCTFail("no request expected"); return (Data(), 500) }
        let service = SupabaseOnlineService(baseURL: AuthFixtures.base, apiKey: "key", tokens: AuthFixtures.provider(store: MemorySessionStore(), transport: transport), transport: transport)
        do {
            _ = try await service.heartbeat()
            XCTFail("expected notSignedIn")
        } catch {
            XCTAssertEqual(error as? OnlineError, .notSignedIn)
        }
        let account = await service.currentAccount()
        XCTAssertNil(account)
    }

    func testPKCEMatchesTheRFCExample() {
        XCTAssertEqual(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let made = PKCE.make()
        XCTAssertEqual(made.verifier.count, 64)
        XCTAssertFalse(made.verifier.contains("="))
        XCTAssertFalse(made.challenge.contains("+") || made.challenge.contains("/") || made.challenge.contains("="))
        XCTAssertNotEqual(PKCE.make(), made)
    }

    func testLinkingGoogleRunsTheAuthorizeAndExchangeSteps() async throws {
        let store = MemorySessionStore(AuthFixtures.session())
        let transport = FakeTransport { request in
            switch request.url?.path {
            case "/auth/v1/user/identities/authorize": return (AuthFixtures.json(#"{"url":"https://accounts.example.com/o/oauth2/auth?x=1"}"#), 200)
            default: return (AuthFixtures.token(access: "linked", refresh: "r3", provider: "anonymous", identities: ["google"]), 200)
            }
        }
        let authenticator = FakeAuthenticator(result: .success(URL(string: "ledger://auth-callback?code=abc123")!))
        let provider = AuthFixtures.provider(store: store, transport: transport, authenticator: authenticator)
        let session = try await provider.link(.google)
        XCTAssertEqual(session.provider, .google)
        XCTAssertEqual(store.load()?.accessToken, "linked")
        let authorize = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(authorize.httpMethod, "GET")
        XCTAssertEqual(authorize.value(forHTTPHeaderField: "Authorization"), "Bearer old")
        let items = URLComponents(url: try XCTUnwrap(authorize.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }
        XCTAssertEqual(value("provider"), "google")
        XCTAssertEqual(value("redirect_to"), "ledger://auth-callback")
        XCTAssertEqual(value("code_challenge_method"), "s256")
        XCTAssertEqual(value("skip_http_redirect"), "true")
        let exchange = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(exchange.url?.query, "grant_type=pkce")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: try XCTUnwrap(exchange.httpBody)) as? [String: String])
        XCTAssertEqual(body["auth_code"], "abc123")
        XCTAssertEqual(PKCE.challenge(for: try XCTUnwrap(body["code_verifier"])), value("code_challenge"))
    }

    func testAProviderThatIsNotSetUpGivesAFriendlyMessage() async {
        let store = MemorySessionStore(AuthFixtures.session())
        let transport = FakeTransport { _ in (AuthFixtures.json(#"{"code":400,"error_code":"validation_failed","msg":"Unsupported provider: provider is not enabled"}"#), 400) }
        do {
            _ = try await AuthFixtures.provider(store: store, transport: transport).link(.google)
            XCTFail("expected a rejection")
        } catch {
            XCTAssertEqual(error as? OnlineError, .rejected("Google linking is not set up on the server yet. Try again later."))
        }
        XCTAssertEqual(store.load()?.accessToken, "old")
    }

    func testCancellingTheBrowserLeavesTheAccountAsItWas() async {
        let store = MemorySessionStore(AuthFixtures.session())
        let transport = FakeTransport { _ in (AuthFixtures.json(#"{"url":"https://accounts.example.com/auth"}"#), 200) }
        let provider = AuthFixtures.provider(store: store, transport: transport, authenticator: FakeAuthenticator(result: .failure(.cancelled)))
        do {
            _ = try await provider.link(.google)
            XCTFail("expected cancelled")
        } catch {
            XCTAssertEqual(error as? OnlineError, .cancelled)
        }
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(store.load()?.accessToken, "old")
    }

    func testCallbackParsing() throws {
        XCTAssertEqual(try SupabaseWire.authorizationCode(from: URL(string: "ledger://auth-callback?code=xyz")!, provider: .google), "xyz")
        func failure(_ url: String) -> OnlineError? {
            do { _ = try SupabaseWire.authorizationCode(from: URL(string: url)!, provider: .google); return nil } catch { return error as? OnlineError }
        }
        XCTAssertEqual(failure("ledger://auth-callback?error=access_denied&error_description=User+denied"), .cancelled)
        XCTAssertEqual(failure("ledger://auth-callback#error=server_error&error_code=identity_already_exists&error_description=Identity+is+already+linked"),
                       .rejected("That Google account is already linked to another player."))
        XCTAssertEqual(failure("ledger://auth-callback?error=server_error&error_code=manual_linking_disabled"),
                       .rejected("Linking accounts is not switched on for the server yet."))
        XCTAssertEqual(failure("ledger://auth-callback"), .rejected("Linking did not finish. Try again."))
    }

    func testInvalidGrantMeansSignInAgain() {
        XCTAssertEqual(SupabaseWire.mapError(status: 400, body: AuthFixtures.json(#"{"error":"invalid_grant","error_description":"Invalid Refresh Token"}"#)), .notSignedIn)
    }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var on = false
    var value: Bool { lock.withLock { on } }
    func raise() { lock.withLock { on = true } }
    func lower() { lock.withLock { on = false } }
}

@MainActor
final class AutomaticAccountTests: XCTestCase {
    private func routes(_ made: Flag) -> FakeTransport.Handler {
        { request in
            switch request.url?.path {
            case "/auth/v1/signup":
                return (AuthFixtures.token(access: "a1", refresh: "r1", user: "anon-1"), 200)
            case "/auth/v1/user/identities/authorize":
                return (AuthFixtures.json(#"{"url":"https://accounts.example.com/auth"}"#), 200)
            case "/auth/v1/token":
                return (AuthFixtures.token(access: "a2", refresh: "r2", user: "anon-1", provider: "anonymous", identities: ["google"]), 200)
            case "/rest/v1/rpc/account_status":
                let has = made.value
                return (AuthFixtures.json(#"{"hasProfile":\#(has),"adultConfirmed":\#(has),"isAdmin":false,"linkRewardGold":100,"linkRewardClaimed":false}"#), 200)
            case "/rest/v1/rpc/ensure_profile":
                made.raise()
                return (AuthFixtures.json(AuthFixtures.profileJSON), 200)
            case "/rest/v1/rpc/view_profile":
                return (AuthFixtures.json(AuthFixtures.profileJSON), 200)
            case "/rest/v1/rpc/claim_link_reward":
                return (AuthFixtures.json(#"{"granted":true,"gold":100,"reason":"granted"}"#), 200)
            default:
                return (Data(), 404)
            }
        }
    }

    private func makeOnline(_ transport: FakeTransport, store: MemorySessionStore = MemorySessionStore(),
                        authenticator: FakeAuthenticator = FakeAuthenticator(result: .failure(.cancelled))) -> OnlineSession {
        let before = Terms.accepted
        UserDefaults.standard.set(true, forKey: Terms.key)
        addTeardownBlock { UserDefaults.standard.set(before, forKey: Terms.key) }
        let tokens = AuthFixtures.provider(store: store, transport: transport, authenticator: authenticator)
        return OnlineSession(service: SupabaseOnlineService(baseURL: AuthFixtures.base, apiKey: "key", tokens: tokens, transport: transport))
    }

    private func waitUntil(_ seconds: Double = 10, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(seconds)
        while !condition() && Date() < end { try? await Task.sleep(nanoseconds: 100_000_000) }
    }

    func testFirstLaunchSignsInAnonymouslyAndCreatesTheProfileWithoutARewardClaim() async {
        let transport = FakeTransport(routes(Flag()))
        let online = makeOnline(transport)
        await online.start()
        await waitUntil { online.profile != nil }
        XCTAssertTrue(online.isSignedIn)
        XCTAssertFalse(online.isLinked)
        XCTAssertTrue(online.canLink)
        XCTAssertFalse(online.offline)
        XCTAssertEqual(online.accountID, "anon-1")
        XCTAssertEqual(online.profile?.displayName, "Player AB12")
        XCTAssertFalse(transport.paths.contains("/rest/v1/rpc/claim_link_reward"))
        XCTAssertEqual(transport.paths.first, "/auth/v1/signup")
    }

    func testLinkingGoogleKeepsTheAccountAndPaysTheRewardOnce() async {
        let transport = FakeTransport(routes(Flag()))
        let online = makeOnline(transport, authenticator: FakeAuthenticator(result: .success(URL(string: "ledger://auth-callback?code=abc")!)))
        await online.start()
        await waitUntil { online.profile != nil }
        let ok = await online.signIn(with: .google)
        XCTAssertTrue(ok)
        XCTAssertEqual(online.provider, .google)
        XCTAssertEqual(online.accountID, "anon-1")
        XCTAssertEqual(online.linkReward?.gold, 100)
        XCTAssertFalse(online.canLink)
        XCTAssertEqual(transport.paths.filter { $0 == "/rest/v1/rpc/claim_link_reward" }.count, 1)
    }

    func testCancellingTheLinkShowsNoProblem() async {
        let online = makeOnline(FakeTransport(routes(Flag())))
        await online.start()
        await waitUntil { online.profile != nil }
        let ok = await online.signIn(with: .google)
        XCTAssertFalse(ok)
        XCTAssertNil(online.problem)
        XCTAssertTrue(online.isSignedIn)
        XCTAssertTrue(online.canLink)
    }

    func testAnUnreachableServerLeavesTheGuestStateAndNoCrash() async {
        let online = makeOnline(FakeTransport { _ in throw URLError(.notConnectedToInternet) })
        await online.start()
        await waitUntil { online.offline }
        XCTAssertTrue(online.offline)
        XCTAssertFalse(online.isSignedIn)
        XCTAssertFalse(online.canLink)
    }

    func testTheServerReturningLaterConnectsByItself() async {
        let down = Flag()
        down.raise()
        let live = routes(Flag())
        let online = makeOnline(FakeTransport { request in
            if down.value { throw URLError(.notConnectedToInternet) }
            return try live(request)
        })
        await online.start()
        await waitUntil { online.offline }
        XCTAssertTrue(online.offline)
        down.lower()
        await waitUntil(15) { online.profile != nil }
        XCTAssertTrue(online.isSignedIn)
        XCTAssertFalse(online.offline)
    }

    func testSigningOutKeepsTheServerAccountAndStopsReconnecting() async {
        let store = MemorySessionStore()
        let online = makeOnline(FakeTransport(routes(Flag())), store: store)
        await online.start()
        await waitUntil { online.profile != nil }
        await online.signOut()
        XCTAssertFalse(online.isSignedIn)
        XCTAssertTrue(online.pausedByPlayer)
        XCTAssertNotNil(store.load())
        online.resume()
        await waitUntil { online.isSignedIn }
        XCTAssertTrue(online.isSignedIn)
        XCTAssertEqual(online.accountID, "anon-1")
    }

    func testTheStandInServiceStaysAGuestUntilALinkAndOffersBothProviders() async {
        let mock = MockOnlineService(suiteName: "test.accounts." + UUID().uuidString, key: "k", latencyMilliseconds: 0)
        let online = OnlineSession(service: mock)
        await online.start()
        XCTAssertFalse(online.isSignedIn)
        XCTAssertTrue(online.canLink)
        XCTAssertFalse(OnlineConfig.serverLinkProviders.contains(.apple))
    }
}
