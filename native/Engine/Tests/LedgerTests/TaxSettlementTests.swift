import XCTest
import GameCore
import Countries
import Finance
@testable import Simulation

final class TaxSettlementTests: XCTestCase {
    private func game() throws -> GameEngine {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        e.update { s, _, _ in
            Ledger.set(&s, to: 0)
            s.loans.removeAll()
            s.tax = PersonalTaxYear(raw: ["ytd": 0, "paid": 0, "wage": 0, "div": 0, "ytdDiv": 0, "withheld": 0, "gain": 0, "int": 0, "shield": 0])
        }
        return e
    }

    func testBillBeyondTheAccountsAsksBeforeAnythingIsForced() throws {
        var e = try game()
        e.update { s, _, ctx in
            s.tax.gains = ctx.homeCurrency(s).scaledPrice(100_000_000)
            PersonalFinance.yearEnd(&s, context: ctx, netWorth: 0, ownedCompanyValue: 0)
            XCTAssertGreaterThan(s.tax.pending, 0)
            XCTAssertGreaterThanOrEqual(s.cash, -s.overdraftLimit, "the unpaid part is not charged to the account")
            XCTAssertTrue(s.inbox.contains { $0.status == "open" && $0.actionID == PersonalFinance.dueAction })
        }
        let id = e.state.inbox.first { $0.actionID == PersonalFinance.dueAction }!.id
        let owed = e.state.tax.pending
        XCTAssertTrue(e.answer(messageID: id, option: 2), "a payment plan is allowed")
        XCTAssertEqual(e.state.tax.pending, 0)
        XCTAssertEqual(e.state.loans.first { $0.name == "Tax payment plan" }?.balance ?? 0, owed, accuracy: 1)
    }

    func testRefusingTakesTheBalanceFromTheAccount() throws {
        var e = try game()
        e.update { s, _, ctx in
            s.tax.gains = ctx.homeCurrency(s).scaledPrice(100_000_000)
            PersonalFinance.yearEnd(&s, context: ctx, netWorth: 0, ownedCompanyValue: 0)
        }
        let id = e.state.inbox.first { $0.actionID == PersonalFinance.dueAction }!.id
        let cash0 = e.state.cash, owed = e.state.tax.pending
        XCTAssertTrue(e.answer(messageID: id, option: 3))
        XCTAssertEqual(e.state.tax.pending, 0)
        XCTAssertEqual(cash0 - e.state.cash, owed, accuracy: 1)
    }

    func testMonthlyEstimateIsStoredAndTheCreditLineGrowsWithWealth() throws {
        var e = try game()
        e.update { s, data, ctx in
            let cur = ctx.homeCurrency(s)
            let base = cur.scaledPrice(25000)
            s.credit = 70
            Ledger.move(&s, .me, cur.scaledPrice(500_000_000), why: "Test funds")
            s.tax.dividends = cur.scaledPrice(1_000_000)
            TaxSettlement.refresh(&s, data: data, context: ctx)
            XCTAssertNotNil(PersonalFinance.storedEstimate(s))
            XCTAssertGreaterThan(PersonalFinance.storedEstimate(s)?.dividendTax ?? 0, 0)
            XCTAssertGreaterThan(s.overdraftLimit, base, "wealth raises the line")
        }
        XCTAssertGreaterThan(e.taxEstimate().total, 0)
    }

    func testWarningWhenTheBillExceedsLiquidFundsNearYearEnd() throws {
        var e = try game()
        e.update { s, data, ctx in
            while PersonalFinance.weeksToYearEnd(week: s.week) > 6 { s.week += 1 }
            s.tax.gains = ctx.homeCurrency(s).scaledPrice(10_000_000)
            TaxSettlement.refresh(&s, data: data, context: ctx)
            XCTAssertTrue(s.inbox.contains { $0.title.contains("tax settlement") }, "an inbox warning")
        }
    }
}
