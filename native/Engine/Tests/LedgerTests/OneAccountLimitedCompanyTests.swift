import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

/// One account, every company a limited company: no savings balance and no legal form in a save, salaries on the 15th with nobody to run or
/// approve them, owner pay taxed at source and capped by the company's own equity, and bankruptcy that pays lenders before the owner.
final class OneAccountLimitedCompanyTests: XCTestCase {
    private func start(seed: Int = 17) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 600_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, fundWith: 150_000_000) else { XCTFail("start"); throw XCTSkip("none") }
        _ = e.quickSetup(companyID: id); _ = e.openCompany(companyID: id)
        return (e, id)
    }

    private func addLoan(_ s: inout GameState, company id: Int, balance: Double, guaranteed: Bool = false) -> Int {
        var l = Loan(raw: [:])
        l.id = 9001; l.kind = "biz"; l.name = "Test loan"; l.balance = balance; l.originalAmount = balance
        l.companyID = id; l.monthlyPayment = 1000; l.termMonths = 36; l.isGuaranteed = guaranteed
        s.loans.append(l)
        return l.id
    }

    // MARK: One account, one legal form

    func testSaveHasNoSavingsBalanceAndNoLegalForm() throws {
        let (e, id) = try start()
        let json = try JSONDecoder().decode(JSONValue.self, from: try JSONEncoder().encode(e.state))
        XCTAssertTrue(json["sav"].isNull, "no savings balance is written")
        XCTAssertTrue(json["savFlow"].isNull)
        XCTAssertNil(e.state.company(id)?.raw["form"], "a company has no legal form field")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    // MARK: Pay day

    func testPayDayIsThe15thOrTheFridayBefore() {
        for year in 2026...2031 {
            for month in 0..<12 {
                let d = Payday.payDate(year: year, month: month)
                let c = Payday.civil(d)
                XCTAssertEqual(c.month, month + 1, "stays in its month")
                XCTAssertTrue((13...15).contains(c.day), "\(year)-\(month + 1): \(c.day)")
                XCTAssertLessThan(Payday.weekday(d), 5, "never a weekend")
                let fifteenth = GameCalendar.daysFromCivil(year: year, month: month + 1, day: 15)
                if Payday.weekday(fifteenth) < 5 { XCTAssertEqual(d, fifteenth, "a weekday 15th is the pay day") }
            }
        }
    }

    func testSalariesGoOutOnPayDayWithNobodyApprovingThem() throws {
        var (e, id) = try start()
        let salary = e.homeCurrency.scaledPrice(2_000)
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].ownerMonthlySalary = salary
        }
        let country = try XCTUnwrap(e.data.countries["UK"])
        var payDays: [Int] = []
        for _ in 0..<(70) {
            let outcome = e.nextDay()
            XCTAssertFalse(e.openDecisions.contains { $0.actionID == "pay29" || $0.actionID == "pay29all" }, "payroll never asks anyone")
            if outcome.newMessages.contains(where: { $0.title.hasPrefix("Payday:") }) { payDays.append(Payday.dayNumber(week: e.state.week, day: e.state.day)) }
            if !payDays.isEmpty { break }
        }
        let t = try XCTUnwrap(payDays.first, "payroll ran by itself")
        XCTAssertEqual(t, Payday.payDate(year: Payday.civil(t).year, month: Payday.civil(t).month - 1), "on the pay day")
        // The owner's pay was taxed at source on that payroll.
        XCTAssertEqual(e.state.tax.salary, salary, accuracy: 0.01)
        XCTAssertEqual(e.state.tax.withheld, Taxes.personalIncomeTax(salary * 12, kind: .wage, in: country) / 12, accuracy: 0.01)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testAShortPayrollIsPaidBackWhenMoneyArrives() throws {
        var (e, id) = try start()
        e.update { s, data, ctx in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].addPayable("wages", 50_000_000_000)
            Ledger.set(&s, .company(id), to: 10_000)
            let t = Payday.dayNumber(week: s.week, day: s.day)
            Payday.runPayroll(&s, i, today: t, data: data, context: ctx)
            XCTAssertGreaterThan(s.companies[i].payables["wages"] ?? 0, 1, "not paid in full")
            XCTAssertNotNil(Payday.config(s.companies[i], today: t).lateSince)
            Ledger.set(&s, .company(id), to: 60_000_000_000)
            Payday.backPay(&s, i, today: t)
            XCTAssertLessThan(s.companies[i].payables["wages"] ?? 0, 1, "paid back")
            XCTAssertNil(Payday.config(s.companies[i], today: t).lateSince)
        }
    }

    // MARK: Owner pay

    func testOwnerPayAboveWhatTheCompanyCanCarryIsRefused() throws {
        var (e, id) = try start()
        let room = e.ownerSalaryRoom(companyID: id)
        XCTAssertGreaterThan(room, 0)
        XCTAssertTrue(e.setOwnerSalary(companyID: id, monthly: room * 10 + 1_000_000_000).isRefused)
        XCTAssertEqual(e.state.company(id)?.ownerMonthlySalary, 0)
        XCTAssertFalse(e.setOwnerSalary(companyID: id, monthly: room / 2).isRefused)
        XCTAssertGreaterThan(e.state.company(id)?.ownerMonthlySalary ?? 0, 0)
    }

    func testBorrowedCashDoesNotRaiseWhatCanBePaidAsSalary() throws {
        var (e, id) = try start()
        let before = e.ownerSalaryRoom(companyID: id)
        e.update { s, _, _ in
            _ = addLoan(&s, company: id, balance: 500_000_000)
            Ledger.set(&s, .company(id), to: (s.company(id)?.cash ?? 0) + 500_000_000)
        }
        XCTAssertEqual(e.ownerSalaryRoom(companyID: id), before, accuracy: 1, "the loan adds cash and the same debt")
        XCTAssertTrue(e.setOwnerSalary(companyID: id, monthly: before * 10 + 1_000_000_000).isRefused)
    }

    func testOwnerPayIsTaxedAsWageAndTheYearEndNeverRefundsMoreThanWasWithheld() throws {
        var (e, _) = try start()
        e.update { s, _, ctx in
            s.tax = PersonalTaxYear(raw: ["wage": 0, "ytdDiv": 0, "withheld": 5_000, "gain": 0, "int": 0, "shield": 0])
            let b = PersonalFinance.breakdown(s, context: ctx, netWorth: 0, ownedCompanyValue: 0)
            XCTAssertGreaterThanOrEqual(b.incomeDue, -5_000, "a refund is at most what was withheld")
            s.tax.salary = 60_000
            let tax = Taxes.personalIncomeTax(60_000, kind: .wage, in: ctx.homeCountry(s))
            XCTAssertEqual(PersonalFinance.breakdown(s, context: ctx, netWorth: 0, ownedCompanyValue: 0).incomeTax, tax, accuracy: 0.01)
        }
    }

    // MARK: Company tax

    func testEveryCompanyPaysCorporateTaxOnItsProfit() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 11)
        e.update { s, _, _ in Ledger.move(&s, .me, 900_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, fundWith: 5_000_000) else { return XCTFail("start") }
        let profit = 12_000_000.0
        e.update { s, data, ctx in
            let i = s.companyIndex(id)!
            s.companies[i].status = .open
            s.companies[i].payables["tax"] = 0
            Ledger.moveRaw(&s, .company(id), 100_000_000)
            let rate = data.countries.resolve(s.companies[i].countryCode, orHome: s.homeCountryCode).corporateTax
            for _ in 0..<12 {
                var b = s.companies[i].books
                b.month = ["rev": profit / 12]
                s.companies[i].books = b
                MonthEnd.closeMonth(&s, companyIndex: i, data: data, context: ctx)
            }
            XCTAssertEqual(s.companies[i].taxAccrued, profit * rate, accuracy: 1, "every company is a limited company: rate times profit")
        }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    // MARK: Bankruptcy

    func testLendersAreRepaidBeforeTheOwnerGetsAnythingBack() throws {
        var (e, id) = try start()
        var cashBefore = 0.0
        e.update { s, data, ctx in
            let i = s.companyIndex(id)!
            s.companies[i].payables = [:]
            let value = CompanyFigures.assets(s.companies[i])
            _ = addLoan(&s, company: id, balance: value * 10 + 1_000_000)   // far more than the company owns
            cashBefore = s.cash
            Failure.bankrupt(&s, companyIndex: i, reason: "cash", data: data, context: ctx)
        }
        XCTAssertEqual(e.state.company(id)?.status, .bust)
        XCTAssertEqual(e.state.cash, cashBefore, accuracy: 0.01, "nothing is left for the owner while a lender is unpaid")
        XCTAssertFalse(e.state.loans.contains { $0.id == 9001 }, "an unguaranteed loan dies with the company")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testTheOwnerGetsAShareOnlyAfterEveryLenderIsPaidInFull() throws {
        var (e, id) = try start()
        var cashBefore = 0.0
        e.update { s, data, ctx in
            let i = s.companyIndex(id)!
            s.companies[i].payables = [:]
            Ledger.set(&s, .company(id), to: 100_000_000)
            _ = addLoan(&s, company: id, balance: 1_000_000)
            cashBefore = s.cash
            Failure.bankrupt(&s, companyIndex: i, reason: "cash", data: data, context: ctx)
        }
        XCTAssertFalse(e.state.loans.contains { $0.id == 9001 }, "the lender is paid in full")
        XCTAssertGreaterThan(e.state.cash, cashBefore, "what is left reaches the owner")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testAGuaranteedLoanLeftUnpaidLandsOnTheOwner() throws {
        var (e, id) = try start()
        var hit = 0.0
        e.update { s, data, ctx in
            let i = s.companyIndex(id)!
            s.companies[i].payables = [:]
            let value = CompanyFigures.assets(s.companies[i])
            _ = addLoan(&s, company: id, balance: value * 10 + 1_000_000, guaranteed: true)
            hit = Failure.bankrupt(&s, companyIndex: i, reason: "cash", data: data, context: ctx)
        }
        XCTAssertGreaterThan(hit, 0)
        let taken = try XCTUnwrap(e.state.loans.first { $0.id == 9001 })
        XCTAssertEqual(taken.companyID, 0, "the owner now owes it personally")
        XCTAssertEqual(taken.balance, hit, accuracy: 0.01)
    }
}
