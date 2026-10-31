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
        // DE: severance is not automatically due (owner-supplied 2026 rules); notice is by service (5 years = 2 months)
        XCTAssertEqual(b.severanceWeeks, 0)
        XCTAssertNotEqual(a.noticeWeeks, b.noticeWeeks)
        XCTAssertEqual(b.noticeWeeks, 8.7, accuracy: 1e-9)
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
        let full = de.minimumMonthly(hours: de.stdHours, rate: 10, inflationIndex: 1)
        XCTAssertEqual(full, de.minMonthly * 10, accuracy: 1e-6)
        XCTAssertEqual(de.minimumMonthly(hours: de.stdHours / 2, rate: 10, inflationIndex: 1), full / 2, accuracy: 1e-6)
        XCTAssertGreaterThan(de.minimumMonthly(hours: de.stdHours, rate: 10, inflationIndex: pow(1.03, 2)), full)
        XCTAssertEqual(LabourRules().minimumMonthly(hours: 40, rate: 1, inflationIndex: 1), 0, "no entry, no minimum")
    }

    func testHiringNeverPaysUnderTheMinimum() throws {
        var (e, id) = try cafe("UK")
        let w = World(state: e.state, data: e.data)
        let co = try XCTUnwrap(e.state.company(id))
        let minimum = w.minimumWage(co)
        XCTAssertGreaterThan(minimum, 0)
        var hired = 0
        let startingStaff = co.staff.count
        for _ in 0..<40 {
            var pid = 0
            e.update { s, d, _ in let co = s.company(id); pid = Hiring.generateCandidate(role: "barista", company: co, tier: "mid", state: &s, data: d).id }
            if e.hire(personID: pid, companyID: id, monthlyWage: 1) == .ok { hired += 1 }
        }
        if hired == 0 { throw XCTSkip("nobody took the minimum") }
        let staff = try XCTUnwrap(e.state.company(id)).staff
        XCTAssertEqual(staff.count, startingStaff + hired, "a new cafe opens with its first hand already on the books")
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
            let k = st.firstIndex { $0.id == pid }!
            st[k].hiredWeek = s.week - 5 * 52
            s.companies[i].staff = st
        }
        let senior = try XCTUnwrap(e.state.company(id)).staff.first { $0.id == pid }!
        let expected = w.terminationCost(co, monthlyWage: senior.monthlyWage, tenureWeeks: 5 * 52)
        XCTAssertGreaterThan(expected, w.terminationCost(co, monthlyWage: m.monthlyWage, tenureWeeks: 1), "more tenure, more pay")
        // the preview picks the weakest, so ask for everyone and compare the whole bill with the helper applied one by one
        let all = try XCTUnwrap(e.state.company(id)).staff
        let preview = e.layoffPreview(companyID: id, count: all.count)
        let each = all.reduce(0.0) { $0 + w.terminationCost(co, monthlyWage: $1.monthlyWage, tenureWeeks: Double(e.state.week - $1.hiredWeek), onNotice: $1.noticeWeeks > 0) }
        XCTAssertEqual(preview.severance, each, accuracy: 1, "the layoff preview uses the same helper")
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

    // MARK: Owner-supplied 2026 rules (docs/TAX_SOURCES.md)

    private func term(_ code: String, years: Double, reason: LabourRules.TerminationReason = .redundancy) -> LabourRules.Termination {
        LabourRules(code: code).termination(tenureWeeks: years * 52, reason: reason)
    }

    func testUKNoticeBandsAndRedundancyByAge() {
        XCTAssertEqual(term("UK", years: 0.05).noticeWeeks, 0)            // under a month
        XCTAssertEqual(term("UK", years: 0.5).noticeWeeks, 1)             // 1 week after 1 month, up to 2 years
        XCTAssertEqual(term("UK", years: 1.9).noticeWeeks, 1)
        XCTAssertEqual(term("UK", years: 2).noticeWeeks, 2)               // 1 week per completed year from 2 to 12
        XCTAssertEqual(term("UK", years: 7).noticeWeeks, 7)
        XCTAssertEqual(term("UK", years: 12).noticeWeeks, 12)
        XCTAssertEqual(term("UK", years: 30).noticeWeeks, 12)             // max 12 weeks
        let uk = LabourRules(code: "UK")
        XCTAssertEqual(term("UK", years: 1).severanceWeeks, 0)            // not eligible under 2 years
        XCTAssertEqual(uk.termination(tenureWeeks: 10 * 52, age: 30).severanceWeeks, 10, accuracy: 1e-9)    // 1 week a year at 22-40
        XCTAssertEqual(uk.termination(tenureWeeks: 10 * 52, age: 20).severanceWeeks, 5, accuracy: 1e-9)     // half a week under 22
        XCTAssertEqual(uk.termination(tenureWeeks: 10 * 52, age: 50).severanceWeeks, 15, accuracy: 1e-9)    // 1.5 weeks from 41
        XCTAssertEqual(uk.termination(tenureWeeks: 30 * 52, age: 50).severanceWeeks, 30, accuracy: 1e-9)    // service counted up to 20 years
        XCTAssertEqual(uk.termination(tenureWeeks: 10 * 52, withCause: true).weeks, 0)
    }

    func testIENoticeBands() {
        XCTAssertEqual(term("IE", years: 0.2).noticeWeeks, 0)             // under 13 weeks
        XCTAssertEqual(term("IE", years: 1).noticeWeeks, 1)               // 13 weeks to under 2 years
        XCTAssertEqual(term("IE", years: 2).noticeWeeks, 2)
        XCTAssertEqual(term("IE", years: 4.9).noticeWeeks, 2)
        XCTAssertEqual(term("IE", years: 5).noticeWeeks, 4)
        XCTAssertEqual(term("IE", years: 10).noticeWeeks, 6)
        XCTAssertEqual(term("IE", years: 15).noticeWeeks, 8)
        XCTAssertEqual(term("IE", years: 40).noticeWeeks, 8)
    }

    func testDENoticeBandsAndNoAutomaticSeverance() {
        XCTAssertEqual(term("DE", years: 1).noticeWeeks, 4)               // statutory start 4 weeks
        for (years, weeks) in [(2.0, 4.3), (5, 8.7), (8, 13), (10, 17.4), (12, 21.7), (15, 26), (20, 30.4)] {   // 1, 2, 3, 4, 5, 6, 7 months
            XCTAssertEqual(term("DE", years: years).noticeWeeks, weeks, accuracy: 1e-9, "\(years) years")
        }
        for y in [1.0, 5, 15] { XCTAssertEqual(term("DE", years: y).severanceWeeks, 0, "no automatic severance at \(y) years") }
    }

    func testFRSeveranceFormulaAndEligibility() {
        let fr = LabourRules(code: "FR"), month = 52.0 / 12
        XCTAssertEqual(fr.termination(tenureWeeks: 34).severanceWeeks, 0)                  // under 8 months: not eligible
        XCTAssertGreaterThan(fr.termination(tenureWeeks: 35).severanceWeeks, 0)            // past 8 months
        XCTAssertEqual(fr.termination(tenureWeeks: 5 * 52).severanceWeeks, 5 * 0.25 * month, accuracy: 1e-9)       // 1/4 month a year
        XCTAssertEqual(fr.termination(tenureWeeks: 10 * 52).severanceWeeks, 10 * 0.25 * month, accuracy: 1e-9)
        XCTAssertEqual(fr.termination(tenureWeeks: 16 * 52).severanceWeeks, (10 * 0.25 + 6.0 / 3) * month, accuracy: 1e-6)   // 1/3 month a year after 10
        XCTAssertEqual(fr.termination(tenureWeeks: 16 * 52, withCause: true).weeks, 0)
        let t = fr.termination(tenureWeeks: 5 * 52)                                        // notice and severance are separate figures
        XCTAssertGreaterThan(t.noticeWeeks, 0)
        XCTAssertEqual(t.weeks, t.noticeWeeks + t.severanceWeeks, accuracy: 1e-12)
    }

    func testBRNoticeThirtyDaysPlusThreePerYearAndFundFine() {
        XCTAssertEqual(term("BR", years: 0.5).noticeWeeks * 7, 30, accuracy: 1e-3)
        XCTAssertEqual(term("BR", years: 1).noticeWeeks * 7, 33, accuracy: 1e-3)
        XCTAssertEqual(term("BR", years: 10).noticeWeeks * 7, 60, accuracy: 1e-3)
        XCTAssertEqual(term("BR", years: 20).noticeWeeks * 7, 90, accuracy: 1e-3)
        XCTAssertEqual(term("BR", years: 40).noticeWeeks * 7, 90, accuracy: 1e-3)         // capped at 90 days
        // FGTS: 8% of pay is payroll (employer rate in the country data); the 40% fine on the balance is a one-off, only without cause
        let br = LabourRules(code: "BR")
        let t = br.termination(tenureWeeks: 52 * 5)
        XCTAssertEqual(t.fundFineMonths, 0.4 * 0.08 * 60, accuracy: 1e-9)
        XCTAssertEqual(t.payments(monthlyWage: 1000, employerSocial: 0).fine, 1920, accuracy: 1e-6)
        XCTAssertEqual(br.termination(tenureWeeks: 52 * 5, withCause: true).fundFineMonths, 0)
        XCTAssertEqual(br.termination(tenureWeeks: 52 * 5, reason: .resignation).fundFineMonths, 0)
    }

    func testMXIndemnityIsGatedByReason() {
        let mx = LabourRules(code: "MX"), wk = 52.0 / 12
        let red = mx.termination(tenureWeeks: 10 * 52, reason: .redundancy)
        // 3 months + 20 days a year + seniority premium (12 days a year)
        XCTAssertEqual(red.severanceWeeks, 3 * wk + 10 * (20.0 + 12.0) / 7, accuracy: 1e-3)
        XCTAssertEqual(mx.termination(tenureWeeks: 10 * 52, reason: .unjustified).severanceWeeks, red.severanceWeeks, accuracy: 1e-9)
        XCTAssertEqual(mx.termination(tenureWeeks: 10 * 52, reason: .forCause).weeks, 0)
        XCTAssertEqual(mx.termination(tenureWeeks: 10 * 52, reason: .resignation).weeks, 0)
        XCTAssertEqual(mx.termination(tenureWeeks: 10 * 52, withCause: true).weeks, 0)
        XCTAssertEqual(red.noticeWeeks, 0)
    }

    func testUSNoSeveranceByDefaultAndMassLayoffFlag() {
        let us = LabourRules(code: "US")
        XCTAssertEqual(us.termination(tenureWeeks: 10 * 52).weeks, 0)
        XCTAssertEqual(us.termination(tenureWeeks: 10 * 52).fundFineMonths, 0)
        XCTAssertEqual(us.termination(tenureWeeks: 10 * 52, massLayoff: true).noticeWeeks * 7, 60, accuracy: 1e-3)     // WARN-type 60 days
        XCTAssertEqual(LabourRules(code: "DE").termination(tenureWeeks: 52, massLayoff: true).noticeWeeks, 4)          // no such law in the data
    }

    func testTerminationPaymentsUseActualWageAndAreSeparate() {
        let t = LabourRules(code: "FR").termination(tenureWeeks: 6 * 52)
        let a = t.payments(monthlyWage: 3000, employerSocial: 0.42), b = t.payments(monthlyWage: 6000, employerSocial: 0.42)
        XCTAssertEqual(b.notice, 2 * a.notice, accuracy: 1e-9)
        XCTAssertEqual(b.severance, 2 * a.severance, accuracy: 1e-9)
        XCTAssertEqual(a.severance, 3000 * 12 / 52 * t.severanceWeeks, accuracy: 1e-9)    // severance carries no employer charge
        XCTAssertEqual(a.notice, 3000 * 12 / 52 * t.noticeWeeks * 1.42, accuracy: 1e-9)
    }

    func testMinimumWageData2026() {
        func rule(_ code: String) -> JSONValue { CountryTraits.labour(code) }
        func entry(_ code: String, _ i: Int = 0) -> JSONValue { rule(code)["minimumWage"][i] }
        XCTAssertEqual(entry("MX")["amount"].double, 315.04, accuracy: 1e-9)
        XCTAssertEqual(entry("MX")["period"].string, "day")
        XCTAssertEqual(entry("MX", 1)["amount"].double, 440.87, accuracy: 1e-9)
        XCTAssertEqual(entry("MX", 1)["region"].string, "northern border zone")
        XCTAssertEqual(rule("MX")["minMonthly"].double, 315.04 * 30.4, accuracy: 1)
        XCTAssertEqual(entry("KR")["amount"].double, 10320)
        XCTAssertEqual(rule("KR")["minMonthly"].double, 2_156_880)
        XCTAssertEqual(rule("BR")["minMonthly"].double, 1621)
        XCTAssertEqual(entry("BR")["hourly"].double, 7.37, accuracy: 1e-9)
        XCTAssertEqual(entry("FR")["amount"].double, 12.31, accuracy: 1e-9)
        XCTAssertEqual(entry("FR")["effective"].string, "2026-06-01")
        XCTAssertEqual(entry("FR", 1)["amount"].double, 12.02, accuracy: 1e-9)
        XCTAssertEqual(rule("FR")["minMonthly"].double, (12.31 * 35 * 52 / 12).rounded(), accuracy: 1e-9)
        XCTAssertEqual(entry("DE")["amount"].double, 13.90, accuracy: 1e-9)
        XCTAssertEqual(entry("UK")["amount"].double, 12.71, accuracy: 1e-9)
        XCTAssertEqual(entry("UK")["ageBand"].string, "21+")
        XCTAssertEqual(entry("IE")["amount"].double, 14.15, accuracy: 1e-9)
        XCTAssertEqual(entry("IE")["ageBand"].string, "20+")
        XCTAssertEqual(entry("US")["amount"].double, 7.25, accuracy: 1e-9)
        XCTAssertEqual(entry("US")["region"].string, "federal")
        // no game-scaled minimum is left: the field holds the real figure
        for code in ["NO", "SE", "PL", "LT", "KR", "BR", "MX", "IT", "FI"] { XCTAssertTrue(rule(code)["realMinMonthly"].isNull, code) }
    }
}
