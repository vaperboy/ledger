import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

/// Fixes from the financial-engine audit, plus the case a profitable business still runs out of cash.
/// These tests were written by tracing the code (no Swift toolchain was available when they were added).
final class FinancialEngineFixesTests: XCTestCase {
    private func cafe(seed: Int = 7) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 500_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 5_000_000) else {
            XCTFail("cafe could not be started"); throw XCTSkip("no cafe")
        }
        return (e, id)
    }

    /// Selling equipment below book value is a loss in the books (it lowers taxable profit), not a silent write-down.
    func testSellingEquipmentBelowBookValueBooksTheLoss() throws {
        var (e, id) = try cafe()
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].set("eq", .object(["oven": .object(["n": .number(1), "bv": .number(10_000), "cost": .number(20_000)])]))
            var b = s.companies[i].books; b.year = [:]; b.month = [:]; s.companies[i].books = b
        }
        let cash0 = e.state.company(id)!.cash
        var got = 0.0
        e.update { s, _, _ in got = EquipmentMarket.sellAll(&s, companyID: id, equipmentID: "oven") }
        XCTAssertEqual(got, 7_000, accuracy: 1)
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(co.cash - cash0, 7_000, accuracy: 1)
        XCTAssertEqual(co.books.year["loss"] ?? 0, 3_000, accuracy: 1, "book value 10000 sold for 7000")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    /// Repaying a personal loan when the current account is short draws on savings instead of overdrawing.
    func testPersonalLoanRepaymentUsesSavings() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 11)
        var loanID = 0
        e.update { s, _, _ in
            var l = Loan(raw: [:])
            l.id = s.makeID(); l.kind = "cons"; l.balance = 10_000; l.companyID = 0; l.monthlyPayment = 500
            s.loans.append(l); loanID = l.id
            Ledger.set(&s, .me, to: 1_000)
            s.savings = 20_000
        }
        var ok = false
        e.update { s, _, _ in ok = Banking.repay(loanID: loanID, amount: 10_000, state: &s) }
        XCTAssertTrue(ok)
        XCTAssertGreaterThanOrEqual(e.state.cash, 0, "the rest came over from savings")
        XCTAssertNil(e.state.loans.first { $0.id == loanID }, "the repaid loan is gone (the start-up loan remains)")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    /// Bills short for four months, or tax unpaid for six, count as long unpaid (the weekly check then closes the company).
    func testLongUnpaidBillsAreDetected() throws {
        let (e, id) = try cafe(seed: 9)
        let co = try XCTUnwrap(e.state.company(id))
        let t = Payday.dayNumber(week: e.state.week, day: e.state.day)
        var cfg = Payday.config(co, today: t)
        cfg.billShortMonths = 3
        var c1 = co; c1.set("pr29", cfg.json)
        XCTAssertFalse(Payday.unpaidForMonths(c1, today: t), "three months short is not yet enough")
        cfg.billShortMonths = 4
        var c2 = co; c2.set("pr29", cfg.json)
        XCTAssertTrue(Payday.unpaidForMonths(c2, today: t))
        var c3 = co; c3.unpaidMonths = 6
        XCTAssertTrue(Payday.unpaidForMonths(c3, today: t))
    }

    /// A profitable business can still run out of cash: customers have not paid yet, so profit sits in receivables
    /// while payroll and bills fall due. Payroll stops at the overdraft room, wages are owed (late), and the books stay balanced.
    func testProfitableButOutOfCash() throws {
        var (e, id) = try cafe(seed: 5)
        var room = 0.0
        e.update { s, _, ctx in
            let i = s.companyIndex(id)!
            Ledger.moveRaw(&s, .company(id), -s.companies[i].cash)                       // no cash at all
            var b = s.companies[i].books
            b.month = [:]; b.year = [:]
            b.add("rev", 10_000_000); b.add("cogs", 2_000_000); b.add("wages", 1_000_000)  // a clearly profitable month
            s.companies[i].books = b
            s.companies[i].receivables = [Receivable(amount: 9_000_000, dueWeek: s.week + 6, willDefault: false)]
            s.companies[i].payables = ["wages": 1e12, "other": 1e12, "rent": 1e12]        // far more than the account can take
            room = ctx.overdraftRoom(s.companies[i], s)
        }
        let before = try XCTUnwrap(e.state.company(id))
        XCTAssertGreaterThan(Books.profit(before.books.month), 0, "profitable on paper")
        XCTAssertGreaterThan(before.receivables.reduce(0) { $0 + $1.amount }, 0)
        XCTAssertEqual(before.cash, 0, accuracy: 1)

        e.update { s, data, ctx in
            let i = s.companyIndex(id)!
            let t = Payday.dayNumber(week: s.week, day: s.day)
            let r = Payday.runPayroll(&s, i, how: .manual, today: t, data: data, context: ctx)
            XCTAssertGreaterThan(r.short, 0, "payroll could not be paid in full")
            _ = Payday.payBills(&s, i, today: t, context: ctx)
        }
        let after = try XCTUnwrap(e.state.company(id))
        let t = Payday.dayNumber(week: e.state.week, day: e.state.day)
        XCTAssertGreaterThanOrEqual(after.cash, -room - 1, "never beyond the overdraft room")
        XCTAssertLessThan(after.cash, 0, "the account is overdrawn although the month was profitable")
        XCTAssertNotNil(Payday.config(after, today: t).lateSince, "wages are late")
        XCTAssertGreaterThan(after.wageShortfall, 0)
        XCTAssertGreaterThan(after.payables["wages"] ?? 0, 0, "wages are still owed")
        XCTAssertEqual(after.receivables.count, 1, "the cash is still with the customers")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }
}
