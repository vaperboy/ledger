import XCTest
@testable import Ledger

final class PopupQueueTests: XCTestCase {

    private func queue(_ rows: [(String, PopupPriority)]) -> PopupQueue {
        var q = PopupQueue()
        var seq = 0
        for r in rows { seq += 1; q.upsert(key: r.0, priority: r.1, seq: seq) }
        return q
    }

    func testEmptyQueueShowsNothing() {
        XCTAssertNil(PopupQueue().visibleKey)
    }

    func testPriorityOrderIsConfirmDecisionAlertNoticeReportCelebrationPanel() {
        let q = queue([("panel", .panel), ("celebration", .celebration), ("report", .report), ("notice", .notice),
                       ("alert", .alert), ("decision", .decision), ("confirm", .confirm)])
        XCTAssertEqual(q.ordered.map { (i: PopupQueue.Item) -> String in i.key },
                       ["confirm", "decision", "alert", "notice", "report", "celebration", "panel"])
        XCTAssertEqual(q.visibleKey, "confirm")
    }

    func testNoticesAreAQueueOldestFirst() {
        let q = queue([("n1", .notice), ("n2", .notice), ("n3", .notice)])
        XCTAssertEqual(q.visibleKey, "n1")
    }

    func testPanelsAreAStackNewestOnTop() {
        let q = queue([("a", .panel), ("b", .panel)])
        XCTAssertEqual(q.visibleKey, "b")
    }

    func testConfirmRaisedFromAPanelShowsAboveItAndThePanelReturnsAfterwards() {
        var q = queue([("panel", .panel)])
        q.upsert(key: "confirm", priority: .confirm, seq: 2)
        XCTAssertEqual(q.visibleKey, "confirm")
        q.remove(key: "confirm")
        XCTAssertEqual(q.visibleKey, "panel")
    }

    func testNoticeWaitsForNothingWhenAPanelIsOpen() {
        var q = queue([("panel", .panel)])
        q.upsert(key: "notice", priority: .notice, seq: 2)
        XCTAssertEqual(q.visibleKey, "notice")
    }

    func testRewardWaitsForTheReportAndThenShows() {
        var q = queue([("reward", .celebration), ("report", .report)])
        XCTAssertEqual(q.visibleKey, "report")
        q.remove(key: "report")
        XCTAssertEqual(q.visibleKey, "reward")
    }

    func testRegisteringAgainKeepsTheOrderOfArrival() {
        var q = queue([("n1", .notice), ("n2", .notice)])
        q.upsert(key: "n1", priority: .notice, seq: 99)
        XCTAssertEqual(q.visibleKey, "n1")
        XCTAssertEqual(q.items.count, 2)
    }

    func testRemovingAnUnknownKeyChangesNothing() {
        var q = queue([("a", .report)])
        q.remove(key: "zzz")
        XCTAssertEqual(q.visibleKey, "a")
    }

    func testOrderAcrossTwoHostsUsesTheGlobalArrivalOrder() {
        let own = [PopupQueue.Item(key: "own", priority: .notice, seq: 5)]
        let parent = [PopupQueue.Item(key: "parent", priority: .notice, seq: 3)]
        XCTAssertEqual(PopupQueue.visible(own + parent), "parent")
    }
}
