import XCTest
import GameCore
import Finance
import Businesses
import Simulation

final class BigWeatherWarningTests: XCTestCase {
    func testBigWarningsNameOnlyOpenCompaniesInThatCountry() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 11)
        XCTAssertTrue(e.bigWeatherWarnings().isEmpty, "no company, no warning")
        e.update { s, _, _ in Ledger.move(&s, .me, 900_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 60_000_000) else { return XCTFail("start") }
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .open } }
        var seen = Set<String>()
        let start = e.state.week
        for w in start..<(start + 300) {
            e.update { s, _, _ in s.week = w }
            for b in e.bigWeatherWarnings() {
                seen.insert(b.kind)
                XCTAssertTrue(["storm", "heat", "flood"].contains(b.kind))
                XCTAssertTrue(b.week >= w && b.week <= w + 2)
                XCTAssertFalse(b.companyIDs.isEmpty)
                for cid in b.companyIDs { XCTAssertEqual(e.state.company(cid)?.countryCode, b.countryCode) }
                XCTAssertTrue(b.companyIDs.contains(id))
            }
        }
        XCTAssertFalse(seen.isEmpty, "300 weeks should hold at least one storm, heatwave or flood")
    }
}
