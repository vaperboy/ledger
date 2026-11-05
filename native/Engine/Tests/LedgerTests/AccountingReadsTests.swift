import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The Accounting read models and records, net worth breakdown and Company overview figures.
final class AccountingReadsTests: XCTestCase {
    private func firm(trade: String = "cafe", days: Int = 90, form: LegalForm = .limited, seed: Int = 31) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 600_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, form: form, fundWith: 200_000_000) else { XCTFail("start"); throw XCTSkip("none") }
        _ = e.quickSetup(companyID: id)
        _ = e.openCompany(companyID: id)
        _ = e.takeLoan(kind: "biz", amount: 3_000_000, termMonths: 36, companyID: id)
        for _ in 0..<days { _ = e.nextDay() }
        return (e, id)
    }

    func testLedgerIsCompleteUncappedAndSearchable() throws {
        let (e, id) = try firm()
        let co = try XCTUnwrap(e.state.company(id))
        let rows = AccountingLedger.rows(co)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.amount }, e.state.cashFlow["co\(id)"] ?? 0, accuracy: 1, "every movement of company cash is a ledger row")
        let page = try XCTUnwrap(e.companyTransactions(companyID: id))
        XCTAssertGreaterThan(page.entries.count, 40, "the 40-label cap is gone")
        XCTAssertTrue(page.entries.contains { $0.categoryID == "sales" && $0.isIncome }, "sales are recorded")
        XCTAssertTrue(page.entries.contains { $0.categoryID == "purchases" && !$0.isIncome }, "supplier purchases are recorded")
        XCTAssertTrue(page.entries.contains { $0.categoryID == "payroll" })
        XCTAssertTrue(page.entries.contains { $0.categoryID == "loans" && $0.link?.kind == "loan" }, "loan payments link to the loan")
        let inc = try XCTUnwrap(e.companyTransactions(companyID: id, kind: .income))
        XCTAssertTrue(inc.entries.allSatisfy { $0.isIncome })
        let exp = try XCTUnwrap(e.companyTransactions(companyID: id, kind: .expenses))
        XCTAssertTrue(exp.entries.allSatisfy { !$0.isIncome })
        XCTAssertEqual(inc.entries.count + exp.entries.count, page.entries.count)
        let found = try XCTUnwrap(e.companyTransactions(companyID: id, search: "payroll"))
        XCTAssertFalse(found.entries.isEmpty)
        XCTAssertTrue(found.entries.allSatisfy { $0.label.lowercased().contains("payroll") || $0.category.lowercased().contains("payroll") })
        let ranged = try XCTUnwrap(e.companyTransactions(companyID: id, fromWeek: e.state.week - 2))
        XCTAssertTrue(ranged.entries.allSatisfy { $0.week >= e.state.week - 2 })
        let first = try XCTUnwrap(page.entries.first)
        XCTAssertNotNil(e.transactionDetail(companyID: id, id: first.id))
    }

    func testNotesAndAccessAreNamedUsersOnly() throws {
        var (e, id) = try firm(days: 40)
        let staff = try XCTUnwrap(e.state.company(id)?.staff.first)
        let user = "p\(staff.id)"
        let t = try XCTUnwrap(e.companyTransactions(companyID: id)?.entries.first)
        // Nobody but the owner has access by default (the accountant and managers included).
        XCTAssertEqual(e.accountingLevel(companyID: id), .owner)
        XCTAssertNil(e.companyTransactions(companyID: id, user: user))
        XCTAssertNil(e.payrollRuns(companyID: id, user: "acc"))
        XCTAssertFalse(e.setTransactionNote(companyID: id, id: t.id, note: "x", user: user))
        // The owner adds a named user at View.
        XCTAssertEqual(e.setAccountingAccess(companyID: id, userID: user, level: .view), .changed)
        XCTAssertNotNil(e.companyTransactions(companyID: id, user: user))
        XCTAssertNil(e.payrollRuns(companyID: id, user: user), "payroll needs the payroll level")
        XCTAssertNil(e.accountingRoster(companyID: id, user: user), "only the owner sees who has access")
        XCTAssertEqual(e.setAccountingAccess(companyID: id, userID: user, level: .full, by: user), .refused("Only the owner manages access."))
        XCTAssertEqual(e.setAccountingAccess(companyID: id, userID: user, level: .full), .changed)
        XCTAssertTrue(e.setTransactionNote(companyID: id, id: t.id, note: "Checked with the supplier", user: user))
        XCTAssertEqual(e.companyTransactions(companyID: id)?.entries.first { $0.id == t.id }?.note, "Checked with the supplier")
        // Access to one company never grants another.
        guard case .success(let other) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .soleTrader, fundWith: 10_000_000) else { return XCTFail("second") }
        XCTAssertNil(e.companyTransactions(companyID: other, user: user))
        XCTAssertEqual(e.accountingLevel(companyID: other, user: user), .none)
        // Remove.
        XCTAssertEqual(e.removeAccountingAccess(companyID: id, userID: user), .changed)
        XCTAssertNil(e.companyTransactions(companyID: id, user: user))
        XCTAssertEqual(e.setAccountingAccess(companyID: id, userID: "p999999", level: .view), .refused("That person is not part of this company."))
    }

    func testPayrollRunsPayslipsTimesheetsAndNoDuplicatePeriod() throws {
        let (e, id) = try firm(days: 100)
        let co = try XCTUnwrap(e.state.company(id))
        let runs = try XCTUnwrap(e.payrollRuns(companyID: id))
        XCTAssertFalse(runs.isEmpty)
        XCTAssertEqual(Set(runs.map(\.periodIndex)).count, runs.count, "one run per period")
        let run = try XCTUnwrap(runs.first)
        XCTAssertEqual(run.lines.count, co.staff.count + (co.managerID == nil ? 0 : 1))
        XCTAssertGreaterThan(run.paid, 0)
        XCTAssertGreaterThan(run.employerCostsTotal, 0)
        XCTAssertEqual(e.payslips(companyID: id, runID: run.id)?.count, run.lines.count)
        let review = try XCTUnwrap(e.payrollRunReview(companyID: id))
        XCTAssertEqual(review.totalEmployerCost, review.grossTotal + review.employerContributions + review.insurance + review.paidLeaveCover, accuracy: 1)
        XCTAssertEqual(review.account, co.name + " account")
        let sheets = try XCTUnwrap(e.timesheets(companyID: id))
        XCTAssertEqual(sheets.count, co.staff.count)
        XCTAssertTrue(sheets.contains { ($0.actualHoursRecorded ?? 0) > 0 }, "hours actually worked come from the weekly simulation")
        XCTAssertTrue(sheets.allSatisfy { $0.contractedHoursPerWeek > 0 })
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testDocumentsInvoicesSuppliersAreRealRecords() throws {
        let (e, id) = try firm(days: 60)
        let co = try XCTUnwrap(e.state.company(id))
        let docs = try XCTUnwrap(e.companyDocuments(companyID: id))
        XCTAssertTrue(docs.contains { $0.kind == "legalForm" })
        XCTAssertEqual(docs.filter { $0.kind == "employment" }.count, co.staff.count + (co.managerID == nil ? 0 : 1), "one employment contract per person")
        XCTAssertEqual(docs.filter { $0.kind == "financing" }.count, 1, "the loan is a financing document")
        XCTAssertTrue(docs.contains { $0.group == .tax } || co.taxAccrued == 0)
        XCTAssertNotNil(e.invoices(companyID: id))
        XCTAssertNotNil(e.supplierRecords(companyID: id))
        let lr = try XCTUnwrap(e.loanRecords(companyID: id).first)
        XCTAssertEqual(docs.first { $0.kind == "financing" }?.amount ?? 0, lr.balance, accuracy: 1)
    }

    func testInsuranceAndApplicationsAreRealRecords() throws {
        var (e, id) = try firm(days: 10)
        // No policy is held at first: no insurance rows, and nothing is made up.
        XCTAssertTrue(try XCTUnwrap(e.companyDocuments(companyID: id, group: .insurance)).isEmpty || (e.coverageOverview(companyID: id)?.activeCount ?? 0) > 0)
        let policy = try XCTUnwrap(e.coverageOverview(companyID: id)?.policies.first(where: { !$0.isOn }))
        _ = e.toggleInsurancePolicy(companyID: id, product: policy.id)
        let held = try XCTUnwrap(e.coverageOverview(companyID: id)?.policies.first(where: { $0.id == policy.id }))
        let ins = try XCTUnwrap(e.companyDocuments(companyID: id, group: .insurance))
        XCTAssertEqual(ins.contains { $0.id == "ins-" + policy.id }, held.isOn, "a policy appears exactly when the company holds it")
        XCTAssertEqual(ins.count, e.coverageOverview(companyID: id)?.activeCount ?? -1)
        // A franchise application is a record with its status; chain and franchise papers are applications, not licences.
        XCTAssertTrue(try XCTUnwrap(e.companyDocuments(companyID: id, group: .applications)).isEmpty)
        e.update { s, _, _ in
            s.rest["fbApps"] = .object(["x:GL:0": .object(["st": "pending", "w0": .number(Double(s.week)), "due": .number(Double(s.week + 2)), "country": "UK", "city": ""])])
        }
        let apps = try XCTUnwrap(e.companyDocuments(companyID: id, group: .applications))
        XCTAssertEqual(apps.filter { $0.kind == "franchise" }.count, 1)
        XCTAssertEqual(apps.first { $0.kind == "franchise" }?.status, "Under review")
        XCTAssertFalse(try XCTUnwrap(e.companyDocuments(companyID: id, group: .company)).contains { $0.id == "doc-chain" || $0.id == "doc-fran" })
        // Access follows the same rule as every Accounting record.
        XCTAssertNil(e.companyDocuments(companyID: id, group: .applications, user: "p999"))
    }

    func testCustomerInvoicesAreRecordsWithStatusAndTax() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 8)
        e.update { s, _, _ in Ledger.move(&s, .me, 600_000_000, why: "Test funds") }
        var found = false
        for trade in ["cons", "print", "logistics", "construction", "carclean", "handy", "photo"] {
            guard let bd = e.data.catalog[trade], bd.businessShare > 0 else { continue }
            guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, form: .limited, fundWith: 200_000_000) else { continue }
            _ = e.quickSetup(companyID: id); _ = e.openCompany(companyID: id)
            for _ in 0..<120 { _ = e.nextDay() }
            let list = e.invoices(companyID: id, kind: .customer) ?? []
            if list.isEmpty { continue }
            found = true
            XCTAssertTrue(list.allSatisfy { $0.number.hasPrefix("INV-") && $0.lines.count >= 1 })
            XCTAssertEqual(Set(list.map(\.number)).count, list.count, "numbers are unique")
            XCTAssertTrue(list.contains { $0.status == .paid || $0.status == .sent || $0.status == .overdue })
            XCTAssertTrue(list.allSatisfy { abs($0.net + $0.tax - $0.gross) < 0.01 })
            break
        }
        if !found { throw XCTSkip("no trade with business customers produced invoices in the window") }
    }

    func testNetWorthAndOverviewReadModels() throws {
        var (e, id) = try firm(days: 60)
        let nw = e.netWorthBreakdown()
        XCTAssertEqual(nw.total, e.netWorth.total, accuracy: 0.5)
        XCTAssertEqual(nw.liquid, e.state.cash + e.state.savings, accuracy: 0.5)
        XCTAssertEqual(nw.stakes.filter { $0.companyID == id }.count, 1, "attributable equity once")
        XCTAssertGreaterThan(nw.guaranteedCompanyDebt + 1, 0)
        // A company inside a holding is not counted twice.
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].holdingID = 999 } }
        XCTAssertEqual(e.netWorthBreakdown().stakes.first { $0.companyID == id }?.attributableEquity, 0)
        let st = try XCTUnwrap(e.companyOverviewStats(companyID: id))
        XCTAssertEqual(st.cash, e.state.company(id)?.cash)
        XCTAssertEqual(st.operatingExpenses, st.expenses.reduce(0) { $0 + $1.amount }, accuracy: 0.5)
        XCTAssertEqual(st.profit, st.revenue - st.operatingExpenses, accuracy: 0.5, "the breakdown and the profit use the same categories")
        XCTAssertEqual(st.legalFormShort, "Ltd")
        XCTAssertEqual(st.ownershipPercent, 100)
        XCTAssertEqual(st.reserves.free, st.cash - st.reserves.payroll - st.reserves.tax, accuracy: 0.5)
    }
}
