import XCTest
import GameCore
import Countries
import Employees
import Finance
import Businesses
@testable import Simulation

/// A foreign company follows the rules of its OWN country: owner-salary withholding, severance social charge, VAT, corporate tax.
/// Written by tracing the code (no Swift toolchain was available when they were added).
final class CompanyCountryRulesTests: XCTestCase {
    private func abroad() throws -> (GameEngine, Int, String) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 11)
        let other = "DE"
        var made = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 900_000_000, why: "Test funds")
            let city = data.countries[other]!.cities[0].id
            if case .success(let id) = CompanySetup.create(&s, tradeID: "cafe", cityID: city, form: .limited, size: 1, name: "Abroad Cafe", countryCode: other, accountantID: nil, data: data, context: ctx) { made = id }
        }
        if made == 0 { throw XCTSkip("no foreign cafe") }
        return (e, made, other)
    }

    func testOwnerSalaryWithholdingUsesCompanyCountry() throws {
        var (e, id, code) = try abroad()
        var expected = 0.0, home = 0.0
        e.update { s, data, ctx in
            let i = s.companyIndex(id)!
            s.companies[i].ownerMonthlySalary = 4_000_000
            Ledger.moveRaw(&s, .company(id), 1_000_000_000 - s.companies[i].cash)
            expected = Taxes.personalIncomeTax(4_000_000 * 12, kind: .wage, in: ctx.country(of: s.companies[i], s)) / 12
            home = Taxes.personalIncomeTax(4_000_000 * 12, kind: .wage, in: ctx.homeCountry(s)) / 12
            let t = Payday.dayNumber(week: s.week, day: s.day)
            // a company still being set up pays no one, and a fresh payroll book counts this month's owner pay as already made
            s.companies[i].status = .open
            var cfg = Payday.config(s.companies[i], today: t)
            cfg.ownerPaidMonth = Payday.monthNumber(t) - 1
            s.companies[i].set("pr29", cfg.json)
            _ = Payday.runPayroll(&s, i, how: .manual, today: t, data: data, context: ctx)
        }
        XCTAssertEqual(code, "DE")
        XCTAssertGreaterThan(abs(expected - home), 1, "the two countries tax differently, so the test can tell them apart")
        XCTAssertEqual(e.state.tax.withheld, expected, accuracy: 1, "withholding follows the country the salary is paid in")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testRulesComeFromCompanyCountryNotHome() throws {
        let (e, id, code) = try abroad()
        let w = World(state: e.state, data: e.data)
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(w.country(co).code, code)
        let bd = try XCTUnwrap(e.data.catalog["cafe"])
        XCTAssertEqual(MonthEnd.taxRate(co, bd, w.country(co)), w.country(co).corporateTax)
        let r = Vat.rate(co, bd, w)
        XCTAssertTrue(r == 0 || r == w.country(co).vat.rate(for: bd.vatCategory))
    }

    func testSeveranceUsesCompanyCountrySocial() throws {
        var (e, id, _) = try abroad()
        var sev = 0.0, social = 0.0, wage = 0.0
        e.update { s, data, _ in
            let i = s.companyIndex(id)!
            var m = StaffMember(raw: [:])
            m.id = s.makeID(); m.role = "waiter"; m.monthlyWage = 300_000; m.hiredWeek = s.week - 60
            s.companies[i].staff.append(m)
            wage = m.monthlyWage
            social = World(state: s, data: data).country(s.companies[i]).employerSocial
            sev = Hiring.fire(m.id, from: id, state: &s, data: data)
        }
        let weeks = LabourRules(code: "DE").termination(tenureWeeks: 60).weeks
        XCTAssertGreaterThan(weeks, 0)
        XCTAssertEqual(sev, wage * 12 / 52 * weeks * (1 + social), accuracy: 1)
    }
}
