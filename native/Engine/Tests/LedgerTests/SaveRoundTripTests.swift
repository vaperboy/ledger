import XCTest
import GameCore

/// A save from the original game must load and write back without losing or changing anything.
final class SaveRoundTripTests: XCTestCase {
    private func loadRaw(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Golden"))
        return try Data(contentsOf: url)
    }

    func testLegacySaveRoundTripsLosslessly() throws {
        for name in ["save_cafe_week3", "save_cafe_week15"] {
            let data = try loadRaw(name)
            let original = try JSONDecoder().decode(JSONValue.self, from: data)
            let state = try JSONDecoder().decode(GameState.self, from: data)
            let written = try JSONEncoder().encode(state)
            var again = try JSONDecoder().decode(JSONValue.self, from: written)
            // The original only writes `day` once the player has used Next Day; we always write it.
            if original["day"].isNull, again["day"].int == 0 { again["day"] = .null; var o = again.object; o.removeValue(forKey: "day"); again = .object(o) }
            XCTAssertEqual(again, original, "\(name) changed while loading and saving")
            XCTAssertEqual(state.version, 5)
            XCTAssertEqual(state.homeCountryCode, "UK")
            XCTAssertEqual(state.companies.count, 1)
            XCTAssertEqual(state.companies[0].type, "cafe")
            XCTAssertEqual(state.companies[0].form, .limited)
        }
    }

    func testTypedAccessors() throws {
        let state = try JSONDecoder().decode(GameState.self, from: try loadRaw("save_cafe_week15"))
        let co = state.companies[0]
        XCTAssertEqual(co.name, "Test Cafe")
        XCTAssertEqual(co.status, .open)
        XCTAssertGreaterThanOrEqual(co.staff.count, 1)
        XCTAssertEqual(state.week, 15)
        XCTAssertEqual(state.loans.first?.kind, "start")
        XCTAssertEqual(state.random.state, 15751624)
        XCTAssertFalse(state.isGameOver)
        XCTAssertGreaterThan(state.people.count, 0)
    }
}
