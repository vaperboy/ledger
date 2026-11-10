import XCTest
import GameCore
import Countries
import Employees
import Finance
import Businesses
@testable import Simulation

final class CompanyCountryRulesTests: XCTestCase {
    private func abroad() throws -> (GameEngine, Int, String) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 11)
        let other = "DE"
        var made = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 900_000_000, why: "Test funds")
            let city = data.countries[other]!.cities[0].id
            if case .success(let id) = CompanySetup.create(&s, tradeID: "cafe", cityID: city, size: 1, name: "Abroad Cafe", countryCode: other, accountantID: nil, data: data, context: ctx) { made = id }
        }
        if made == 0 { throw XCTSkip("no foreign cafe") }
        return (e, made, other)
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
            social = World(state: s, data: data).country(s.companies[i]).employerOnCost(monthlyWage: 300_000)
            sev = Dismissal.dismiss(&s, companyID: id, staffID: m.id, reason: .redundancy, data: data)?.paid ?? 0
        }
        let weeks = LabourRules(code: "DE").termination(tenureWeeks: 60).weeks
        XCTAssertGreaterThan(weeks, 0)
        XCTAssertEqual(sev, wage * 12 / 52 * weeks * (1 + social), accuracy: 1)
    }
}
