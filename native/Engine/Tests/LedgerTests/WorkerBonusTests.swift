import XCTest
import GameCore
import Countries
import Employees
import Finance
@testable import Businesses
import Simulation

/// Bonus plans for ordinary staff: judged with the manager's targets machinery, paid through payroll with the employer's charges, set in the contract
/// discussion, visible in the profile, saved, and the books stay balanced.
final class WorkerBonusTests: XCTestCase {
    private func shop(seed: Int = 5, trade: String = "cafe", country: String = "UK") throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: country, playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 80_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, form: .limited, fundWith: 30_000_000) else { throw XCTSkip("no company") }
        var days = 0
        while e.state.company(id)?.status != .open, days < 60 * 7 { e.nextDay(); days += 1 }
        return (e, id)
    }

    private func hire(_ e: inout GameEngine, _ id: Int, role: String = "barista", skill: Double = 60) -> Int {
        var pid = 0
        e.update { s, d, _ in
            var p = Hiring.generateCandidate(role: role, company: s.company(id), tier: "mid", state: &s, data: d)
            p.set("pers", "steady"); p.set("sec", 0.1); p.skill = skill
            s.people[p.id] = p; pid = p.id
        }
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: e.state.people[pid]!.askingMonthlyWage * 1.5), .ok)
        e.update { s, _, _ in var f = s.company(id)!.value("flags"); f["noquit"] = 1; s.companies[s.companyIndex(id)!].set("flags", f) }
        return pid
    }

    func testThePlanIsSetInTheContractTalkAndWritesNothingElse() throws {
        var (e, id) = try shop()
        let pid = hire(&e, id)
        XCTAssertNil(e.state.company(id)?.staff.first { $0.id == pid }?.raw["bp"], "no key until a plan is set")
        let t = e.contractTopics(companyID: id, personID: pid).first { $0.topic == .bonus }
        XCTAssertEqual(t?.available, true)
        let choices = e.contractChoices(companyID: id, personID: pid, topic: .bonus)
        XCTAssertEqual(choices.map { $0.id }, ["plan:none", "plan:standard", "plan:high"])
        e.update { s, _, _ in s.companies[s.companyIndex(id)!].raw.removeValue(forKey: "tg58") }
        let pv = e.contractPreview(companyID: id, personID: pid, proposal: .init(.bonus, choice: "plan:standard"))
        XCTAssertGreaterThan(pv.costPerMonth, 0, "the likely cost is shown before it is agreed")
         XCTAssertFalse(pv.risks.isEmpty, "no targets are set, which the preview says")
        guard case .agreed = e.contractPropose(companyID: id, personID: pid, proposal: .init(.bonus, choice: "plan:standard")) else { return XCTFail("plan") }
        let prof = try XCTUnwrap(e.staffProfile(companyID: id, staffID: pid))
        XCTAssertEqual(prof.bonusPlan, "Standard plan")
        guard case .agreed = e.contractPropose(companyID: id, personID: pid, proposal: .init(.bonus, choice: "plan:none")) else { return XCTFail("off") }
        XCTAssertNil(e.state.company(id)?.staff.first { $0.id == pid }?.raw["bp"])
    }

    func testTargetsMetPayThroughPayrollWithEmployerChargesAndMissedPayNothing() throws {
        var (e, id) = try shop()
        let a = hire(&e, id), b = hire(&e, id)
        _ = e.contractPropose(companyID: id, personID: a, proposal: .init(.bonus, choice: "plan:standard"))
        let wageA = e.state.company(id)!.staff.first { $0.id == a }!.monthlyWage
        // two of three targets met: 2 x 2% of the monthly pay, for the one on a plan only
        e.update { s, _, _ in WorkerBonus.monthEnd(&s, s.companyIndex(id)!, hits: 2) }
        let co = e.state.company(id)!
        XCTAssertEqual(co.num("bnPend"), wageA * 0.04, accuracy: 1e-6, "2 targets of 2% each; no month on record yet, so no performance reward")
        XCTAssertGreaterThan(co.num("bnPend"), 0)
        XCTAssertEqual(co.staff.first { $0.id == b }?.num("bnM") ?? 0, 0)
        // paid through the weekly payroll accrual with the employer's charges
        let pend = co.num("bnPend")
        let country = World(state: e.state, data: e.data).country(co)
        let wages0 = co.books.week["wages"] ?? 0
        e.update { s, d, _ in _ = CompanyCosts.wages(&s, companyIndex: s.companyIndex(id)!, d.catalog[s.company(id)!.type]!, data: d) }
        let after = e.state.company(id)!
        XCTAssertNil(after.raw["bnPend"], "taken into payroll once")
        let routine = after.lastWages
        XCTAssertEqual((after.books.week["wages"] ?? 0) - wages0, routine + pend * country.employerCostFactor, accuracy: 1e-6)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        // a month with no target met pays no target bonus
        e.update { s, _, _ in WorkerBonus.monthEnd(&s, s.companyIndex(id)!, hits: 0) }
        XCTAssertLessThan(e.state.company(id)!.num("bnPend"), pend, "no target bonus when none was met")
        // the average that counts as pay follows the months
        XCTAssertGreaterThan(e.state.company(id)!.staff.first { $0.id == a }!.num("bnEma"), 0)
    }

    func testNoPerformanceRewardInAMonthWithALoss() throws {
        var (e, id) = try shop()
        let a = hire(&e, id, skill: 90), _ = hire(&e, id, skill: 30)
        _ = e.contractPropose(companyID: id, personID: a, proposal: .init(.bonus, choice: "plan:high"))
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].monthlyHistory = [MonthRecord(monthIndex: 1, revenue: 1000, profit: -5000, cash: 0)]
            WorkerBonus.monthEnd(&s, i, hits: nil)
        }
        XCTAssertNil(e.state.company(id)!.raw["bnPend"], "a loss month pays no reward")
    }

    func testYearEndPaysWhenTheBudgetIsMetProRataToService() throws {
        var (e, id) = try shop()
        let a = hire(&e, id)
        _ = e.contractPropose(companyID: id, personID: a, proposal: .init(.bonus, choice: "plan:high"))
        let wage = e.state.company(id)!.staff.first { $0.id == a }!.monthlyWage
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            var st = s.companies[i].staff; let k = st.firstIndex { $0.id == a }!; st[k].hiredWeek = s.week - 26; s.companies[i].staff = st
            WorkerBonus.yearEnd(&s, i, budgetMet: false)
        }
        XCTAssertNil(e.state.company(id)!.raw["bnPend"], "budget missed: nothing")
        e.update { s, _, _ in WorkerBonus.yearEnd(&s, s.companyIndex(id)!, budgetMet: true) }
        XCTAssertEqual(e.state.company(id)!.num("bnPend"), wage * 1.0 * 0.5, accuracy: 1e-6, "one month of pay for half a year served")
    }

    func testPlanAndPendingBonusSurviveASave() throws {
        var (e, id) = try shop()
        let a = hire(&e, id)
        _ = e.contractPropose(companyID: id, personID: a, proposal: .init(.bonus, choice: "plan:standard"))
        e.update { s, _, _ in WorkerBonus.monthEnd(&s, s.companyIndex(id)!, hits: 3) }
        let back = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(e.state))
        XCTAssertEqual(back.company(id)?.num("bnPend"), e.state.company(id)?.num("bnPend"))
        XCTAssertEqual(back.company(id)?.staff.first { $0.id == a }.flatMap { WorkerBonus.level(of: $0)?.id }, "standard")
    }
}
