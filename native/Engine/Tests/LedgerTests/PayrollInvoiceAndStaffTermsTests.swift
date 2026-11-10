import XCTest
import GameCore
import Countries
import Employees
import Finance
import Businesses
@testable import Simulation

final class PayrollInvoiceAndStaffTermsTests: XCTestCase {
    private func start(trade: String = "cafe", seed: Int = 17) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 600_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, fundWith: 150_000_000) else { XCTFail("start"); throw XCTSkip("none") }
        return (e, id)
    }

    func testStaffTermsUnlockWithAManagerOrFiveStaff() throws {
        var (e, id) = try start()
        XCTAssertFalse(e.staffTermsUnlocked(companyID: 999))
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].staff = []
            s.companies[i].managerID = nil
        }
        XCTAssertFalse(e.staffTermsUnlocked(companyID: id))
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].staff = (1...5).map { StaffMember(raw: ["id": .number(Double($0))]) }
        }
        XCTAssertTrue(e.staffTermsUnlocked(companyID: id))
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].staff = []
            s.companies[i].managerID = 0
        }
        XCTAssertTrue(e.staffTermsUnlocked(companyID: id))
    }

    func testFinancingFeeIsItsOwnCategoryAndDraftInvoicesBecomeSent() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 8)
        e.update { s, _, _ in Ledger.move(&s, .me, 600_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, fundWith: 150_000_000) else { return XCTFail("start") }
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
        func records(_ id: Int) -> [InvoiceBook.Record] { e.state.company(id).map { InvoiceBook.records($0) } ?? [] }
        var checkedDraft = false
        defer { XCTAssertTrue(checkedDraft, "some trade with business customers raised invoices") }
        for trade in ["cons", "print", "logistics", "construction", "carclean", "handy", "photo"] {
            guard let bd = e.data.catalog[trade], bd.businessShare > 0,
                  case .success(let tid) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, fundWith: 100_000_000) else { continue }
            _ = e.quickSetup(companyID: tid); _ = e.openCompany(companyID: tid)
            var sawDraft = false
            for _ in 0..<90 {
                _ = e.nextDay()
                if records(tid).contains(where: { $0.closed == "draft" }) { sawDraft = true }
            }
            let list = records(tid)
            if list.isEmpty { continue }
            XCTAssertTrue(sawDraft, "an invoice is a draft before it is sent")
            XCTAssertTrue(list.contains { $0.closed != "draft" }, "drafts are sent by the weekly run")
            checkedDraft = true
            break
        }
    }

    func testCommissionAndBonusUseTheRealPeoplesOnCost() throws {
        let (e, id) = try { () throws -> (GameEngine, Int) in
            var (g, i) = try start()
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
