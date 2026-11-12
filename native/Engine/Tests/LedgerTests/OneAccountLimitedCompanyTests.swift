import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

final class OneAccountLimitedCompanyTests: XCTestCase {
    private func start(seed: Int = 17) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 600_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID) else { XCTFail("start"); throw XCTSkip("none") }
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

    func testSaveHasNoSavingsBalanceAndNoLegalForm() throws {
        let (e, id) = try start()
        let json = try JSONDecoder().decode(JSONValue.self, from: try JSONEncoder().encode(e.state))
        XCTAssertTrue(json["sav"].isNull, "no savings balance is written")
        XCTAssertTrue(json["savFlow"].isNull)
        XCTAssertNil(e.state.company(id)?.raw["form"], "a company has no legal form field")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

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

    func testAShortPayrollIsPaidBackWhenMoneyArrives() throws {
        var (e, id) = try start()
        e.update { s, data, ctx in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].addPayable("wages", 50_000_000_000)
            Ledger.set(&s, to: 10_000)
            let t = Payday.dayNumber(week: s.week, day: s.day)
            Payday.runPayroll(&s, i, today: t, data: data, context: ctx)
            XCTAssertGreaterThan(s.companies[i].payables["wages"] ?? 0, 1, "not paid in full")
            XCTAssertNotNil(Payday.config(s.companies[i], today: t).lateSince)
            Ledger.set(&s, to: 60_000_000_000)
            Payday.backPay(&s, i, today: t)
            XCTAssertLessThan(s.companies[i].payables["wages"] ?? 0, 1, "paid back")
            XCTAssertNil(Payday.config(s.companies[i], today: t).lateSince)
        }
    }

    func testWageIsTaxedAndTheYearEndNeverRefundsMoreThanWasWithheld() throws {
        var (e, _) = try start()
        e.update { s, _, ctx in
            s.tax = PersonalTaxYear(raw: ["wage": 0, "ytdDiv": 0, "withheld": 5_000, "gain": 0, "int": 0, "shield": 0])
            let b = PersonalFinance.breakdown(s, context: ctx, netWorth: 0, ownedCompanyValue: 0)
            XCTAssertGreaterThanOrEqual(b.incomeDue, -5_000, "a refund is at most what was withheld")
            s.tax.salary = 60_000
            let tax = Taxes.personalIncomeTax(60_000, in: ctx.homeCountry(s))
            XCTAssertEqual(PersonalFinance.breakdown(s, context: ctx, netWorth: 0, ownedCompanyValue: 0).incomeTax, tax, accuracy: 0.01)
        }
    }

    func testEveryCompanyPaysCorporateTaxOnItsProfit() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 11)
        e.update { s, _, _ in Ledger.move(&s, .me, 900_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID) else { return XCTFail("start") }
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

    func testLendersAreRepaidBeforeTheOwnerGetsAnythingBack() throws {
        var (e, id) = try start()
        var cashBefore = 0.0
        e.update { s, data, ctx in
            let i = s.companyIndex(id)!
            s.companies[i].payables = [:]
            let value = CompanyFigures.assets(s.companies[i])
            _ = addLoan(&s, company: id, balance: value * 10 + 1_000_000)
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
            _ = addLoan(&s, company: id, balance: 100)
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
