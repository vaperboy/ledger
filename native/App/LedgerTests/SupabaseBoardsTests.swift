import XCTest
@testable import Ledger

final class SupabaseBoardsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try SupabaseWire.makeDecoder().decode(type, from: Data(json.utf8))
    }

    func testLeaderboardRowsDecode() throws {
        let rows = try decode([LeaderboardRow].self, #"[{"playerID":"u1","name":"Mara Voss","week":40,"netWorth":5000000.00,"tradingResult":-5000.00}]"#)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].netWorth, 5_000_000)
        XCTAssertEqual(rows[0].tradingResult, -5_000)
    }

    func testWorldRulesSnapshotDecodes() throws {
        let s = try decode(WorldRulesSnapshot.self, """
        {"rules":{"band.exchange_low":0.75,"tax.step":0.01},
         "exchange":{"bandLow":0.75,"bandHigh":1.25,"dayMoveShare":0.10,"valueStepShare":0.10,"holderCapShare":0.20,"ownerFloorShare":0.51,
                     "lockUpDays":28,"quarterDays":91,"blackoutBefore":7,"blackoutAfter":1},
         "updatedAt":"2026-11-09T10:00:00.123456+00:00"}
        """)
        XCTAssertEqual(s.rules["tax.step"], 0.01)
        XCTAssertEqual(s.exchange.holderCapShare, 0.20)
        XCTAssertEqual(s.exchange.quarterDays, 91)
        XCTAssertNotNil(s.updatedAt)
    }

    func testProfileCarriesTheIcon() throws {
        let p = try SupabaseWire.decodeProfile(Data("""
        {"id":"u1","code":"K7M-4PQ2","avatarIcon":"av.coffee","displayName":"Mara","avatarColour":3,"countryCode":"GB","level":4,"badges":[],
         "privacy":"everyone","companyCount":0,"companies":[],"gameWeek":1,"tradesCompleted":0,"relation":"you"}
        """.utf8))
        XCTAssertEqual(p.avatarIcon, "av.coffee")
    }

    func testExchangeAndOfficeErrorCodesHaveWords() {
        for code in ["lock_up", "blackout", "outside_day_limit", "holder_cap", "value_jump", "own_office", "currency_mismatch", "already_hired", "too_early"] {
            let body = Data(#"{"code":"P0001","message":"\#(code)"}"#.utf8)
            guard case .rejected(let why) = SupabaseWire.mapError(status: 400, body: body) else { return XCTFail(code) }
            XCTAssertFalse(why.isEmpty)
        }
    }
}
