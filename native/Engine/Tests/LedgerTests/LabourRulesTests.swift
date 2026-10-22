import XCTest
import GameCore
import Countries
import Employees
import Finance
import Businesses
import Simulation

/// Labour law as data (`labour` in country_traits.json): minimum wage, overtime, notice and severance, probation. The rules differ by
/// country only through the data, so these tests compare two countries' entries instead of expecting values written in the code.
/// Written by tracing the code (no Swift toolchain was available when they were added).
final class LabourRulesTests: XCTestCase {
    private func cafe(_ code: String, seed: Int = 5) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: code, playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 30_000_000) else { throw XCTSkip("no company") }
        return (e, id)
    }

    func testEveryCountryHasLabourData() throws {
        let book = try CountryBook.bundled()
        XCTAssertEqual(book.countries.count, 23)
        for c in book.countries {
            let r = LabourRules(country: c)
            XCTAssertTrue(r.hasMinimum, "\(c.code) has a minimum")
            XCTAssertTrue((30...50).contains(r.stdHours), "\(c.code) week")
            XCTAssertTrue((0...1).contains(r.overtimePremium), "\(c.code) overtime")
            XCTAssertFalse(r.summary(currency: Currency(country: c, rates: ExchangeRates())).isEmpty)
            // the minimum stays on the scale of the country's own median wage in the data
            let median = c.wageLevel * ReferenceEconomy.medianWage / c.fx
            XCTAssertLessThan(r.minMonthly, median * 1.2, "\(c.code) minimum against median")
            XCTAssertGreaterThan(r.minMonthly, median * 0.05, "\(c.code) minimum against median")
        }
    }

    func testNoticeAndSeveranceDifferByCountryData() {
        let uk = LabourRules(code: "UK"), de = LabourRules(code: "DE"), us = LabourRules(code: "US")
        // inside the probation of one and past the other
        let early = 60.0
        XCTAssertEqual(uk.termination(tenureWeeks: early).noticeWeeks, uk.probationNoticeWeeks)
        XCTAssertEqual(uk.termination(tenureWeeks: early).severanceWeeks, 0)
        XCTAssertGreaterThan(de.termination(tenureWeeks: early).noticeWeeks, de.probationNoticeWeeks)
        // five years in: more notice and severance in the one with the longer tenure scale
        let five = 5 * 52.0
        let a = uk.termination(tenureWeeks: five), b = de.termination(tenureWeeks: five)
        XCTAssertGreaterThan(a.severanceWeeks, 0)
        XCTAssertEqual(a.severanceWeeks, uk.severancePerYear * 5, accuracy: 1e-9)
        XCTAssertEqual(b.severanceWeeks, de.severancePerYear * 5, accuracy: 1e-9)
        XCTAssertNotEqual(a.noticeWeeks, b.noticeWeeks)
        XCTAssertEqual(b.noticeWeeks, min(de.noticeMax, de.noticeWeeks + de.noticePerYear * 5), accuracy: 1e-9)
        // at will: nothing is owed and there is no unfair dismissal claim
        XCTAssertEqual(us.termination(tenureWeeks: five).weeks, 0)
        XCTAssertFalse(us.canClaimUnfairDismissal(tenureWeeks: five))
        XCTAssertTrue(de.canClaimUnfairDismissal(tenureWeeks: five))
        XCTAssertFalse(de.canClaimUnfairDismissal(tenureWeeks: 1), "not in probation")
        // with cause or already on notice nothing is due
        XCTAssertEqual(de.termination(tenureWeeks: five, withCause: true).weeks, 0)
        XCTAssertEqual(de.termination(tenureWeeks: five, onNotice: true).weeks, 0)
    }

    func testOvertimeIsPaidAboveTheStandardWeek() {
        let fr = LabourRules(code: "FR"), uk = LabourRules(code: "UK"), us = LabourRules(code: "US")
        XCTAssertEqual(us.overtimeHours(worked: 40, contracted: 37.5), 0)
        XCTAssertEqual(us.overtimeHours(worked: 46, contracted: 37.5), 6, accuracy: 1e-9)
        let pay = us.overtimePay(monthlyWage: 100_000, contracted: 37.5, worked: 46)
        XCTAssertEqual(pay, 100_000 * 12 / 52 / 37.5 * 6 * (1 + us.overtimePremium), accuracy: 1e-6)
        XCTAssertGreaterThan(us.overtimePremium, uk.overtimePremium, "the premium comes from the data")
        // a full-timer on the agreed 37.5 hour week gets no premium for the agreed hours in a shorter-week country
        XCTAssertEqual(fr.overtimeThreshold(contracted: 37.5), 37.5)
        XCTAssertEqual(fr.overtimeHours(worked: 37.5, contracted: 37.5), 0)
        // part-timers: premium only above the standard week
        XCTAssertEqual(us.overtimeHours(worked: 30, contracted: 20), 0)
        XCTAssertGreaterThan(us.overtimeHours(worked: 45, contracted: 20), 0)
        // tiredness starts no later than 40 hours
        XCTAssertLessThanOrEqual(us.tirednessThreshold(contracted: 37.5), 40)
    }

    func testMinimumWageIsPerWeekAndInflationLinked() {
        let de = LabourRules(code: "DE")
        let full = de.minimumMonthly(hours: de.stdHours, rate: 10, inflation: 0, week: 0)
        XCTAssertEqual(full, de.minMonthly * 10, accuracy: 1e-6)
        XCTAssertEqual(de.minimumMonthly(hours: de.stdHours / 2, rate: 10, inflation: 0, week: 0), full / 2, accuracy: 1e-6)
        XCTAssertGreaterThan(de.minimumMonthly(hours: de.stdHours, rate: 10, inflation: 0.03, week: 104), full)
        XCTAssertEqual(LabourRules().minimumMonthly(hours: 40, rate: 1, inflation: 0, week: 0), 0, "no entry, no minimum")
    }

    func testHiringNeverPaysUnderTheMinimum() throws {
        var (e, id) = try cafe("UK")
        let w = World(state: e.state, data: e.data)
        let co = try XCTUnwrap(e.state.company(id))
        let minimum = w.minimumWage(co)
        XCTAssertGreaterThan(minimum, 0)
        var hired = 0
        for _ in 0..<40 {
            var pid = 0
            e.update { s, d, _ in let co = s.company(id); pid = Hiring.generateCandidate(role: "barista", company: co, tier: "mid", state: &s, data: d).id }
            if e.hire(personID: pid, companyID: id, monthlyWage: 1) == .ok { hired += 1 }
        }
        if hired == 0 { throw XCTSkip("nobody took the minimum") }
        let staff = try XCTUnwrap(e.state.company(id)).staff
        XCTAssertEqual(staff.count, hired)
        for m in staff { XCTAssertGreaterThanOrEqual(m.monthlyWage, minimum - 0.5) }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testRaiseAndPayLiftKeepPayAtTheMinimum() throws {
        var (e, id) = try cafe("UK", seed: 7)
        var pid = 0
        e.update { s, d, _ in let co = s.company(id); pid = Hiring.generateCandidate(role: "barista", company: co, tier: "mid", state: &s, data: d).id }
        guard e.hire(personID: pid, companyID: id, monthlyWage: e.state.people[pid]!.askingMonthlyWage * 1.5) == .ok else { throw XCTSkip("refused") }
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            var st = s.companies[i].staff
            st[0].monthlyWage = 1
            s.companies[i].staff = st
        }
        for _ in 0..<14 { e.nextDay() }
        let w = World(state: e.state, data: e.data)
        let co = try XCTUnwrap(e.state.company(id))
        let m = try XCTUnwrap(co.staff.first { $0.id == pid })
        XCTAssertGreaterThanOrEqual(m.monthlyWage, w.minimumWage(co, hours: m.weeklyHours ?? 37.5) * 0.99, "pay under the minimum is lifted")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testDismissalPaysByTenureAndOneHelperServesAllPaths() throws {
        var (e, id) = try cafe("UK", seed: 9)
        var pid = 0
        e.update { s, d, _ in let co = s.company(id); pid = Hiring.generateCandidate(role: "barista", company: co, tier: "mid", state: &s, data: d).id }
        guard e.hire(personID: pid, companyID: id, monthlyWage: e.state.people[pid]!.askingMonthlyWage * 1.5) == .ok else { throw XCTSkip("refused") }
        let w = World(state: e.state, data: e.data)
        let co = try XCTUnwrap(e.state.company(id))
        let m = try XCTUnwrap(co.staff.first { $0.id == pid })
        // make them a long-serving worker so the tenure rules apply
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            var st = s.companies[i].staff
            st[0].hiredWeek = s.week - 5 * 52
            s.companies[i].staff = st
        }
        let senior = try XCTUnwrap(e.state.company(id)).staff[0]
        let expected = w.terminationCost(co, monthlyWage: senior.monthlyWage, tenureWeeks: 5 * 52)
        XCTAssertGreaterThan(expected, w.terminationCost(co, monthlyWage: m.monthlyWage, tenureWeeks: 1), "more tenure, more pay")
        let preview = e.layoffPreview(companyID: id, count: 1)
        XCTAssertEqual(preview.severance, expected, accuracy: 1, "the layoff preview uses the same helper")
        let before = try XCTUnwrap(e.state.company(id)).cash
        let r = try XCTUnwrap(e.dismissStaff(companyID: id, staffID: pid))
        XCTAssertEqual(r.severance, expected, accuracy: 1)
        XCTAssertLessThan(try XCTUnwrap(e.state.company(id)).cash, before)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testCardTextHasASeparateLinePerRule() throws {
        let book = try CountryBook.bundled()
        let de = try XCTUnwrap(book["DE"]), us = try XCTUnwrap(book["US"])
        let a = LabourRules(country: de).summary(currency: Currency(country: de, rates: ExchangeRates()))
        let b = LabourRules(country: us).summary(currency: Currency(country: us, rates: ExchangeRates()))
        XCTAssertEqual(a.map { $0.label }, b.map { $0.label })
        XCTAssertNotEqual(a.map { $0.value }, b.map { $0.value })
        XCTAssertEqual(b.first { $0.label == "Probation" }?.value, "At will")
    }
}
