import XCTest
import GameCore
import Countries
import Employees
import Finance
@testable import Businesses
import Simulation

/// Staff in a company with a manager still make hours and promotion requests; they go to the manager, who decides inside their authority, and
/// reach the owner (the same Inbox flow) only beyond it. Pay and fixed-salary talks stay with the manager's monthly pay review.
final class ManagedRequestsTests: XCTestCase {
    private func managedShop(level: Int, pay: Double = 0, seed: Int = 5) throws -> (GameEngine, Int, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 80_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 30_000_000) else { throw XCTSkip("no company") }
        var days = 0
        while e.state.company(id)?.status != .open, days < 60 * 7 { e.nextDay(); days += 1 }
        let cands = try XCTUnwrap(e.searchManagers(companyID: id))
        XCTAssertEqual(e.hireManager(personID: cands[0].id, companyID: id, monthlyWage: cands[0].askingMonthlyWage * 1.3), .ok)
        e.setManagerAuthority(companyID: id, level: level, pay: pay)
        var pid = 0
        e.update { s, d, _ in
            var p = Hiring.generateCandidate(role: "barista", company: s.company(id), tier: "mid", state: &s, data: d)
            p.set("pers", "steady"); p.set("sec", 0.1)
            s.people[p.id] = p; pid = p.id
        }
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: e.state.people[pid]!.askingMonthlyWage * 1.5), .ok)
        e.update { s, _, _ in
            let ci = s.companyIndex(id)!
            var f = s.companies[ci].value("flags"); f["noquit"] = 1; s.companies[ci].set("flags", f)
            var st = s.companies[ci].staff; for k in st.indices { st[k].tiredness = 70 }; s.companies[ci].staff = st
        }
        return (e, id, pid)
    }

    func testTheTriggerIsStillDeterministicAndOnlyHoursAndPromotionAreRaisedUnderAManager() throws {
        let (e, id, pid) = try managedShop(level: 2)
        let co = e.state.company(id)!, m = co.staff.first { $0.id == pid }!, n = e.state.people[pid]!
        XCTAssertEqual(StaffTalks.nextTalk(m, n, company: co, gap: 0.3, tenure: 400, week: e.state.week + 200, salesRoles: e.salesRoles), .hoursAsk(staffID: pid),
                       "a big pay gap raises no pay ask while a manager runs the company: their pay review does")
        let again = StaffTalks.nextTalk(m, n, company: co, gap: 0.3, tenure: 400, week: e.state.week + 200, salesRoles: e.salesRoles)
        XCTAssertEqual(again, .hoursAsk(staffID: pid))
    }

    func testAManagerWithFullControlGrantsAFairRequestAtOnce() throws {
        var (e, id, pid) = try managedShop(level: 2)
        let msgs0 = e.openDecisions.count
        e.update { s, d, _ in ContractTalk.employeeAsks(&s, companyIndex: s.companyIndex(id)!, staffID: pid, topic: .hours, data: d) }
        XCTAssertLessThan(e.state.company(id)!.staff.first { $0.id == pid }!.weeklyHours ?? StaffModel.fullWeekHours, StaffModel.fullWeekHours)
        XCTAssertEqual(e.openDecisions.count, msgs0, "nothing reaches the owner")
        XCTAssertNil(e.contractTalk(personID: pid))
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testAManagerWhoAsksYouFirstPassesItOnSayingWho() throws {
        var (e, id, pid) = try managedShop(level: 0)
        e.update { s, d, _ in ContractTalk.employeeAsks(&s, companyIndex: s.companyIndex(id)!, staffID: pid, topic: .hours, data: d) }
        XCTAssertNil(e.state.company(id)!.staff.first { $0.id == pid }!.weeklyHours, "unchanged")
        let msg = try XCTUnwrap(e.openDecisions.first { $0.actionID == "staffx" })
        let mgr = e.state.people[e.state.company(id)!.managerID!]!.name
        XCTAssertTrue(msg.str("body").contains(mgr), msg.str("body"))
        XCTAssertNotNil(e.contractTalk(personID: pid))
        // the owner then answers through the same flow
        XCTAssertTrue(e.answer(messageID: msg.id, option: 0))
        XCTAssertNotNil(e.state.company(id)!.staff.first { $0.id == pid }!.weeklyHours)
    }

    func testPayTalksStayWithTheManagersReviewAndNothingIsAskedOfTheOwner() throws {
        var (e, id, _) = try managedShop(level: 2)
        for _ in 0..<(26 * 7) { e.nextDay() }
        XCTAssertFalse(e.openDecisions.contains { ["payask", "fixask"].contains($0.value("data")["t"].string) }, "no pay ask while a manager is in charge")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        _ = id
    }

    func testDeterministicFromTheSameSeed() throws {
        func run() throws -> (Double, Int) {
            var (e, _, _) = try managedShop(level: 1, pay: 1_000_000, seed: 8)
            for _ in 0..<(20 * 7) { e.nextDay() }
            return (e.state.cash, e.openDecisions.count)
        }
        let a = try run(), b = try run()
        XCTAssertEqual(a.0, b.0); XCTAssertEqual(a.1, b.1)
    }
}
