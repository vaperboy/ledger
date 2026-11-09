import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

/// The reads the new look needs: payroll alerts, the Bank app, the trade picker and its costs, and the Hiring screen.
final class NewLookEngineReadsTests: XCTestCase {
    private func game(seed: Int = 7) throws -> GameEngine {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 500_000_000, why: "Test funds") }
        return e
    }

    private func cafe(_ e: inout GameEngine) throws -> Int {
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, fundWith: 50_000_000) else { throw XCTSkip("no company") }
        return id
    }

    // MARK: Payroll alerts and the Bank app

    func testRoutinePayrollTheCompanyCanPayIsNotAnAlert() throws {
        var e = try game()
        let id = try cafe(&e)
        for _ in 0..<(60 * 7) { e.nextDay() }
        XCTAssertNil(e.payrollAlerts().first { $0.companyID == id && !$0.isLate }, "the 'Approve routine payroll' rule covers it")
    }

    func testLoansBelongToTheirAccountAndStatementsAreListed() throws {
        var e = try game()
        let id = try cafe(&e)
        let biz = e.loanOffer(kind: "biz", amount: 1, companyID: id).maximum / 2, cons = e.loanOffer(kind: "cons", amount: 1, companyID: nil).maximum / 2
        XCTAssertGreaterThan(biz, 0); XCTAssertGreaterThan(cons, 0)
        XCTAssertEqual(e.takeLoan(kind: "biz", amount: biz, termMonths: 36, companyID: id), .ok)
        XCTAssertEqual(e.takeLoan(kind: "cons", amount: cons, termMonths: 24, companyID: nil), .ok)
        let bank = e.bankAccounts()
        XCTAssertEqual(bank.rows.first { $0.id == .company(id) }?.loanCount, 1)
        XCTAssertEqual(bank.rows.first { $0.id == .personal }?.loanCount, e.state.loans.filter { $0.companyID == 0 }.count)
        XCTAssertEqual(bank.rows.first { $0.id == .investments }?.loanCount, 0)
        XCTAssertEqual(bank.rows.map(\.id).filter { if case .company = $0 { return false }; return true }, [.personal, .investments])
        let company = try XCTUnwrap(e.bankAccount(.company(id)))
        XCTAssertEqual(company.loans.map(\.kind), ["biz"])
        XCTAssertGreaterThan(company.loans[0].yearlyRate, 0)
        XCTAssertTrue(company.upcoming.contains { $0.kind == .loan })
        XCTAssertEqual(company.balance, e.state.company(id)!.cash)
        XCTAssertGreaterThanOrEqual(company.available, company.balance)
        let me = try XCTUnwrap(e.bankAccount(.personal))
        XCTAssertTrue(me.loans.map(\.kind).contains("cons"))
        XCTAssertFalse(me.loans.contains { $0.kind == "biz" }, "a company's loan is not on the personal account")
        XCTAssertFalse(me.recent.isEmpty)
        XCTAssertEqual(me.statements.map(\.kind), ReportKind.allCases)
        XCTAssertEqual(e.bankAccount(.investments)?.loans.count, 0)
        XCTAssertEqual(bank.total, bank.rows.reduce(0) { $0 + $1.balance }, accuracy: 0.01)
    }

    // MARK: Trade picker

    func testTradePickerPricesTheHomeCityAndSplitsTheCost() throws {
        let e = try game()
        let city = e.state.player.cityID
        let rows = e.tradePickerRows()
        XCTAssertEqual(rows.count, e.data.catalog.all.filter { !SpecialFamilies.isRetired($0) }.count, "retired trades are not offered")
        let row = try XCTUnwrap(rows.first { $0.tradeID == "cafe" })
        XCTAssertEqual(row.startUpCost, e.tradeAffordability().first { $0.tradeID == "cafe" }?.cost)
        XCTAssertEqual(row.sector, e.data.catalog["cafe"]?.category)
        XCTAssertLessThanOrEqual(row.staffMin, row.staffMax)
        // Demand follows the city: the same café is High in the capital and Low in a small town.
        let uk = e.data.countries["UK"]!
        let small = try XCTUnwrap(uk.cities.first { $0.name == "Small town" })
        let big = try XCTUnwrap(uk.cities.first { $0.name == "London" })
        XCTAssertEqual(e.tradePickerRows(cityID: big.id).first { $0.tradeID == "cafe" }?.demand, .high)
        XCTAssertEqual(e.tradePickerRows(cityID: small.id).first { $0.tradeID == "cafe" }?.demand, .low)
        // The breakdown adds up to the picker's figure with the standard place, and to the plan's total with a picked one.
        let b = try XCTUnwrap(e.startUpCostBreakdown(tradeID: "cafe", cityID: city))
        XCTAssertEqual(b.lines.prefix(3).map(\.label), ["Registration and licences", "Fit-out and equipment", "Deposit and first month"])
        XCTAssertEqual(b.total, row.startUpCost!, accuracy: 0.5)
        XCTAssertEqual(b.lines.reduce(0) { $0 + $1.amount }, b.total, accuracy: 0.01)
        let plan = try XCTUnwrap(e.newCompanyPlan(tradeID: "cafe", cityID: city, size: 1))
        let pick = NewCompanyPlan.Pick(listingIndex: plan.options[0].index, buy: true)
        let size = CompanySetup.recommendedSize(e.data.catalog["cafe"]!, city: uk.city(city)!)
        let bought = try XCTUnwrap(e.startUpCostBreakdown(tradeID: "cafe", cityID: city, premises: pick))
        XCTAssertEqual(bought.total, e.newCompanyPlan(tradeID: "cafe", cityID: city, size: size, pick: pick)!.total, accuracy: 0.5)
        XCTAssertTrue(bought.buying)
        // Monthly costs: rent plus running costs plus the wages the start-up cost holds one month of.
        let m = try XCTUnwrap(e.monthlyFixedCostEstimate(tradeID: "cafe", cityID: city))
        XCTAssertEqual(m.lines.first?.label, "Rent")
        XCTAssertEqual(m.lines.first { $0.id == "wages" }?.amount, e.newCompanyPlan(tradeID: "cafe", cityID: city, size: size)!.estimate.firstPayroll)
        XCTAssertEqual(m.total, m.lines.reduce(0) { $0 + $1.amount }, accuracy: 0.01)
        XCTAssertEqual(e.monthlyFixedCostEstimate(tradeID: "cafe", cityID: city, premises: pick)?.lines.first?.label, "Mortgage payment")
    }

    // MARK: Hiring

    func testApplicantsShowOnlyWhatIsVisibleAndSearchesAreFree() throws {
        var e = try game()
        let id = try cafe(&e)
        let options = e.hiringSearchOptions()
        XCTAssertEqual(options.map(\.mode), [.ads, .agency])   // the network option is gone for the player
        XCTAssertTrue(options.allSatisfy { $0.fee == 0 }, "searching costs nothing in the game today")
        let cashBefore = e.state.company(id)!.cash
        let found = e.searchWorkers(companyID: id, role: "barista", mode: .ads)
        XCTAssertEqual(e.state.company(id)!.cash, cashBefore)
        XCTAssertTrue(Hiring.applicantsFound(.ads).contains(found.count))
        let board = e.hiringBoard(companyID: id, role: "barista", personIDs: found.map(\.id))
        XCTAssertEqual(board.applicants.count, found.count)
        XCTAssertEqual(board.marketMonthly, e.marketWage(role: "barista", companyID: id))
        for (a, p) in zip(board.applicants, found) {
            XCTAssertFalse(a.cvImpression.isEmpty, "the CV in words, never a number")
            XCTAssertEqual(a.claimedExperienceYears, e.claimedExperienceYears(personID: p.id))
            XCTAssertTrue(a.trialObservations.isEmpty)
            XCTAssertTrue(["Seasoned", "Eager", "Steady"].contains(a.seems))
        }
        XCTAssertNil(e.applicant(personID: -1, companyID: id))
    }
}
