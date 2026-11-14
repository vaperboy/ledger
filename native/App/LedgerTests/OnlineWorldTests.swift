import XCTest
@testable import Ledger

@MainActor
final class OnlineWorldTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try SupabaseWire.makeDecoder().decode(type, from: Data(json.utf8))
    }

    private func service() -> MockOnlineService {
        MockOnlineService(suiteName: "test.world." + UUID().uuidString, key: "k", latencyMilliseconds: 0)
    }

    func testFriendActivityAndPresenceDecode() throws {
        let a = try decode(FriendActivity.self, """
        {"activity":[{"id":"6a2f0f3e-0000-4000-8000-000000000001","playerID":"u1","playerName":"Mara Voss","kind":"levelUp","count":7,"label":null,"at":1762761600.5},
                     {"id":"6a2f0f3e-0000-4000-8000-000000000002","playerID":"u2","playerName":"Tomas","kind":"auctionSold","count":null,"label":"Brass scales","at":1762761000}],
         "presence":[{"playerID":"u1","lastSeen":1762761600.5,"online":true},{"playerID":"u2","lastSeen":null,"online":false}]}
        """)
        XCTAssertEqual(a.activity.count, 2)
        XCTAssertEqual(a.activity[0].sentence, "Mara Voss reached level 7.")
        XCTAssertEqual(a.activity[1].sentence, "Tomas sold Brass scales at auction.")
        XCTAssertTrue(a.presence[0].online)
        XCTAssertNil(a.presence[1].lastSeen)
    }

    func testSettlementsDecodeWithAndWithoutMeta() throws {
        let rows = try decode([OnlineSettlementRow].self, """
        [{"id":"6a2f0f3e-0000-4000-8000-0000000000a1","amount":550.00,"currency":"GBP","kind":"supply_sale","ref":"c:2026-11-02","label":"Sold to other players",
          "meta":{"companyKey":"own.4","listingID":"x","units":50,"unitPrice":11.00,"week":"2026-11-02"},"createdAt":"2026-11-09T10:00:00.123456+00:00"},
         {"id":"6a2f0f3e-0000-4000-8000-0000000000a2","amount":-105,"currency":"USD","kind":"auction_win","ref":"r","label":"Won at auction","meta":{"auctionID":"a","defID":"abacus","serial":1}}]
        """)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].companyKey, "own.4")
        XCTAssertEqual(rows[0].units, 50)
        XCTAssertEqual(rows[0].unitPrice, 11)
        XCTAssertEqual(rows[1].amount, -105)
        XCTAssertNil(rows[1].companyKey)
    }

    func testWorldPulseIgnoresTheServerClock() throws {
        let p = try decode(WorldPulse.self, #"{"online":14,"players":41,"now":1762761600.25}"#)
        XCTAssertEqual(p, WorldPulse(online: 14, players: 41))
    }

    func testNewsFeedRowsBecomeEngineEvents() throws {
        let rows = try decode([ServerPlayerEvent].self, """
        [{"id":"e1","kind":"branchMilestone","playerID":"u1","playerName":"Mara Voss","countryCode":"GB","audience":"everyone","day":20400,"trade":"Bakery","city":"Leeds",
          "company":"Voss & Co","count":5,"otherName":null,"club":null,"isFriend":true,"namesVisible":true},
         {"id":"e2","kind":"somethingNew","playerID":"u2","playerName":"X","countryCode":"GB","audience":"friends","day":20400,"trade":null,"city":null,
          "company":null,"count":null,"otherName":null,"club":null,"isFriend":false,"namesVisible":false}]
        """)
        XCTAssertEqual(rows[0].event?.day, 20400)
        XCTAssertEqual(rows[0].event?.count, 5)
        XCTAssertNil(rows[1].event)
    }

    func testProfileCarriesLastSeenAsEpochSeconds() throws {
        let p = try SupabaseWire.decodeProfile(Data("""
        {"id":"u1","code":"K7M-4PQ2","displayName":"Mara","avatarColour":3,"countryCode":"GB","level":4,"badges":[],"privacy":"everyone","companyCount":0,
         "companies":[],"gameWeek":1,"tradesCompleted":0,"relation":"friend","lastSeen":1762761600.5}
        """.utf8))
        XCTAssertEqual(p.lastSeen, 1762761600.5)
    }

    func testNewServerRulesHaveWords() {
        for code in ["price_outside_market", "too_many_orders", "not_reportable", "invalid_event", "rate_limited", "start_price_too_low", "seller_cannot_bid"] {
            let body = Data(#"{"code":"P0001","message":"\#(code)"}"#.utf8)
            guard case .rejected(let why) = SupabaseWire.mapError(status: 400, body: body) else { return XCTFail(code) }
            XCTAssertFalse(why.isEmpty)
        }
        let low = SupabaseWire.mapError(status: 400, body: Data(#"{"code":"P0001","message":"too_low:105"}"#.utf8))
        XCTAssertEqual(low, .rejected("The lowest bid now is 105."))
    }

    func testInviteLinksRoundTrip() throws {
        XCTAssertEqual(InviteLink.normalised("k7m4pq2"), "K7M-4PQ2")
        XCTAssertEqual(InviteLink.normalised("K7M-4PQ2"), "K7M-4PQ2")
        XCTAssertNil(InviteLink.normalised("K7M-4P"))
        XCTAssertEqual(InviteLink.code(from: try XCTUnwrap(URL(string: "ledger://friend/K7M-4PQ2"))), "K7M-4PQ2")
        XCTAssertEqual(InviteLink.code(from: try XCTUnwrap(URL(string: "ledger://friend/k7m4pq2"))), "K7M-4PQ2")
        XCTAssertNil(InviteLink.code(from: try XCTUnwrap(URL(string: "ledger://other/K7M-4PQ2"))))
        XCTAssertNil(InviteLink.code(from: try XCTUnwrap(URL(string: "https://example.com/somewhere"))))
        XCTAssertEqual(InviteLink.code(from: try XCTUnwrap(URL(string: "https://x.supabase.co/functions/v1/invite?c=K7M4PQ2"))), "K7M-4PQ2")
        XCTAssertTrue(InviteLink.message(code: "K7M-4PQ2").contains("K7M-4PQ2"))
    }

    func testTheStandInNeverLetsAFreshGameLowerTheProfile() async throws {
        let s = service()
        _ = try await s.signIn(with: .apple)
        _ = try await s.createProfile(adultConfirmed: true)
        let company = OnlineCompany(id: "own.1", name: "Old Bakery", trade: "Bakery", city: "Leeds", countryCode: "UK", health: .thriving)
        _ = try await s.updateMyProfile(ProfileUpdate(companies: [company], level: 9, badges: ["First Profit", "Ten Hires"], gameWeek: 120))
        let fresh = OnlineCompany(id: "own.1", name: "New Cafe", trade: "Cafe", city: "Leeds", countryCode: "UK", health: .new)
        let p = try await s.updateMyProfile(ProfileUpdate(companies: [fresh], level: 1, badges: ["Debt Free"], gameWeek: 2))
        XCTAssertEqual(p.level, 9)
        XCTAssertEqual(p.gameWeek, 120)
        XCTAssertEqual(p.companies?.first?.name, "Old Bakery")
        XCTAssertEqual(Set(p.badges), Set(["First Profit", "Ten Hires", "Debt Free"]))
        let ahead = try await s.updateMyProfile(ProfileUpdate(companies: [fresh], level: 10, gameWeek: 121))
        XCTAssertEqual(ahead.level, 10)
        XCTAssertEqual(ahead.companies?.first?.name, "New Cafe")
    }

    func testTheStandInHasNothingToSettleAndAnswersTheWorldCalls() async throws {
        let s = service()
        _ = try await s.signIn(with: .apple)
        _ = try await s.createProfile(adultConfirmed: true)
        let rows = try await s.pendingSettlements()
        XCTAssertTrue(rows.isEmpty)
        let pulse = try await s.heartbeat()
        XCTAssertGreaterThan(pulse.players, 0)
        let activity = try await s.friendActivity()
        XCTAssertEqual(Set(activity.presence.map { $0.playerID }).count, activity.presence.count)
    }

    func testStandInCodesHaveTheServersShape() {
        let code = SampleRoster.code(for: "p01")
        XCTAssertEqual(code.count, 8)
        XCTAssertNotNil(InviteLink.normalised(code))
    }
}
