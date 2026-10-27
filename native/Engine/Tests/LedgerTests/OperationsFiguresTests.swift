import XCTest
import GameCore
import Finance
import Businesses
import Simulation

final class OperationsFiguresTests: XCTestCase {
    func testWeeklyHistoryKeepsEightWeeks() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 21)
        e.update { s, _, _ in Ledger.move(&s, .me, 40_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 12_000_000) else { return XCTFail("start") }
        _ = e.quickSetup(companyID: id)
        for _ in 0..<(7 * 12) { e.nextDay() }
        let f = try XCTUnwrap(e.operationsFigures(companyID: id))
        XCTAssertLessThanOrEqual(f.weeks.count, 8)
        XCTAssertFalse(f.weeks.isEmpty)
        XCTAssertEqual(f.weeks, f.weeks.sorted { $0.week < $1.week })
        XCTAssertNotNil(f.capacityUse)
    }
}
