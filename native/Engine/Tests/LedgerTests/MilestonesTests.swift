import XCTest
import GameCore
import Countries
import Finance
@testable import SaveSystem
@testable import Simulation

final class MilestonesTests: XCTestCase {
    private func game(_ seed: Int = 5) throws -> GameEngine { try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed) }
    private func give(_ e: inout GameEngine, _ amount: Double) {
        let a = e.homeCurrency.scaledPrice(amount)
        e.update { s, _, _ in Ledger.move(&s, .me, a, why: "Test funds") }
    }
    private func week(_ e: inout GameEngine) { for _ in 0..<7 { _ = e.nextDay() } }
    private func milestoneTitles(_ e: GameEngine) -> [Celebration] { e.pendingCelebrations.filter { $0.title.hasPrefix("Net worth passed") } }

    func testMilestoneIsCrossedOnceAndQueuedOnce() throws {
        var e = try game()
        give(&e, 300_000)
        _ = e.nextDay()
        let r = e.milestoneProgress.reached
        XCTAssertGreaterThanOrEqual(r.count, 2)
        XCTAssertEqual(milestoneTitles(e).count, 1, "only the highest newly crossed is celebrated")
        _ = e.takeCelebrations()
        for _ in 0..<3 { _ = e.nextDay() }
        XCTAssertEqual(e.milestoneProgress.reached.count, r.count)
        XCTAssertTrue(milestoneTitles(e).isEmpty)
        XCTAssertGreaterThan(e.milestoneProgress.next, r.last!.amount)
    }

    func testStreakResetsOnALossWeekAndKeepsBest() throws {
        var e = try game()
        week(&e)
        // Enough cash that the loss does not end the game (a player with no company and a deep overdraft is out on the day the failure check runs).
        give(&e, 10_000_000); week(&e)
        e.update { s, _, _ in var m = s.rest["miles"]!; m["s"] = .number(3); m["bs"] = .number(3); s.rest["miles"] = m }
        let loss = e.homeCurrency.scaledPrice(5_000_000)
        e.update { s, _, _ in Ledger.move(&s, .me, -loss, why: "Loss") }
        week(&e)
        XCTAssertEqual(e.milestoneProgress.profitStreak, 0)
        XCTAssertEqual(e.milestoneProgress.bestStreak, 3)
    }

    func testStreakCountsGainWeeks() throws {
        var e = try game()
        week(&e)
        for _ in 0..<2 { give(&e, 1_000_000); week(&e) }
        XCTAssertEqual(e.milestoneProgress.profitStreak, 2)
        XCTAssertGreaterThan(e.milestoneProgress.bestWeek, 0)
    }

    func testSaveReloadEquality() throws {
        var e = try game()
        give(&e, 600_000); week(&e); week(&e)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-miles-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaveStore(directory: dir)
        try store.save(e.state, summary: store.summary(of: e.state, trades: e.data.catalog))
        let (data, events, marketing) = try GameEngine.loadResources()
        let back = GameEngine(state: try store.load(), data: data, events: events, marketing: marketing)
        XCTAssertEqual(back.milestoneProgress, e.milestoneProgress)
        XCTAssertEqual(back.pendingCelebrations, e.pendingCelebrations)
    }

    func testDeterminismAndMarkShown() throws {
        var a = try game(9), b = try game(9)
        for _ in 0..<2 { give(&a, 300_000); give(&b, 300_000); week(&a); week(&b) }
        XCTAssertEqual(a.milestoneProgress, b.milestoneProgress)
        XCTAssertEqual(a.pendingCelebrations, b.pendingCelebrations)
        XCTAssertEqual(a.state, b.state)
        let first = try XCTUnwrap(a.pendingCelebrations.first)
        a.markCelebrationShown(String(first.id))
        XCTAssertFalse(a.pendingCelebrations.contains { $0.id == first.id })
    }
}
