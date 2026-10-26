import XCTest
import GameCore
import Countries
import Employees
import Finance
@testable import Businesses
import Simulation

/// Commission and mix pay as data on roles and trades, and the pay plan in the hire offer.
final class PayPlansTests: XCTestCase {
    private func shop(_ trade: String, seed: Int = 5) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 80_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, form: .limited, fundWith: 30_000_000) else { throw XCTSkip("no company") }
        var days = 0
        while e.state.company(id)?.status != .open, days < 60 * 7 { e.nextDay(); days += 1 }
        return (e, id)
    }

    private func candidate(_ e: inout GameEngine, _ id: Int, role: String, sec: Double = 0.1) -> Int {
        var pid = 0
        e.update { s, d, _ in
            var p = Hiring.generateCandidate(role: role, company: s.company(id), tier: "mid", state: &s, data: d)
            p.set("pers", "steady"); p.set("sec", sec)
            s.people[p.id] = p; pid = p.id
        }
        return pid
    }

    func testTheOriginalPlanNumbersAreUnchanged() {
        XCTAssertEqual(PayPlans.mode("mix"), PayPlans.Mode(baseShare: 0.6, defaultRate: 0.03))
        XCTAssertEqual(PayPlans.mode("com"), PayPlans.Mode(baseShare: 0, defaultRate: 0.06))
        XCTAssertEqual(PayPlans.rateSteps, [0.02, 0.03, 0.05, 0.08, 0.12])
        XCTAssertNil(PayPlans.mode("fix"))
    }

    func testEligibilityIsDataPerRoleAndTrade() throws {
        let sales = try GameData.bundled().catalog.tables.salesRoles
        XCTAssertTrue(PayPlans.eligible(role: "estate", trade: "estate", salesRoles: sales), "general selling jobs everywhere")
        XCTAssertTrue(PayPlans.eligible(role: "cashier", trade: "boutique", salesRoles: sales))
        XCTAssertTrue(PayPlans.eligible(role: "cashier", trade: "hardware", salesRoles: sales))
        XCTAssertFalse(PayPlans.eligible(role: "cashier", trade: "grocery", salesRoles: sales), "a supermarket checkout does not sell on commission")
        XCTAssertTrue(PayPlans.eligible(role: "hr", trade: "staffing", salesRoles: sales))
        XCTAssertTrue(PayPlans.eligible(role: "banker", trade: "bank", salesRoles: sales))
        XCTAssertFalse(PayPlans.eligible(role: "banker", trade: "insco", salesRoles: sales))
        XCTAssertEqual(PayPlans.modes(role: "waiter", trade: "restaurant", salesRoles: sales), [])
    }

    func testAShopAssistantCanBePutOnCommissionOnlyInABoutiqueButNotInAGrocery() throws {
        var (e, id) = try shop("boutique")
        let pid = candidate(&e, id, role: "cashier")
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: e.state.people[pid]!.askingMonthlyWage * 1.5), .ok)
        XCTAssertEqual(e.contractTopics(companyID: id, personID: pid).first { $0.topic == .payBasis }?.available, true)
        guard case .agreed = e.contractPropose(companyID: id, personID: pid, proposal: .init(.payBasis, amount: 0.05, choice: "com")) else { return XCTFail("com") }
        let m = e.state.company(id)!.staff.first { $0.id == pid }!
        XCTAssertEqual(m.monthlyWage, 0, "commission only means no base")
        XCTAssertEqual(m.commissionMode, "com"); XCTAssertEqual(m.commissionRate, 0.05, accuracy: 1e-12)
        XCTAssertTrue(m.flag("ppx"), "counts as a seller while on a plan")
        _ = e.contractPropose(companyID: id, personID: pid, proposal: .init(.payBasis, choice: "fix"))
        XCTAssertFalse(e.state.company(id)!.staff.first { $0.id == pid }!.flag("ppx"))
        XCTAssertGreaterThan(e.state.company(id)!.staff.first { $0.id == pid }!.monthlyWage, 0)
    }

    func testCommissionIsPaidOnTheRevenueAttributedToAnExtraSeller() throws {
        var (e, id) = try shop("boutique")
        let pid = candidate(&e, id, role: "cashier")
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: e.state.people[pid]!.askingMonthlyWage * 1.5, terms: Hiring.Terms(payPlan: "com", commissionRate: 0.08)), .ok)
        for _ in 0..<28 { e.nextDay() }
        let m = e.state.company(id)!.staff.first { $0.id == pid }!
        XCTAssertEqual(m.commissionMode, "com")
        XCTAssertGreaterThan(m.num("lastComm"), 0, "commission accrues on what they sold")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testThePlanIsPartOfTheHireOffer() throws {
        var (e, id) = try shop("estate")
        let a = candidate(&e, id, role: "estate"), b = candidate(&e, id, role: "estate"), c = candidate(&e, id, role: "estate")
        let wage = e.state.people[a]!.askingMonthlyWage * 1.5
        XCTAssertEqual(e.hire(personID: a, companyID: id, monthlyWage: wage, terms: Hiring.Terms(payPlan: "mix", commissionRate: 0.05)), .ok)
        XCTAssertEqual(e.hire(personID: b, companyID: id, monthlyWage: e.state.people[b]!.askingMonthlyWage * 1.5, terms: Hiring.Terms(payPlan: "com")), .ok)
        XCTAssertEqual(e.hire(personID: c, companyID: id, monthlyWage: e.state.people[c]!.askingMonthlyWage * 1.5), .ok)
        let st = e.state.company(id)!.staff
        let ma = st.first { $0.id == a }!, mb = st.first { $0.id == b }!, mc = st.first { $0.id == c }!
        XCTAssertEqual(ma.commissionMode, "mix"); XCTAssertEqual(ma.commissionRate, 0.05, accuracy: 1e-12); XCTAssertEqual(ma.monthlyWage, wage, "the offer is the base salary")
        XCTAssertEqual(mb.commissionMode, "com"); XCTAssertEqual(mb.commissionRate, 0.06, accuracy: 1e-12, "the plan's usual rate"); XCTAssertEqual(mb.monthlyWage, 0)
        XCTAssertNil(mc.commissionMode, "a plain offer keeps a plain salary")
        // a job without a plan ignores one
        var (e2, id2) = try shop("cafe")
        let w = candidate(&e2, id2, role: "waiter")
        XCTAssertEqual(e2.hire(personID: w, companyID: id2, monthlyWage: e2.state.people[w]!.askingMonthlyWage * 1.5, terms: Hiring.Terms(payPlan: "com")), .ok)
        XCTAssertNil(e2.state.company(id2)!.staff.first { $0.id == w }!.commissionMode)
    }

    func testSomeoneWhoWantsSecurityMayRefuseCommissionOnlyAndStaysOnTheMarket() throws {
        var (e, id) = try shop("estate")
        var refused = false
        for k in 0..<12 where !refused {
            let pid = candidate(&e, id, role: "estate", sec: 1)
            let r = e.hire(personID: pid, companyID: id, monthlyWage: e.state.people[pid]!.askingMonthlyWage * 1.5, terms: Hiring.Terms(payPlan: "com"))
            if r == .planRefused {
                refused = true
                XCTAssertEqual(e.state.people[pid]?.employerID, 0, "still on the market")
                XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: e.state.people[pid]!.askingMonthlyWage * 1.5, terms: Hiring.Terms(payPlan: "mix")), .ok, "a mixed plan is fine \(k)")
            }
        }
        XCTAssertTrue(refused, "6 in 10 refuse; none of twelve is not plausible")
    }

    func testDeterministicFromTheSameSeed() throws {
        func run() throws -> Double {
            var (e, id) = try shop("boutique", seed: 21)
            let pid = candidate(&e, id, role: "cashier")
            _ = e.hire(personID: pid, companyID: id, monthlyWage: e.state.people[pid]!.askingMonthlyWage * 1.5, terms: Hiring.Terms(payPlan: "mix"))
            for _ in 0..<35 { e.nextDay() }
            return e.state.cash
        }
        XCTAssertEqual(try run(), try run())
    }
}
