import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Manager targets and the yearly budget: set by you, judged each month, bonuses paid through the books.
final class ManagerTargetsTests: XCTestCase {
    private func managedCafe(seed: Int) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 30_000_000) else { throw XCTSkip("no company") }
        let cands = try XCTUnwrap(e.searchManagers(companyID: id))
        XCTAssertEqual(e.hireManager(personID: cands[0].id, companyID: id, monthlyWage: cands[0].askingMonthlyWage * 1.2), .ok)
        return (e, id)
    }

    private func run(_ e: inout GameEngine, days: Int) {
        for _ in 0..<days {
            e.nextDay()
            for m in e.openDecisions where ManagerTargets.handlesAnswer(m.actionID) || ["prop", "mgrraise", "mgrpoach", "staffx"].contains(m.actionID) { e.answer(messageID: m.id, option: 0) }
        }
    }

    func testTargetsAreSetJudgedAndPaid() throws {
        var (e, id) = try managedCafe(seed: 5)
        run(&e, days: 14 * 7)   // a few months of numbers
        // With nobody between you and the manager, you set the targets and the bonus level.
        let st = try XCTUnwrap(e.targetStatus(companyID: id))
        XCTAssertTrue(st.setter.isOwner)
        let pv = try XCTUnwrap(e.targetPreview(companyID: id, mode: 2))
        XCTAssertEqual(pv.rows.count, 3)
        XCTAssertGreaterThan(pv.bonusPerTarget[2], pv.bonusPerTarget[1])
        XCTAssertTrue(e.setTargets(companyID: id, mode: 2, bonus: 2))
        let after = try XCTUnwrap(e.targetStatus(companyID: id))
        XCTAssertEqual(after.bonusLevel, 2)
        XCTAssertEqual(after.standing.count, 3)
        XCTAssertTrue(after.budget?.approved ?? false)
        run(&e, days: 12 * 7)
        let log = e.state.company(id)?.value("tg58")["log"].array ?? []
        XCTAssertFalse(log.isEmpty, "months are judged against the targets")
        XCTAssertEqual(log.last?["of"].int, 3)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "bonuses go through the company's books")
        // The scorecard reads the same log.
        XCTAssertNotNil(e.runManagerScorecards().first { $0.id == id })
    }

    func testNoTargetsWithoutHistoryOrForUnmanagedCompany() throws {
        var (e, id) = try managedCafe(seed: 7)
        XCTAssertNil(e.targetPreview(companyID: id, mode: 1), "needs months of numbers first")
        XCTAssertFalse(e.setTargets(companyID: id, mode: 1, bonus: 1))
        XCTAssertNil(e.targetStatus(companyID: 9999))
    }

    /// `current` must be a real nil when the month has no targets (a `JSONValue` nil literal used to become `.null`, so every managed company counted as having targets).
    func testNoTargetsThisMonthIsARealNil() throws {
        var (e, id) = try managedCafe(seed: 5)
        var co = try XCTUnwrap(e.state.company(id))
        XCTAssertNil(ManagerTargets.current(co, week: e.state.week), "freshly managed: no history, no targets yet")
        XCTAssertEqual(ManagerTargets.demandFactor(co, week: e.state.week), 1, "no targets, no chase for a bonus")
        XCTAssertEqual(ManagerTargets.qualityCare(co, week: e.state.week), 0)
        XCTAssertTrue(ManagerTargets.standing(co, week: e.state.week).isEmpty)
        XCTAssertFalse(WorkerBonus.hasTargets(co, week: e.state.week))
        run(&e, days: 14 * 7)
        co = try XCTUnwrap(e.state.company(id))
        let m = try XCTUnwrap(ManagerTargets.current(co, week: e.state.week), "after a few months the manager has this month's targets")
        XCTAssertFalse(m.isNull)
        XCTAssertGreaterThan(ManagerTargets.demandFactor(co, week: e.state.week), 1)
        XCTAssertTrue(WorkerBonus.hasTargets(co, week: e.state.week))
        // A month with no record (far ahead) is nil again.
        XCTAssertNil(ManagerTargets.current(co, week: e.state.week + 20))
        // Unmanaged company: never a chase.
        let plain = ChainsTests.start(&e, "cafe")
        XCTAssertEqual(ManagerTargets.demandFactor(try XCTUnwrap(e.state.company(plain)), week: e.state.week), 1)
    }
}
