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
            // Nothing was handed to the owner, so nothing is clawed back.
            s.companies[i].retainedCash = 0
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
            s.companies[i].payables = [:]; s.companies[i].vatBalance = 0
            let value = CompanyFigures.assets(s.companies[i])
            _ = addLoan(&s, company: id, balance: value * 10 + 1_000_000, guaranteed: true)
            hit = Failure.bankrupt(&s, companyIndex: i, reason: "cash", data: data, context: ctx)
        }
        XCTAssertGreaterThan(hit, 0)
        let taken = try XCTUnwrap(e.state.loans.first { $0.id == 9001 })
        XCTAssertEqual(taken.companyID, 0, "the owner now owes it personally")
        XCTAssertEqual(taken.balance, hit, accuracy: 0.01)
        XCTAssertEqual(e.state.company(id)?.num("clawBk") ?? -1, 0, accuracy: 0.01, "the guaranteed lender lost nothing, so nothing is clawed back")
    }

    /// Cash minus personal debts, plus what the owner spent personally, plus the company's things at forced-sale value.
    private func ownerWealth(_ s: GameState, spent: Double, company id: Int) -> Double {
        let things = s.company(id).map { $0.status.isLive ? max(0, CompanyFigures.assets($0)) * 0.45 : 0 } ?? 0
        return s.cash + spent - s.loans.filter { $0.companyID == 0 }.reduce(0) { $0 + $1.balance } + things
    }

    func testBorrowDrainAndBankruptcyNeverLeaveTheOwnerRicher() throws {
        var (e, id) = try start()
        var wealth0 = 0.0, spent = 0.0, claw = 0.0, borrowed = 0.0
        e.update { s, data, ctx in
            let i = s.companyIndex(id)!
            s.companies[i].payables = [:]; s.companies[i].vatBalance = 0
            wealth0 = ownerWealth(s, spent: 0, company: id)
            borrowed = max(0, CompanyFigures.assets(s.companies[i])) * 20 + 50_000_000
            _ = addLoan(&s, company: id, balance: borrowed)
            Payments.companyReceives(&s, companyID: id, amount: borrowed, category: nil, label: "Loan drawn")
            spent = s.cash - 1_000
            Payments.playerPays(&s, spent, label: "Bought a yacht")
            Failure.bankrupt(&s, companyIndex: i, reason: "loan", data: data, context: ctx)
            claw = s.companies[i].num("clawBk")
        }
        XCTAssertEqual(e.state.company(id)?.status, .bust)
        XCTAssertFalse(e.state.loans.contains { $0.id == 9001 }, "the unguaranteed loan ends with the company")
        XCTAssertGreaterThan(claw, borrowed * 0.9, "the borrowed money handed to the owner is taken back")
        XCTAssertLessThanOrEqual(ownerWealth(e.state, spent: spent, company: id), wealth0 + 1, "borrowing and going bankrupt never pays")
        let estate = try XCTUnwrap(e.state.loans.first { $0.name.hasPrefix("Owed to the estate") }, "what the account cannot pay becomes a personal debt")
        XCTAssertEqual(estate.companyID, 0)
        XCTAssertEqual(estate.balance, claw - 1_000, accuracy: 1)
        XCTAssertTrue(e.state.inbox.contains { $0.body.contains("taken back") })
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testAnUnguaranteedLoanLossFallsOnTheLenderMinusTheClawBack() throws {
        var (e, id) = try start()
        var cashBefore = 0.0, loss = 0.0
        let handedOver = 2_000_000.0
        e.update { s, data, ctx in
            let i = s.companyIndex(id)!
            s.companies[i].payables = [:]; s.companies[i].vatBalance = 0
            s.companies[i].retainedCash = 0
            let things = max(0, CompanyFigures.assets(s.companies[i])) * 0.45
            let balance = things + handedOver * 5
            _ = addLoan(&s, company: id, balance: balance)
            loss = balance - things
            Payments.companyReceives(&s, companyID: id, amount: handedOver, category: "rev", label: "Sales")
            cashBefore = s.cash
            Failure.bankrupt(&s, companyIndex: i, reason: "cash", data: data, context: ctx)
        }
        let clawed = e.state.company(id)?.num("clawBk") ?? 0
        XCTAssertEqual(clawed, handedOver, accuracy: 1, "only what the company handed over is taken back")
        XCTAssertEqual(e.state.cash, cashBefore - handedOver, accuracy: 1, "paid from the account")
        XCTAssertLessThan(clawed, loss, "the lender still carries the rest of its loss")
        XCTAssertFalse(e.state.loans.contains { $0.id == 9001 || $0.name.hasPrefix("Owed to the estate") })
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testClawBackCountsOnlyInsolventMonthsOfTheLastYear() throws {
        let (e, id) = try start()
        var co = try XCTUnwrap(e.state.company(id))
        let now = GameCalendar.monthIndex(week: e.state.week)
        func month(_ m: Int, _ sur: Double, insolvent: Bool) -> MonthRecord {
            var r = MonthRecord(monthIndex: m, revenue: 0, profit: 0, cash: 0)
            r.set("sur", sur); r.set("insol", insolvent)
            return r
        }
        co.monthlyHistory = [month(now - 14, 500, insolvent: true), month(now - 3, 800, insolvent: false), month(now - 1, 1_000, insolvent: true)]
        co.retainedCash = 1_600
        // 500 is older than a year; 300 came while it could pay its debts; 200 and the 600 since the last month end count.
        XCTAssertEqual(ClawBack.takenOut(e.state, co), 800, accuracy: 0.01)
    }

    func testASolventCompanyIsWoundUpWithEveryLoanRepaid() throws {
        var (e, id) = try start()
        e.update { s, _, _ in
            s.companies[s.companyIndex(id)!].payables = ["wages": 30_000]
            _ = addLoan(&s, company: id, balance: 5_000_000)
        }
        let cash0 = e.state.cash
        let t = try XCTUnwrap(e.windUpTerms(companyID: id))
        XCTAssertNil(t.refusal)
        XCTAssertGreaterThan(t.debts, 5_030_000 - 1)
        XCTAssertTrue(e.windUpCompany(companyID: id))
        XCTAssertFalse(e.state.loans.contains { $0.id == 9001 }, "repaid at closing")
        XCTAssertFalse(e.state.loans.contains { $0.companyID == 0 && $0.name.contains("Test loan") }, "nothing passes to the owner")
        XCTAssertEqual(e.state.cash, cash0 - t.fromAccount + t.toOwner, accuracy: 1)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testAnInsolventCompanyCannotBeWoundUpOnlyFiledBankrupt() throws {
        var (e, id) = try start()
        e.update { s, _, _ in
            let things = CompanyFigures.assets(s.companies[s.companyIndex(id)!])
            _ = addLoan(&s, company: id, balance: things * 10 + 1_000_000)
            Ledger.set(&s, to: 1_000)
        }
        let t = try XCTUnwrap(e.windUpTerms(companyID: id))
        XCTAssertEqual(t.refusal, GameEngine.insolventWindUp)
        XCTAssertTrue(t.refusal?.contains("owes more than it has") ?? false)
        XCTAssertFalse(e.windUpCompany(companyID: id), "a company that owes more than it has cannot be closed")
        XCTAssertEqual(e.state.company(id)?.status, .open)
        XCTAssertTrue(e.state.loans.contains { $0.id == 9001 }, "the loan is untouched")
        XCTAssertTrue(e.fileForBankruptcy(companyID: id))
        XCTAssertEqual(e.state.company(id)?.status, .bust)
        XCTAssertTrue(e.state.inbox.contains { $0.body.contains("You filed for bankruptcy") })
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testASolventCompanyCannotBeFiledBankrupt() throws {
        var (e, id) = try start()
        XCTAssertFalse(e.fileForBankruptcy(companyID: id), "a company that can pay its debts is closed, not filed bankrupt")
        XCTAssertEqual(e.state.company(id)?.status, .open)
    }

    func testBankLoansToAYoungOrThinCompanyNeedAPersonalGuarantee() throws {
        var (e, id) = try start()
        let cur = e.homeCurrency
        XCTAssertEqual(e.takeLoan(kind: "biz", amount: cur.scaledPrice(500_000), termMonths: 60, companyID: id), .ok)
        let young = try XCTUnwrap(e.state.loans.last { $0.companyID == id })
        XCTAssertTrue(young.isGuaranteed, "a company under two years old borrows only against the owner's guarantee")
        XCTAssertTrue(e.loanAssessment(kind: "biz", companyID: id).personalGuarantee)
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].foundedWeek = s.week - Banking.guaranteeAgeWeeks - 1
            s.companies[i].shareCapital = cur.scaledPrice(5_000_000)
        }
        XCTAssertEqual(e.takeLoan(kind: "biz", amount: cur.scaledPrice(200_000), termMonths: 60, companyID: id), .ok)
        let older = try XCTUnwrap(e.state.loans.last { $0.companyID == id })
        XCTAssertFalse(older.isGuaranteed, "an established company with enough share capital borrows on its own")
        e.update { s, _, _ in s.companies[s.companyIndex(id)!].shareCapital = 1 }
        XCTAssertEqual(e.takeLoan(kind: "biz", amount: cur.scaledPrice(200_000), termMonths: 60, companyID: id), .ok)
        XCTAssertTrue(try XCTUnwrap(e.state.loans.last { $0.companyID == id }).isGuaranteed, "a loan above the share capital needs a guarantee")
    }

    func testNoNewBankLoansForTwoYearsAfterABankruptcy() throws {
        var (e, id) = try start()
        e.update { s, data, ctx in
            Failure.bankrupt(&s, companyIndex: s.companyIndex(id)!, reason: "cash", data: data, context: ctx)
        }
        XCTAssertNotNil(Banking.loanBanUntil(e.state))
        XCTAssertEqual(e.loanOffer(kind: "cons", amount: 10_000, companyID: nil).maximum, 0)
        XCTAssertTrue(e.loanAssessment(kind: "cons", companyID: nil).refusal?.contains("bankruptcy") ?? false)
        XCTAssertTrue(e.state.inbox.contains { $0.body.contains("No new bank loans for two years") })
        e.update { s, _, _ in s.week += Banking.bankruptcyLoanBanWeeks }
        XCTAssertNil(Banking.loanBanUntil(e.state), "the ban ends after two years")
    }
}
