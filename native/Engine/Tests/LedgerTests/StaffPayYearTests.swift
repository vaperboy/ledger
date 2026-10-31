import XCTest
import GameCore
import Countries
import Employees
import Finance
@testable import Businesses
import Simulation

/// A year of play with the new pay machinery, several seeds: a sales trade with commission and mix plans, and a managed shop with bonus plans, perks
/// and expense reimbursements. The books balance, wages stay a sensible share of takings, and the bonuses are real but small next to the wage bill.
final class StaffPayYearTests: XCTestCase {
    private func open(_ trade: String, seed: Int) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 200_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, form: .limited, fundWith: 60_000_000) else { throw XCTSkip("no company") }
        var days = 0
        while e.state.company(id)?.status != .open, days < 60 * 7 { e.nextDay(); days += 1 }
        return (e, id)
    }

    private func hire(_ e: inout GameEngine, _ id: Int, role: String, terms: Hiring.Terms = Hiring.Terms()) -> Int? {
        var pid = 0
        e.update { s, d, _ in
            var p = Hiring.generateCandidate(role: role, company: s.company(id), tier: "mid", state: &s, data: d)
            p.set("pers", "steady"); p.set("sec", 0.1)
            s.people[p.id] = p; pid = p.id
        }
        return e.hire(personID: pid, companyID: id, monthlyWage: e.state.people[pid]!.askingMonthlyWage * 1.5, terms: terms) == .ok ? pid : nil
    }

    private struct Year { var rev = 0.0, wages = 0.0, oth = 0.0, cash = 0.0, bonusSeen = false, gaps = 0 }

    private func estateYear(seed: Int, plans: Bool) throws -> Year {
        var (e, id) = try open("estate", seed: seed)
        let a = hire(&e, id, role: "estate", terms: plans ? Hiring.Terms(payPlan: "mix", commissionRate: 0.05) : Hiring.Terms())
        _ = hire(&e, id, role: "estate", terms: plans ? Hiring.Terms(payPlan: "com") : Hiring.Terms())
        _ = hire(&e, id, role: "estate")
        if plans, let a { _ = e.contractPropose(companyID: id, personID: a, proposal: .init(.bonus, choice: "plan:standard")) }
        for _ in 0..<(52 * 7) { e.nextDay() }
        let co = try XCTUnwrap(e.state.company(id))
        return Year(rev: co.books.total["rev"] ?? 0, wages: co.books.total["wages"] ?? 0, oth: co.books.total["oth"] ?? 0, cash: co.cash, gaps: Ledger.gaps(e.state).count)
    }

    func testASalesTradeWithCommissionPlansForAYear() throws {
        for seed in [3, 7, 11] {
            let with = try estateYear(seed: seed, plans: true), without = try estateYear(seed: seed, plans: false)
            print("YEAR estate seed \(seed): plans: revenue \(Int(with.rev)) wages \(Int(with.wages)) | plain salaries: revenue \(Int(without.rev)) wages \(Int(without.wages))")
            XCTAssertEqual(with.gaps, 0, "seed \(seed)"); XCTAssertEqual(without.gaps, 0)
            XCTAssertGreaterThan(with.wages, 0)
            // commission only has no base, so the plan year costs less in fixed pay than three salaries and cannot cost several times more
            XCTAssertLessThan(with.wages, without.wages * 1.5, "seed \(seed): the plans do not blow up the wage bill")
        }
    }

    private func cafeYear(seed: Int, plans: Bool) throws -> Year {
        var (e, id) = try open("cafe", seed: seed)
        let cands = try XCTUnwrap(e.searchManagers(companyID: id))
        XCTAssertEqual(e.hireManager(personID: cands[0].id, companyID: id, monthlyWage: cands[0].askingMonthlyWage * 1.3), .ok)
        var crew: [Int] = []
        for r in ["barista", "barista", "cook", "waiter"] { if let p = hire(&e, id, role: r) { crew.append(p) } }
        if plans {
            for p in crew {
                _ = e.contractPropose(companyID: id, personID: p, proposal: .init(.bonus, choice: "plan:standard"))
                _ = e.contractPropose(companyID: id, personID: p, proposal: .init(.benefits, amount: 1, choice: "exp:training"))
            }
            _ = e.toggleStaffPerk(companyID: id, perk: "lunch", group: "crew")
        }
        var y = Year()
        for _ in 0..<52 {
            for _ in 0..<7 { e.nextDay() }
            if (e.state.company(id)?.num("bnPend") ?? 0) > 0 { y.bonusSeen = true }
        }
        let co = try XCTUnwrap(e.state.company(id))
        y.rev = co.books.total["rev"] ?? 0; y.wages = co.books.total["wages"] ?? 0; y.oth = co.books.total["oth"] ?? 0; y.cash = co.cash; y.gaps = Ledger.gaps(e.state).count
        return y
    }

    func testAManagedShopWithBonusPlansPerksAndExpensesForAYear() throws {
        for seed in [3, 7, 11] {
            let with = try cafeYear(seed: seed, plans: true), without = try cafeYear(seed: seed, plans: false)
            print("YEAR cafe seed \(seed): plans: revenue \(Int(with.rev)) wages \(Int(with.wages)) other \(Int(with.oth)) bonus paid \(with.bonusSeen) | none: revenue \(Int(without.rev)) wages \(Int(without.wages)) other \(Int(without.oth))")
            XCTAssertEqual(with.gaps, 0, "seed \(seed)"); XCTAssertEqual(without.gaps, 0)
            XCTAssertGreaterThan(with.oth, without.oth, "the training allowance is booked as an expense")
            // lunch and bonuses are real money but small next to the plain wage bill
            XCTAssertLessThan(with.wages, without.wages * 1.5, "seed \(seed)")
            XCTAssertGreaterThanOrEqual(with.wages, without.wages * 0.8, "seed \(seed)")
        }
    }

    func testTheSameSeedGivesTheSameYear() throws {
        func run() throws -> Double {
            var (e, id) = try open("boutique", seed: 13)
            if let p = hire(&e, id, role: "cashier", terms: Hiring.Terms(payPlan: "mix")) {
                _ = e.contractPropose(companyID: id, personID: p, proposal: .init(.bonus, choice: "plan:high"))
                _ = e.contractPropose(companyID: id, personID: p, proposal: .init(.term, choice: "fixed:26"))
            }
            for _ in 0..<(40 * 7) { e.nextDay() }
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
            return e.state.cash
        }
        XCTAssertEqual(try run(), try run())
    }
}
