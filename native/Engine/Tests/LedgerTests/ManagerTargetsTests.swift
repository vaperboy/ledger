import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
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

    func testTargetsAreSetByThemselvesJudgedAndTheOwnerApprovesTheBudget() throws {
        var (e, id) = try managedCafe(seed: 5)
        run(&e, days: 14 * 7)   // a few months of numbers
        // With nobody between you and the manager the targets come on their own, from the history and your direction.
        let st = try XCTUnwrap(e.targetStatus(companyID: id))
        XCTAssertTrue(st.setter.isOwner)
        XCTAssertEqual(st.standing.count, 3)
        XCTAssertNotNil(st.budget)
        XCTAssertTrue(e.approveBudget(companyID: id))
        XCTAssertTrue(try XCTUnwrap(e.targetStatus(companyID: id)).budget?.approved ?? false)
        run(&e, days: 12 * 7)
        let log = e.state.company(id)?.value("tg58")["log"].array ?? []
        XCTAssertFalse(log.isEmpty, "months are judged against the targets")
        XCTAssertEqual(log.last?["of"].int, 3)
        XCTAssertTrue(log.allSatisfy { $0["bonus"].isNull }, "no bonus is paid on targets: the profit share is the only pay on results")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        // The scorecard reads the same log.
        XCTAssertNotNil(e.runManagerScorecards().first { $0.id == id })
    }

    /// Each direction tilts the month's targets: growth stretches sales, lean and cash stretch profit.
    func testTheOwnersDirectionTiltsTheTargets() throws {
        var (e, id) = try managedCafe(seed: 5)
        e.update { s, d, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].status = .open
            s.companies[i].monthlyHistory = (0..<6).map { MonthRecord(monthIndex: $0 + 1, revenue: 4_000_000, profit: 400_000, cash: 1_000_000) }
            while GameCalendar.isMonthEnd(week: s.week) { s.week += 1 }
            ManagerTargets.weekly(&s, data: d)
        }
        func targets(_ e: GameEngine) -> (rev: Double, profit: Double)? {
            guard let co = e.state.company(id), let m = ManagerTargets.current(co, week: e.state.week) else { return nil }
            return (m["T"]["rev"].double, m["T"]["profit"].double)
        }
        let base = try XCTUnwrap(targets(e))
        var lean = e, grow = e
        grow.update { s, d, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].set("dir", "growth")
            ManagerTargets.setTargets(&s, i, month: ManagerTargets.mi(s), data: d)
        }
        lean.update { s, d, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].set("dir", "lean")
            ManagerTargets.setTargets(&s, i, month: ManagerTargets.mi(s), data: d)
        }
        let g = try XCTUnwrap(targets(grow)), l = try XCTUnwrap(targets(lean))
        XCTAssertGreaterThan(g.rev, base.rev)
        XCTAssertGreaterThan(l.profit, base.profit)
        XCTAssertGreaterThan(l.profit, g.profit)
        XCTAssertGreaterThan(g.rev, l.rev)
    }

    /// A month counter at or below zero (a hand-made history) must not index outside the twelve months.
    func testMonthOfYearNeverLeavesTheTwelveMonths() {
        for m in -30...30 { XCTAssertTrue((0..<12).contains(ManagerTargets.month0(m)), "\(m)") }
        XCTAssertEqual(ManagerTargets.month0(1), 0); XCTAssertEqual(ManagerTargets.month0(13), 0); XCTAssertEqual(ManagerTargets.month0(0), 11)
    }

    func testNoTargetsWithoutHistoryOrForUnmanagedCompany() throws {
        var (e, id) = try managedCafe(seed: 7)
        XCTAssertTrue(e.targetStatus(companyID: id)?.standing.isEmpty ?? true, "needs months of numbers first")
        XCTAssertFalse(e.approveBudget(companyID: id), "no budget is drafted before there is a history")
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
