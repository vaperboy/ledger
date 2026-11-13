import Foundation
import Security
import CryptoKit
import UIKit
import AuthenticationServices

protocol SessionStore: Sendable {
    func load() -> SupabaseSession?
    func save(_ session: SupabaseSession)
    func clear()
}

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

struct PKCE: Equatable, Sendable {
    var verifier: String

    var challenge: String { Self.challenge(for: verifier) }

    static func make() -> PKCE {
        PKCE(verifier: base64URL(Data((0..<48).map { _ in UInt8.random(in: .min ... .max) })))
    }

    static func challenge(for verifier: String) -> String { base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

protocol WebAuthenticator: Sendable {
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

struct SystemWebAuthenticator: WebAuthenticator {
    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await WebSessionRunner().run(url: url, callbackScheme: callbackScheme)
    }
}

@MainActor
private final class WebSessionRunner: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func run(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            var finished = false
            func finish(_ result: Result<URL, Error>) {
                guard !finished else { return }
                finished = true
                continuation.resume(with: result)
            }
            let web = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { (callback: URL?, error: Error?) in
                if let callback { finish(.success(callback)); return }
                let cancelled: Bool = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                finish(.failure(cancelled ? OnlineError.cancelled : OnlineError.offline))
            }
            web.presentationContextProvider = self
            session = web
            if !web.start() { finish(.failure(OnlineError.offline)) }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let windows: [UIWindow] = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
            return windows.first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
        }
    }
}

protocol IdentityTokenProvider: Sendable {
    func currentUserID() async -> String?
    func establish(createIfMissing: Bool) async throws -> SupabaseSession
    func validSession() async throws -> SupabaseSession
    func renewed(rejected: SupabaseSession) async throws -> SupabaseSession
    func link(_ provider: SignInProvider) async throws -> SupabaseSession
    func linkApple(idToken: String, nonce: String) async throws -> SupabaseSession
    func signInExisting(_ request: SignInRequest) async throws -> SupabaseSession
    func adopt(_ session: SupabaseSession) async
    func release(_ session: SupabaseSession) async
    func enabledProviders() async -> [SignInProvider]?
    func discard() async
}

