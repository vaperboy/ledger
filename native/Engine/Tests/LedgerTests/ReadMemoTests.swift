import XCTest
import GameCore
import Finance
import Businesses
@testable import Simulation

/// The New company list is kept between redraws; it must always equal a fresh calculation, after a day, a purchase and any other change.
final class ReadMemoTests: XCTestCase {
    private func same(_ e: GameEngine, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(e.tradePickerRows(), e.tradePickerRowsFresh(), what, file: file, line: line)
        XCTAssertEqual(e.tradeAffordability(), e.tradeAffordabilityFresh(), what, file: file, line: line)
        XCTAssertEqual(e.tradePickerRows(), e.tradePickerRowsFresh(), what + " (second read)", file: file, line: line)
    }

    func testCachedEqualsFreshAfterDayPurchaseAndAction() throws {
        var e = try GameEngine.showcase(days: 40)
        same(e, "start")
        let before = e.tradePickerRows()
        e.nextDay()
        same(e, "after a day")
        let afterDay = e.tradePickerRows()
        XCTAssertEqual(before.count, afterDay.count)
        _ = e.startCompany(tradeID: "bakery", cityID: e.state.player.cityID, fundWith: 3_000_000)   // a purchase
        same(e, "after starting a company")
        e.update { s, _, _ in Ledger.move(&s, .me, -30_000_000, why: "Test spend") }   // an action that only changes money
        same(e, "after money moved")
        XCTAssertNotEqual(afterDay.map(\.isFunded), e.tradePickerRows().map(\.isFunded), "less money must show in the list")
    }

    func testCopiesDoNotShareStaleResults() throws {
        var a = try GameEngine.showcase(days: 20)
        let b = a
        _ = a.tradePickerRows(); _ = b.tradePickerRows()
        a.update { s, _, _ in Ledger.move(&s, .me, -30_000_000, why: "Test spend") }
        XCTAssertEqual(a.tradePickerRows(), a.tradePickerRowsFresh())
        XCTAssertEqual(b.tradePickerRows(), b.tradePickerRowsFresh())
        XCTAssertNotEqual(a.tradePickerRows(), b.tradePickerRows())
    }

    func testCachedReadIsFast() throws {
        let e = try GameEngine.showcase(days: 20)
        _ = e.tradePickerRows()
        let t = Date()
        for _ in 0..<50 { _ = e.tradePickerRows() }
        print("PERF cached tradePickerRows", Date().timeIntervalSince(t) * 1000 / 50, "ms")
        let f = Date(); _ = e.tradePickerRowsFresh()
        print("PERF fresh tradePickerRows", Date().timeIntervalSince(f) * 1000, "ms")
    }
}
