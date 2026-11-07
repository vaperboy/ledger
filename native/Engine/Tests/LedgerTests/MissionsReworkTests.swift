import XCTest
import GameCore
import Countries
import Finance
@testable import Events
@testable import Businesses
@testable import SaveSystem
@testable import Simulation

/// Awards reflect results, not setup: opening a company, hiring and signing papers earn nothing; results over time do.
final class MissionsReworkTests: XCTestCase {
    /// `ladder: false` plays the older-save mode (no linear ladder): the ladder celebrates every goal by design, the checklist keeps setup steps silent.
    private func setupGame(seed: Int = 4242, ladder: Bool = true) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 80_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: "cafe", cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6 + 3_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
            let i = s.companyIndex(id)!
            var m = StaffMember(raw: [:])
            m.id = s.makeID(); m.role = "waiter"; m.monthlyWage = 300_000; m.hiredWeek = s.week
            s.companies[i].staff.append(m)
        }
        if !ladder { e.update { s, _, _ in s.rest["ldr"] = nil } }
        XCTAssertNotEqual(id, 0)
        return (e, id)
    }
    private func days(_ e: inout GameEngine, _ n: Int) {
        for _ in 0..<n { e.nextDay(); for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) } }
    }
    private func trophyCheck(_ e: inout GameEngine) { e.update { s, d, c in Trophies.check(&s, data: d, context: c) } }
    private func got(_ e: GameEngine, _ id: String) -> Bool { Trophies.entries(e.state).contains { $0.id == id && $0.reachedWeek != nil } }

    func testSetupStepsEarnAtMostOneAwardInTheFirstFourteenDays() throws {
        var (e, _) = try setupGame(ladder: false)
        days(&e, 14)
        _ = e.celebrateDailyGoal()
        // The 80M test funding makes net-worth and cash milestones fire (career goals, art "goal.career"); those are results, not setup awards.
        let setupAwards = e.pendingAwards().filter { !$0.title.contains("Net worth") && !$0.title.contains("million") && $0.artKey != "goal.career" }
        XCTAssertLessThanOrEqual(setupAwards.count, 1, "\(setupAwards.map { $0.title })")
        let trophies = Trophies.entries(e.state).filter { $0.reachedWeek != nil }.map { $0.id }
        XCTAssertFalse(trophies.contains("cust") || trophies.contains("emp") || trophies.contains("mgr") || trophies.contains("branch"), "\(trophies)")
    }

    func testSetupStepsStayClaimableButSilent() throws {
        var (e, _) = try setupGame(ladder: false)
        days(&e, 7)
        XCTAssertTrue(PlayerGoals.stepDone("co", e.state))
        XCTAssertFalse(e.pendingCelebrations.contains { $0.kind == "goal" && $0.art != "goal.career" }, "no popup for a setup step (career cash goals are results and may fire on the test funding)")
        XCTAssertFalse(PlayerGoals.firstSteps(e.state)!.first { $0.id == "co" }!.claimed, "the checklist still lists it")
    }

    func testResultAwardsFireWhenTheirConditionIsMet() throws {
        var (e, id) = try setupGame()
        days(&e, 1)
        trophyCheck(&e)
        for t in ["q3", "emp", "mgr", "cust", "debt0"] { XCTAssertFalse(got(e, t), t) }
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].monthlyHistory = (1...3).map { MonthRecord(monthIndex: $0, revenue: 100, profit: 10, cash: 100) }
            s.companies[i].status = .open
            s.companies[i].managerID = s.companies[i].staff[0].id
            s.companies[i].set("lastW", .object(["units": 25, "rev": 100]))
            s.week += 8
        }
        trophyCheck(&e)
        for t in ["q3", "emp", "mgr", "cust"] { XCTAssertTrue(got(e, t), t) }
        XCTAssertTrue(PlayerGoals.stepCelebrates("mgr", e.state))
        // Debt-free needs a loan that was held and then repaid.
        e.update { s, _, _ in var l = Loan(raw: [:]); l.id = s.makeID(); l.balance = 1; s.loans.append(l) }
        trophyCheck(&e)
        XCTAssertFalse(got(e, "debt0"))
        e.update { s, _, _ in s.loans = [] }
        trophyCheck(&e)
        XCTAssertTrue(got(e, "debt0"))
    }

    func testDeterministicAndSurvivesSaveReload() throws {
        var a = try setupGame().0, b = try setupGame().0
        days(&a, 20); days(&b, 20)
        XCTAssertEqual(a.pendingAwards(), b.pendingAwards())
        XCTAssertEqual(a.state, b.state)
        a.update { s, _, _ in Celebrations.add(&s, kind: "trophy", title: "T", detail: "d", art: "trophy.money", tier: 2) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("missions-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaveStore(directory: dir)
        try store.save(a.state, summary: store.summary(of: a.state, trades: a.data.catalog))
        let (data, events, marketing) = try GameEngine.loadResources()
        let back = GameEngine(state: try store.load(), data: data, events: events, marketing: marketing)
        XCTAssertEqual(back.pendingAwards(), a.pendingAwards())
        let info = try XCTUnwrap(back.pendingAwards().last)
        XCTAssertEqual(info.artKey, "trophy.money"); XCTAssertEqual(info.tier, 2); XCTAssertEqual(info.title, "T")
    }

    func testEarnedAwardsAndOldQueueEntriesStayAsTheyWere() throws {
        var (e, _) = try setupGame()
        e.update { s, _, _ in
            s.rest["ach28"] = .object(["cust": .object(["w": 1, "t": "old", "old": false])])
            s.rest["cele"] = .array([.object(["id": 1, "k": "goal", "t": "Old", "d": "", "r": "", "w": 0])])
        }
        trophyCheck(&e)
        XCTAssertTrue(got(e, "cust"))
        let old = try XCTUnwrap(e.pendingAwards().first)
        XCTAssertEqual(old.title, "Old"); XCTAssertEqual(old.artKey, "goal"); XCTAssertEqual(old.tier, 1)
    }

    func testDailyGoalsNoLongerOfferSetupGoals() throws {
        var (e, _) = try setupGame()
        for d in 0..<40 {
            let day = Date(timeIntervalSince1970: 1_800_000_000 + Double(d) * 86400)
            let g = try XCTUnwrap(e.dailyGoal(now: day))
            XCTAssertFalse(["start", "hire"].contains(g.id))
        }
    }
}
