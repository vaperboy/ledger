import XCTest
@testable import Ledger

final class AccountSwitchTests: XCTestCase {
    private static func body(_ request: URLRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
    }

    private static func savedGame(week: Int) -> String {
        AccountGameCodec.pack(stateJSON: Data(#"{"week":12}"#.utf8), info: AccountGameInfo(updatedAt: Date(timeIntervalSince1970: 1_800_000_000), week: week, title: "Harbour Bakery"))!
    }

    func testAppleLinkSendsTheTokenWithTheCurrentAccount() async throws {
        let store = MemorySessionStore(AuthFixtures.session())
        let transport = FakeTransport { _ in (AuthFixtures.token(access: "linked", refresh: "r2", provider: "anonymous", identities: ["apple"]), 200) }
        let session = try await AuthFixtures.provider(store: store, transport: transport).linkApple(idToken: "apple-jwt", nonce: "raw")
        XCTAssertEqual(session.provider, .apple)
        XCTAssertEqual(store.load()?.accessToken, "linked")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/auth/v1/token")
        XCTAssertEqual(request.url?.query, "grant_type=id_token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer old")
        let body = Self.body(request)
        XCTAssertEqual(body["provider"] as? String, "apple")
        XCTAssertEqual(body["id_token"] as? String, "apple-jwt")
        XCTAssertEqual(body["nonce"] as? String, "raw")
        XCTAssertEqual(body["link_identity"] as? Bool, true)
    }

    func testTheAppleNonceIsTheHexDigestOfTheRawValue() {
        XCTAssertEqual(AppleNonce.hash("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertNotEqual(AppleNonce.make(), AppleNonce.make())
    }

    func testTheSavedGameRoundTrips() throws {
        let text = Self.savedGame(week: 12)
        XCTAssertEqual(AccountGameCodec.info(of: text)?.week, 12)
        XCTAssertEqual(AccountGameCodec.info(of: text)?.title, "Harbour Bakery")
        XCTAssertEqual(AccountGameCodec.unpack(text), #"{"week":12}"#)
        XCTAssertNil(AccountGameCodec.unpack("not a save"))
    }

    func testGoogleIsHiddenWhenTheServerHasItOffAndNothingIsOfferedWithoutApple() async {
        func options(_ external: String) async -> [SignInProvider] {
            let transport = FakeTransport { request in
                request.url?.path == "/auth/v1/settings" ? (AuthFixtures.json(#"{"external":\#(external)}"#), 200) : (Data(), 404)
            }
            let tokens = AuthFixtures.provider(store: MemorySessionStore(), transport: transport)
            return await SupabaseOnlineService(baseURL: AuthFixtures.base, apiKey: "key", tokens: tokens, transport: transport).signInOptions()
        }
        let both = await options(#"{"apple":true,"google":true}"#)
        let appleOnly = await options(#"{"apple":true,"google":false}"#)
        let noApple = await options(#"{"apple":false,"google":true}"#)
        XCTAssertEqual(both, [.apple, .google])
        XCTAssertEqual(appleOnly, [.apple])
        XCTAssertEqual(noApple, [])
    }

    func testTheDeletionPreviewListsWhatTheServerSettles() async throws {
        let transport = FakeTransport { request in
            request.url?.path == "/rest/v1/rpc/account_deletion_preview"
                ? (AuthFixtures.json(#"{"items":["Alpha Bakery is closed.","1 supply deal ends."]}"#), 200) : (Data(), 404)
        }
        let tokens = AuthFixtures.provider(store: MemorySessionStore(AuthFixtures.session()), transport: transport)
        let preview = try await SupabaseOnlineService(baseURL: AuthFixtures.base, apiKey: "key", tokens: tokens, transport: transport).deletionPreview()
        XCTAssertEqual(preview.items, ["Alpha Bakery is closed.", "1 supply deal ends."])
    }

    @MainActor
    func testAnAppleIDOfAnotherAccountOffersTheSwitchAndMovesThePhoneToIt() async throws {
        let game = Self.savedGame(week: 12)
        let store = MemorySessionStore(AuthFixtures.session())
        let transport = FakeTransport { request in
            switch request.url?.path {
            case "/auth/v1/token":
                if AccountSwitchTests.body(request)["link_identity"] as? Bool == true {
                    return (AuthFixtures.json(#"{"code":422,"error_code":"identity_already_exists","msg":"Identity is already linked to another user"}"#), 422)
                }
                return (AuthFixtures.token(access: "other", refresh: "r9", user: "u2", provider: "apple", identities: ["apple"]), 200)
            case "/rest/v1/rpc/view_profile":
                return (AuthFixtures.json(AuthFixtures.profileJSON), 200)
            case "/rest/v1/save_blobs":
                let rows = try JSONSerialization.data(withJSONObject: [["payload": game]])
                return (rows, 200)
            case "/rest/v1/rpc/account_status":
                return (AuthFixtures.json(#"{"hasProfile":true,"adultConfirmed":true,"isAdmin":false,"linkRewardGold":100,"linkRewardClaimed":true}"#), 200)
            default:
                return (Data(), 404)
            }
        }
        let tokens = AuthFixtures.provider(store: store, transport: transport)
        let online = OnlineSession(service: SupabaseOnlineService(baseURL: AuthFixtures.base, apiKey: "key", tokens: tokens, transport: transport))

        let linked = await online.connect(.apple(idToken: "apple-jwt", nonce: "raw"))
        XCTAssertFalse(linked)
        XCTAssertNil(online.problem)
        guard case .chooseGame(let offer)? = online.accountChoice else { return XCTFail("No switch was offered") }
        XCTAssertEqual(offer.playerID, "u2")
        XCTAssertEqual(offer.name, "Player AB12")
        XCTAssertEqual(offer.savedGame?.week, 12)
        XCTAssertEqual(store.load()?.userID, "u1")
        let viewProfile = try XCTUnwrap(transport.requests.first { $0.url?.path == "/rest/v1/rpc/view_profile" })
        XCTAssertEqual(viewProfile.value(forHTTPHeaderField: "Authorization"), "Bearer other")

        await online.finishSwitch(offer, loadGame: false, store: GameStore())
        XCTAssertNil(online.accountChoice)
        XCTAssertEqual(online.accountID, "u2")
        XCTAssertEqual(online.provider, .apple)
        XCTAssertEqual(store.load()?.userID, "u2")
    }

    @MainActor
    func testTurningTheSwitchDownKeepsThePhoneOnItsOwnAccount() async {
        let store = MemorySessionStore(AuthFixtures.session())
        let transport = FakeTransport { request in
            switch request.url?.path {
            case "/auth/v1/token":
                if AccountSwitchTests.body(request)["link_identity"] as? Bool == true {
                    return (AuthFixtures.json(#"{"code":422,"error_code":"identity_already_exists","msg":"Identity is already linked to another user"}"#), 422)
                }
                return (AuthFixtures.token(access: "other", refresh: "r9", user: "u2", provider: "apple", identities: ["apple"]), 200)
            case "/rest/v1/save_blobs": return (AuthFixtures.json("[]"), 200)
            case "/auth/v1/logout": return (Data(), 204)
            default: return (Data(), 404)
            }
        }
        let tokens = AuthFixtures.provider(store: store, transport: transport)
        let online = OnlineSession(service: SupabaseOnlineService(baseURL: AuthFixtures.base, apiKey: "key", tokens: tokens, transport: transport))
        _ = await online.connect(.apple(idToken: "apple-jwt", nonce: "raw"))
        guard case .chooseGame(let offer)? = online.accountChoice else { return XCTFail("No switch was offered") }
        XCTAssertNil(offer.savedGame)
        online.cancelAccountChoice()
        let end = Date().addingTimeInterval(5)
        while !transport.paths.contains("/auth/v1/logout") && Date() < end { try? await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertTrue(transport.paths.contains("/auth/v1/logout"))
        XCTAssertNil(online.accountChoice)
        XCTAssertEqual(store.load()?.userID, "u1")
    }
}
