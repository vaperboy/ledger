import XCTest
import GameCore
import Countries
import Employees
import Finance
import Businesses
import Simulation

/// Audit part 4a: the 16 countries the first calculations audit did not probe (all 23 minus UK, US, MX, PL, DE, JP, NO).
/// Per country: a limited-company cafe played 26 weeks day by day (ledger gaps empty, equity = capital put in + profit), the minimum wage on
/// the cheapest job, notice and severance quoted equal to what is booked, the employer on-cost shared by payroll and the quotes, VAT data and the
/// personal-tax quote. Findings: native/docs/audit/part4a-countries.md.
final class CountryAuditProbeTests: XCTestCase {
    static let codes = ["SE", "LT", "FR", "ES", "NL", "CA", "AU", "KR", "BR", "CH", "AE", "IT", "DK", "FI", "IE", "SG"]

    private func countries() throws -> [Country] {
        let book = try CountryBook.bundled()
        return Self.codes.map { code in book.countries.first { $0.code == code }! }
    }

    private func cafe(_ code: String, seed: Int = 5) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: code, playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 5_000_000) else { throw XCTSkip("no company in \(code)") }
        return (e, id)
    }

    // MARK: Twenty-six weeks

    private func runHalfYear(_ code: String) throws {
        var (e, id) = try cafe(code)
        for _ in 0..<(26 * 7) {
            e.nextDay()
            for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
        }
        let gaps = Ledger.gaps(e.state)
        XCTAssertTrue(gaps.isEmpty, "\(code) ledger gaps: \(gaps)")
        guard let co = e.state.company(id), co.status.isLive else { return }
        let equity = CompanyFigures.assets(co) - CompanyFigures.debts(co, loans: e.state.loans)
        let profit = Books.profit(co.books.total) - (co.books.total["tax"] ?? 0)
        XCTAssertEqual(equity, co.injectedCapital + profit, accuracy: max(20_000, abs(profit) * 0.02), "\(code) equity \(equity) vs injected \(co.injectedCapital) + profit \(profit)")
    }

    func testHalfYearSE() throws { try runHalfYear("SE") }
    func testHalfYearLT() throws { try runHalfYear("LT") }
    func testHalfYearFR() throws { try runHalfYear("FR") }
    func testHalfYearES() throws { try runHalfYear("ES") }
    func testHalfYearNL() throws { try runHalfYear("NL") }
    func testHalfYearCA() throws { try runHalfYear("CA") }
    func testHalfYearAU() throws { try runHalfYear("AU") }
    func testHalfYearKR() throws { try runHalfYear("KR") }
    func testHalfYearBR() throws { try runHalfYear("BR") }
    func testHalfYearCH() throws { try runHalfYear("CH") }
    func testHalfYearAE() throws { try runHalfYear("AE") }
    func testHalfYearIT() throws { try runHalfYear("IT") }
    func testHalfYearDK() throws { try runHalfYear("DK") }
    func testHalfYearFI() throws { try runHalfYear("FI") }
    func testHalfYearIE() throws { try runHalfYear("IE") }
    func testHalfYearSG() throws { try runHalfYear("SG") }

    // MARK: Minimum wage on the cheapest job, dismissal quote = booking

    private func hireOne(_ e: inout GameEngine, _ id: Int, wage: Double?) -> Int? {
        var pid = 0
        e.update { s, d, _ in let co = s.company(id)!; pid = Hiring.generateCandidate(role: "barista", company: co, tier: "young", state: &s, data: d).id }
        return e.hire(personID: pid, companyID: id, monthlyWage: wage ?? e.state.people[pid]!.askingMonthlyWage * 1.5) == .ok ? pid : nil
    }

    func testMinimumWageAppliesToTheCheapestJobInEveryCountry() throws {
        var tested = 0
        defer { XCTAssertEqual(tested, Self.codes.count, "every country hired someone") }
        for c in try countries() {
            var (e, id) = try cafe(c.code, seed: 11)
            let minimum = World(state: e.state, data: e.data).minimumWage(e.state.company(id)!)
            XCTAssertGreaterThan(minimum, 0, c.code)
            guard let pid = hireOne(&e, id, wage: 1) ?? hireOne(&e, id, wage: minimum) ?? hireOne(&e, id, wage: nil) else { continue }
            tested += 1
            let m = try XCTUnwrap(e.state.company(id)?.staff.first { $0.id == pid }, c.code)
            let asked = e.state.people[pid]?.askingMonthlyWage ?? 0
            print("AUDIT4A \(c.code) minimum \(Int(minimum)) cheapest candidate asks \(Int(asked)) (\(Int(asked / minimum * 100))% of minimum) paid \(Int(m.monthlyWage))")
            XCTAssertGreaterThanOrEqual(m.monthlyWage, minimum - 0.5, "\(c.code) cheapest job paid under the minimum")
            for other in e.state.company(id)!.staff { XCTAssertGreaterThanOrEqual(other.monthlyWage, minimum - 0.5, "\(c.code) staff under the minimum") }
        }
    }

    func testDismissalQuoteEqualsWhatIsBookedInEveryCountry() throws {
        var tested = 0
        defer { XCTAssertEqual(tested, Self.codes.count, "every country hired someone") }
        for c in try countries() {
            var (e, id) = try cafe(c.code, seed: 13)
            guard let pid = hireOne(&e, id, wage: nil) else { continue }
            tested += 1
            // five years' service, then a redundancy
            e.update { s, _, _ in
                let i = s.companyIndex(id)!, k = s.companies[i].staff.firstIndex { $0.id == pid }!
                s.companies[i].staff[k].hiredWeek = s.week - 5 * 52
            }
            let quote = try XCTUnwrap(Dismissal.quote(e.state, companyID: id, staffID: pid, reason: .redundancy, data: e.data), c.code)
            let m = try XCTUnwrap(e.state.company(id)?.staff.first { $0.id == pid })
            let rules = LabourRules(country: c)
            let t = rules.termination(tenureWeeks: 5 * 52, reason: .redundancy, age: e.state.people[pid].map { Double($0.age) })
            let onCost = 1 + c.employerOnCost(monthlyWage: m.monthlyWage)
            XCTAssertEqual(quote.notice, m.monthlyWage * 12 / 52 * t.noticeWeeks * onCost, accuracy: 1, "\(c.code) notice carries the full employer on-cost")
            XCTAssertEqual(quote.severance, m.monthlyWage * 12 / 52 * t.severanceWeeks, accuracy: 1, "\(c.code) severance")
            var s = e.state
            let before = s.company(id)!.cash
            Dismissal.dismiss(&s, companyID: id, staffID: pid, reason: .redundancy, data: e.data)
            let paid = before - s.company(id)!.cash
            XCTAssertEqual(paid, quote.total, accuracy: 3, "\(c.code) booked \(paid) vs quoted \(quote.total)")
            XCTAssertTrue(Ledger.gaps(s).isEmpty, c.code)
        }
    }

    // MARK: Data checks

    func testEmployerOnCostIsOneRateEverywhere() throws {
        for c in try countries() {
            XCTAssertEqual(c.employerCostFactor, 1 + c.employerOnCost(monthlyWage: c.medianMonthlyWage), accuracy: 1e-9, "\(c.code) payroll factor against the shared on-cost")
            XCTAssertEqual(c.employerOnCost(monthlyWage: 1), c.employerSocialRate(monthlyWage: 1) + c.employerPension + c.employerInjury, accuracy: 1e-12)
            XCTAssertLessThan(c.employerOnCost(monthlyWage: c.medianMonthlyWage), 0.7, c.code)
        }
    }

    func testVATDataIsCoherentInEveryCountry() throws {
        for c in try countries() {
            XCTAssertTrue([1, 2, 3, 6, 12].contains(c.vatFilingMonths), "\(c.code) filing every \(c.vatFilingMonths) months")
            XCTAssertTrue(c.vat.standard > 0 && c.vat.standard < 0.3, "\(c.code) standard rate \(c.vat.standard)")
            XCTAssertLessThanOrEqual(c.vat.food, c.vat.standard, c.code)
            XCTAssertLessThanOrEqual(c.vat.low, c.vat.standard, c.code)
            XCTAssertGreaterThanOrEqual(c.vatThreshold, 0, c.code)
        }
    }

    func testPersonalTaxQuoteRisesWithIncomeInEveryCountry() throws {
        for c in try countries() {
            let median = c.medianMonthlyWage * 12
            let t1 = Taxes.personalIncomeTax(median, kind: .wage, in: c), t5 = Taxes.personalIncomeTax(median * 5, kind: .wage, in: c)
            XCTAssertGreaterThanOrEqual(t1, 0, c.code)
            XCTAssertLessThan(t1 / median, 0.5, "\(c.code) median earner's rate")
            if c.code == "AE" { XCTAssertEqual(t5, 0, "AE has no personal income tax") } else {
                XCTAssertGreaterThan(t5 / (median * 5), t1 / median, "\(c.code) progressive")
            }
            XCTAssertLessThan(t5 / (median * 5), 0.65, "\(c.code) high earner's rate")
            XCTAssertEqual(Taxes.personalIncomeTax(-1000, kind: .wage, in: c), 0, c.code)
        }
    }

    func testLabourDataIsPlausibleInEveryCountry() throws {
        for c in try countries() {
            let r = LabourRules(country: c)
            XCTAssertTrue(r.hasMinimum, c.code)
            XCTAssertGreaterThan(r.leaveDays, 0, "\(c.code) statutory leave")
            XCTAssertGreaterThan(r.termination(tenureWeeks: 5 * 52, reason: .redundancy).noticeWeeks, 0, "\(c.code) notice after five years")
            // overtime: paid above the standard week at the data's premium
            let pay = r.overtimePay(monthlyWage: 100_000, contracted: r.stdHours, worked: r.stdHours + 5)
            XCTAssertEqual(pay, 100_000 * 12 / 52 / r.stdHours * 5 * (1 + r.overtimePremium), accuracy: 1e-6, c.code)
        }
    }
}