actor SupabaseIdentityProvider: IdentityTokenProvider {
    private let base: URL
    private let apiKey: String
    private let store: any SessionStore
    private let transport: any HTTPTransport
    private let authenticator: any WebAuthenticator
    private let clock: @Sendable () -> Date
    private let decoder: JSONDecoder = SupabaseWire.makeDecoder()
    private var inFlight: Task<SupabaseSession, Error>?

    init(baseURL: URL, apiKey: String, store: any SessionStore = KeychainSessionStore(), transport: any HTTPTransport = URLSession.shared,
         authenticator: any WebAuthenticator = SystemWebAuthenticator(), clock: @escaping @Sendable () -> Date = { Date() }) {
        self.base = baseURL; self.apiKey = apiKey; self.store = store; self.transport = transport
        self.authenticator = authenticator; self.clock = clock
    }

    func currentUserID() async -> String? { store.load()?.userID }

    func establish(createIfMissing: Bool) async throws -> SupabaseSession {
        if store.load() != nil {
            do { return try await validSession() } catch OnlineError.notSignedIn {}
        }
        guard createIfMissing else { throw OnlineError.notSignedIn }
        return try await shared { (me: SupabaseIdentityProvider) -> SupabaseSession in try await me.signUpAnonymously() }
    }

    func validSession() async throws -> SupabaseSession {
        guard let session = store.load() else { throw OnlineError.notSignedIn }
        return session.needsRefresh(now: clock()) ? try await refresh(session) : session
    }

    func renewed(rejected: SupabaseSession) async throws -> SupabaseSession {
        if let current = store.load(), current.accessToken != rejected.accessToken, !current.needsRefresh(now: clock()) { return current }
        return try await refresh(rejected)
    }

    func discard() async { store.clear() }

    // Apple's token is attached to the current account, which keeps its id and stops being anonymous.
    func linkApple(idToken: String, nonce: String) async throws -> SupabaseSession {
        let current: SupabaseSession = try await validSession()
        let linked: SupabaseSession = try await idTokenGrant(idToken: idToken, nonce: nonce, linkingTo: current)
        store.save(linked)
        return linked
    }

    // Signs in to the account that already owns this sign-in. The session is returned, not kept, until the player decides to switch.
    func signInExisting(_ request: SignInRequest) async throws -> SupabaseSession {
        switch request {
        case .apple(let idToken, let nonce):
            return try await idTokenGrant(idToken: idToken, nonce: nonce, linkingTo: nil)
        case .google:
            let pkce: PKCE = .make()
            let query: [URLQueryItem] = [
                URLQueryItem(name: "provider", value: SignInProvider.google.rawValue),
                URLQueryItem(name: "redirect_to", value: OnlineConfig.callbackURL),
                URLQueryItem(name: "code_challenge", value: pkce.challenge),
                URLQueryItem(name: "code_challenge_method", value: "s256"),
            ]
            var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
            comps.path = (comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path) + "/auth/v1/authorize"
            comps.queryItems = query
            guard let url = comps.url else { throw OnlineError.offline }
            let callback: URL = try await authenticator.authenticate(url: url, callbackScheme: OnlineConfig.callbackScheme)
            let code: String = try SupabaseWire.authorizationCode(from: callback, provider: .google)
            return try await exchangeCode(code, verifier: pkce.verifier, provider: .google)
        }
    }

    func adopt(_ session: SupabaseSession) async { store.save(session) }

    // Ends a session that was opened for a switch the player turned down.
    func release(_ session: SupabaseSession) async {
        let request: URLRequest = SupabaseWire.request(base: base, path: "/auth/v1/logout", method: "POST", query: [URLQueryItem(name: "scope", value: "local")],
                                                       apiKey: apiKey, accessToken: session.accessToken)
        _ = try? await perform(request)
    }

    // The sign-in providers switched on for this project, or nil when the server cannot be asked.
    func enabledProviders() async -> [SignInProvider]? {
        let request: URLRequest = SupabaseWire.request(base: base, path: "/auth/v1/settings", apiKey: apiKey)
        guard let (data, status) = try? await perform(request), (200..<300).contains(status),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let external = json["external"] as? [String: Any] else { return nil }
        return SignInProvider.allCases.filter { (p: SignInProvider) -> Bool in (external[p.rawValue] as? Bool) == true }
    }

    private func idTokenGrant(idToken: String, nonce: String, linkingTo current: SupabaseSession?) async throws -> SupabaseSession {
        var fields: [String: Any] = ["provider": SignInProvider.apple.rawValue, "id_token": idToken, "nonce": nonce]
        if current != nil { fields["link_identity"] = true }
        let request: URLRequest = SupabaseWire.request(base: base, path: "/auth/v1/token", method: "POST", query: [URLQueryItem(name: "grant_type", value: "id_token")],
                                                       body: try JSONSerialization.data(withJSONObject: fields), apiKey: apiKey, accessToken: current?.accessToken)
        let (data, status) = try await perform(request)
        guard (200..<300).contains(status) else { throw linkError(status: status, body: data, provider: .apple) }
        return try parse(data, fallback: .apple)
    }

    private func exchangeCode(_ code: String, verifier: String, provider: SignInProvider) async throws -> SupabaseSession {
        let body: Data = try JSONSerialization.data(withJSONObject: ["auth_code": code, "code_verifier": verifier])
        let exchange: URLRequest = SupabaseWire.request(base: base, path: "/auth/v1/token", method: "POST", query: [URLQueryItem(name: "grant_type", value: "pkce")],
                                                        body: body, apiKey: apiKey)
        let (reply, replyStatus) = try await perform(exchange)
        guard (200..<300).contains(replyStatus) else { throw linkError(status: replyStatus, body: reply, provider: provider) }
        return try parse(reply, fallback: provider)
    }

    func link(_ provider: SignInProvider) async throws -> SupabaseSession {
        guard provider == .google else { throw OnlineError.rejected("Use the Sign in with Apple button.") }
        let current: SupabaseSession = try await validSession()
        let pkce: PKCE = .make()
        let query: [URLQueryItem] = [
            URLQueryItem(name: "provider", value: provider.rawValue),
            URLQueryItem(name: "redirect_to", value: OnlineConfig.callbackURL),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
            URLQueryItem(name: "skip_http_redirect", value: "true"),
        ]
        let authorize: URLRequest = SupabaseWire.request(base: base, path: "/auth/v1/user/identities/authorize", method: "GET", query: query,
                                                         apiKey: apiKey, accessToken: current.accessToken)
        let (data, status) = try await perform(authorize)
        guard (200..<300).contains(status) else { throw linkError(status: status, body: data, provider: provider) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let text = json["url"] as? String, let url = URL(string: text) else {
            throw OnlineError.offline
        }
        let callback: URL = try await authenticator.authenticate(url: url, callbackScheme: OnlineConfig.callbackScheme)
        let code: String = try SupabaseWire.authorizationCode(from: callback, provider: provider)
        let linked: SupabaseSession = try await exchangeCode(code, verifier: pkce.verifier, provider: provider)
        store.save(linked)
        return linked
    }

    private func linkError(status: Int, body: Data, provider: SignInProvider) -> OnlineError {
        let mapped: OnlineError = SupabaseWire.mapLinkError(status: status, body: body, provider: provider)
        return mapped == .offline && (400..<500).contains(status) ? .rejected("Linking did not finish. Try again.") : mapped
    }

    private func signUpAnonymously() async throws -> SupabaseSession {
        let request: URLRequest = SupabaseWire.request(base: base, path: "/auth/v1/signup", method: "POST", body: Data("{}".utf8), apiKey: apiKey)
        let (data, status) = try await perform(request)
        guard (200..<300).contains(status) else { throw SupabaseWire.mapError(status: status, body: data) }
        let session: SupabaseSession = try parse(data, fallback: nil)
        store.save(session)
        return session
    }

    private func refresh(_ old: SupabaseSession) async throws -> SupabaseSession {
        try await shared { (me: SupabaseIdentityProvider) -> SupabaseSession in try await me.exchangeRefreshToken(old) }
    }

    private func exchangeRefreshToken(_ old: SupabaseSession) async throws -> SupabaseSession {
        let body: Data = try JSONSerialization.data(withJSONObject: ["refresh_token": old.refreshToken])
        let request: URLRequest = SupabaseWire.request(base: base, path: "/auth/v1/token", method: "POST",
                                                       query: [URLQueryItem(name: "grant_type", value: "refresh_token")], body: body, apiKey: apiKey)
        let (data, status) = try await perform(request)
        guard (200..<300).contains(status) else {
            let failure: OnlineError = SupabaseWire.mapError(status: status, body: data)
            if failure == .notSignedIn { store.clear() }
            throw failure
        }
        let fresh: SupabaseSession = try parse(data, fallback: old.provider)
        store.save(fresh)
        return fresh
    }

    private func shared(_ work: @escaping @Sendable (SupabaseIdentityProvider) async throws -> SupabaseSession) async throws -> SupabaseSession {
        if let running = inFlight { return try await running.value }
        let task = Task { try await work(self) }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    private func parse(_ data: Data, fallback: SignInProvider?) throws -> SupabaseSession {
        do { return try decoder.decode(SupabaseTokenResponse.self, from: data).session(now: clock(), fallbackProvider: fallback) } catch { throw OnlineError.offline }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, Int) {
        do { return try await transport.send(request) } catch { throw OnlineError.offline }
    }
}
