import XCTest
@testable import Ledger

/// Request building, profile decoding with hidden fields, and server error mapping for the Supabase client.
final class SupabaseWireTests: XCTestCase {
    private let base = URL(string: "https://example.supabase.co")!

    func testRequestCarriesKeyTokenAndQuery() {
        let req = SupabaseWire.request(base: base, path: "/rest/v1/blocks", method: "DELETE",
                                       query: [URLQueryItem(name: "blocker_id", value: "eq.a")], apiKey: "k", accessToken: "t", prefer: "return=minimal")
        XCTAssertEqual(req.url?.absoluteString, "https://example.supabase.co/rest/v1/blocks?blocker_id=eq.a")
        XCTAssertEqual(req.httpMethod, "DELETE")
        XCTAssertEqual(req.value(forHTTPHeaderField: "apikey"), "k")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer t")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Prefer"), "return=minimal")
    }

    func testRequestWithoutSessionHasNoAuthorization() {
        let req = SupabaseWire.request(base: base, path: "/auth/v1/signup", method: "POST", body: Data("{}".utf8), apiKey: "k")
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testPrivateProfileKeepsHiddenFieldsNil() throws {
        let json = """
        {"id":"u1","code":"K7M-4PQ2","displayName":"Mara Voss","avatarColour":3,"countryCode":"GB","level":null,"badges":[],
         "privacy":"onlyMe","companyCount":null,"companies":null,"isSimulated":true,"gameWeek":null,"tradesCompleted":null,"relation":"none"}
        """
        let p = try SupabaseWire.decodeProfile(Data(json.utf8))
        XCTAssertNil(p.level); XCTAssertNil(p.companyCount); XCTAssertNil(p.companies); XCTAssertNil(p.gameWeek); XCTAssertNil(p.tradesCompleted)
        XCTAssertEqual(p.privacy, .onlyMe)
        XCTAssertEqual(p.relation, FriendRelation.none)
    }

    func testPublicProfileWithCompaniesDecodes() throws {
        let json = """
        {"id":"u2","code":"AAA-BBBB","displayName":"Ines","avatarColour":1,"countryCode":"NG","level":9,"badges":["First Profit"],
         "privacy":"everyone","companyCount":1,"isSimulated":false,"gameWeek":108,"tradesCompleted":27,"relation":"friend",
         "companies":[{"id":"c1","name":"Ines & Co","trade":"Bakery","city":"Lagos","countryCode":"NG","health":"steady"}]}
        """
        let p = try SupabaseWire.decodeProfile(Data(json.utf8))
        XCTAssertEqual(p.level, 9)
        XCTAssertEqual(p.companies?.first?.health, .steady)
        XCTAssertEqual(p.relation, .friend)
    }

    func testFriendsOverviewDecodesPostgresTimestamps() throws {
        let json = """
        {"friends":[],"outgoing":[],"incoming":[{"sentAt":"2026-11-09T10:15:30.123456+00:00","player":
          {"id":"u3","code":"CCC-DDDD","displayName":"Tomas","avatarColour":0,"countryCode":"ES","badges":[],"privacy":"friends",
           "isSimulated":false,"relation":"requestReceived"}}]}
        """
        let o = try SupabaseWire.makeDecoder().decode(FriendsOverview.self, from: Data(json.utf8))
        XCTAssertEqual(o.incoming.count, 1)
        XCTAssertNil(o.incoming[0].player.level)
    }

    func testErrorMapping() {
        func map(_ status: Int, _ body: String) -> OnlineError { SupabaseWire.mapError(status: status, body: Data(body.utf8)) }
        XCTAssertEqual(map(400, #"{"code":"P0001","message":"not_found"}"#), .notFound)
        XCTAssertEqual(map(400, #"{"code":"P0001","message":"blocked"}"#), .blocked)
        XCTAssertEqual(map(400, #"{"code":"P0001","message":"already_friends"}"#), .alreadyFriends)
        XCTAssertEqual(map(400, #"{"code":"P0001","message":"request_pending"}"#), .requestPending)
        XCTAssertEqual(map(400, #"{"code":"P0001","message":"cannot_target_self"}"#), .cannotTargetYourself)
        XCTAssertEqual(map(400, #"{"code":"P0001","message":"name_rejected: That name is reserved."}"#), .nameRejected("That name is reserved."))
        XCTAssertEqual(map(401, #"{"message":"JWT expired"}"#), .notSignedIn)
        XCTAssertEqual(map(400, #"{"error_code":"bad_id_token","msg":"Bad ID token"}"#), .notSignedIn)
        XCTAssertEqual(map(503, ""), .offline)
    }

    func testSessionRefreshWindow() {
        let now = Date()
        let s = SupabaseSession(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(30), userID: "u", createdAt: now,
                                isAnonymous: false, provider: .apple)
        XCTAssertTrue(s.needsRefresh(now: now))
        XCTAssertFalse(s.needsRefresh(now: now.addingTimeInterval(-3600)))
    }
}
