import XCTest
import GameCore
import Countries
import Employees
import Finance
import Businesses
import Simulation

/// Manager-path payroll responsibility; conversion of setup / closed / sold / chain / franchise companies; deductions; hours worked;
/// draft and paid invoices; the financing-fee category; the commission/bonus on-cost.
final class Stage2ProbeTests: XCTestCase {
    private func start(_ form: LegalForm, trade: String = "cafe", seed: Int = 17) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 600_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, form: form, fundWith: 150_000_000) else { XCTFail("start"); throw XCTSkip("none") }
        return (e, id)
    }

    func testManagerPathPayrollResponsibility() throws {
        var (e, id) = try start(.soleTrader)
        _ = e.quickSetup(companyID: id); _ = e.openCompany(companyID: id)
        XCTAssertEqual(e.payrollOverview(companyID: id)?.responsibility?.who, .owner)
        let cands = try XCTUnwrap(e.searchManagers(companyID: id))
        XCTAssertEqual(e.hireManager(personID: cands[0].id, companyID: id, monthlyWage: cands[0].askingMonthlyWage * 1.3), .ok)
        let o = try XCTUnwrap(e.payrollOverview(companyID: id))
        // A manager who decides on their card (level 1 or 2) runs payroll with no fee; one who does not leaves it to the player.
        let handler = ContractTalk.handler(e.state, companyID: id, data: e.data)
        XCTAssertEqual(o.responsibility?.who, handler == nil ? .owner : .manager)
        XCTAssertEqual(o.choices.first { $0.mode == .manager }?.monthlyFee, 0)
        for _ in 0..<70 { _ = e.nextDay() }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        XCTAssertFalse((e.payrollRuns(companyID: id) ?? []).isEmpty)
    }

    func testConversionOfSetupClosedSoldChainAndFranchise() throws {
        // Still being set up: allowed (the legal form is chosen before opening).
        var (e, id) = try start(.soleTrader)
        XCTAssertNil(e.conversionPlan(companyID: id)?.blocked)
        XCTAssertEqual(e.convertToLimited(companyID: id), .ok)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        // Closed for a while: allowed.
        var (c, cid) = try start(.soleTrader)
        _ = c.quickSetup(companyID: cid); _ = c.openCompany(companyID: cid)
        for _ in 0..<14 { _ = c.nextDay() }
        c.update { s, _, _ in if let i = s.companyIndex(cid) { s.companies[i].status = .closed } }
        XCTAssertEqual(c.convertToLimited(companyID: cid), .ok)
        XCTAssertEqual(c.state.company(cid)?.form, .limited)
        // Sold or bust: refused, nothing changes.
        var (s1, sid) = try start(.soleTrader)
        s1.update { s, _, _ in if let i = s.companyIndex(sid) { s.companies[i].status = .sold } }
        let snap = s1.state
        XCTAssertEqual(s1.convertToLimited(companyID: sid), .notAllowed(.notTrading))
        XCTAssertEqual(s1.state, snap)
        // A store of a chain follows the chain's form.
        var (ch, chid) = try start(.soleTrader)
        ch.update { s, _, _ in
            s.rest["chains"] = .array([.object(["id": 77, "type": "cafe"])])
            if let i = s.companyIndex(chid) { s.companies[i].set("chain", 77) }
        }
        XCTAssertEqual(ch.convertToLimited(companyID: chid), .notAllowed(.chainStore))
        // A franchisor (franchise on) converts like any company, and its franchise record is untouched.
        var (f, fid) = try start(.soleTrader)
        f.update { s, _, _ in if let i = s.companyIndex(fid) { s.companies[i].set("fr", .object(["on": true])) } }
        XCTAssertEqual(f.convertToLimited(companyID: fid), .ok)
        XCTAssertTrue(f.state.company(fid)?.value("fr")["on"].bool ?? false)
        XCTAssertTrue(Ledger.gaps(f.state).isEmpty)
    }

    func testPayslipDeductionsHoursWorkedAndOvertimeComeFromRealData() throws {
        var (e, id) = try start(.limited)
        _ = e.quickSetup(companyID: id); _ = e.openCompany(companyID: id)
        for _ in 0..<110 { _ = e.nextDay() }   // long enough for a replacement hire to have worked some weeks
        let co = try XCTUnwrap(e.state.company(id))
        let country = try XCTUnwrap(e.data.countries["UK"])
        let run = try XCTUnwrap(e.payrollRuns(companyID: id)?.first)
        let line = try XCTUnwrap(run.lines.first)
        let d = EmployerCost.deductions(wage: line.grossMonthly, country: country)
        XCTAssertEqual(line.incomeTaxWithheld, d.incomeTax, accuracy: 0.01)
        XCTAssertEqual(line.employeeSocialWithheld, d.employeeSocial, accuracy: 0.01)
        XCTAssertEqual(line.netPay, line.grossMonthly - d.incomeTax - d.employeeSocial, accuracy: 0.01)
        XCTAssertLessThan(line.netPay, line.grossMonthly)
        // Withholding is not an extra company cost.
        XCTAssertEqual(line.totalEmployerCost, line.grossMonthly + line.employerContributions + line.insurance + line.paidLeaveCover, accuracy: 1)
        // Hours actually worked come from the weekly simulation.
        let sheets = try XCTUnwrap(e.timesheets(companyID: id))
        let thisMonth = GameCalendar.monthIndex(week: e.state.week)
        let lastMonth = (1...3).flatMap { e.timesheets(companyID: id, monthIndex: thisMonth - $0) ?? [] }   // the weeks since opening may straddle a month end
        XCTAssertEqual(sheets.count, co.staff.count)
        XCTAssertTrue((sheets + lastMonth).contains { ($0.actualHoursRecorded ?? 0) > 0 && $0.weeksRecorded > 0 }, "worked hours are recorded")
        XCTAssertTrue(sheets.allSatisfy { $0.paidLeaveHoursCovered >= 0 })
    }

    func testFinancingFeeIsItsOwnCategoryAndDraftInvoicesBecomeSent() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 8)
        e.update { s, _, _ in Ledger.move(&s, .me, 600_000_000, why: "Test funds") }
        // Loan arrangement fee: books under "fin", not interest.
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 150_000_000) else { return XCTFail("start") }
        _ = e.quickSetup(companyID: id); _ = e.openCompany(companyID: id)
        for _ in 0..<100 { _ = e.nextDay() }
        let a = e.loanAssessment(kind: "biz", companyID: id)
        if a.approved {
            let amount = (a.maximum / 2 / 1000).rounded() * 1000
            let int0 = e.state.company(id)?.books.total["int"] ?? 0
            if case .approved(_, let fee, _) = e.applyForLoan(kind: "biz", amount: amount, termMonths: 36, companyID: id, documents: LoanDocuments(fullName: e.state.player.name, companyPapers: .accounts), agreed: true), fee > 0 {
                XCTAssertEqual(e.state.company(id)?.books.total["fin"] ?? 0, fee, accuracy: 0.5)
                XCTAssertEqual(e.state.company(id)?.books.total["int"] ?? 0, int0, accuracy: 0.5)
                XCTAssertEqual(Books.expenses(["fin": 10]), 10, "it counts as a cost in the profit")
            }
        }
        // Draft invoices: a trade with business customers raises drafts that the next weekly run sends.
        var checkedDraft = false
        defer { XCTAssertTrue(checkedDraft, "some trade with business customers raised invoices") }
        for trade in ["cons", "print", "logistics", "construction", "carclean", "handy", "photo"] {
            guard let bd = e.data.catalog[trade], bd.businessShare > 0,
                  case .success(let tid) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, form: .limited, fundWith: 100_000_000) else { continue }
            _ = e.quickSetup(companyID: tid); _ = e.openCompany(companyID: tid)
            var sawDraft = false
            for _ in 0..<90 {
                _ = e.nextDay()
                if (e.invoices(companyID: tid, kind: .customer) ?? []).contains(where: { $0.status == .draft }) { sawDraft = true }
            }
            let list = e.invoices(companyID: tid, kind: .customer) ?? []
            if list.isEmpty { continue }
            XCTAssertTrue(sawDraft, "an invoice is a draft before it is sent")
            XCTAssertTrue(list.contains { $0.status != .draft }, "drafts are sent by the weekly run")
            checkedDraft = true
            break
        }
    }

    func testCommissionAndBonusUseTheRealPeoplesOnCost() throws {
        let (e, id) = try { () throws -> (GameEngine, Int) in
            var (g, i) = try start(.limited)
            _ = g.quickSetup(companyID: i); _ = g.openCompany(companyID: i)
            return (g, i)
        }()
        let co = try XCTUnwrap(e.state.company(id))
        let country = try XCTUnwrap(e.data.countries["UK"])
        let f = Payroll.averageFactor(co, country: country)
        let wages = co.staff.reduce(0) { $0 + $1.monthlyWage }
        let cost = co.staff.reduce(0) { $0 + $1.monthlyWage * country.payrollFactor(monthlyWage: $1.monthlyWage) }
        XCTAssertEqual(f, cost / wages, accuracy: 1e-9, "wage-weighted, from the real people")
    }
}
