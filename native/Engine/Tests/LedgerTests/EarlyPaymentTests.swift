import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Simulation

/// Bank > Bills "Pay now": a bill paid early is charged once, and its due date charges nothing more for it.
final class EarlyPaymentTests: XCTestCase {
    private func game() throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        e.update { s, _, _ in Ledger.move(&s, .me, 500_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 50_000_000) else { throw XCTSkip("no company") }
        return (e, id)
    }

    private func obligation(_ e: GameEngine, _ id: Int, _ prefix: String) -> Obligation? {
        e.financeOverview(companyID: id).upcoming.first { $0.companyID == id && $0.id.hasPrefix(prefix) }
    }

    func testRentAndSupplierBillsPaidEarlyAreChargedOnceAndNotAgainOnTheDate() throws {
        var (e, id) = try game()
        var days = 0
        while obligation(e, id, "bills") == nil, days < 90 { e.nextDay(); days += 1 }
        let o = try XCTUnwrap(obligation(e, id, "bills"), "rent and supplier bills build up")
        let cash0 = e.state.company(id)!.cash
        let tx0 = e.state.company(id)!.transactions.count
        guard case .paid(let paid) = e.payObligationNow(o) else { return XCTFail("should be paid") }
        XCTAssertEqual(paid, o.amount, accuracy: 1)
        let co = e.state.company(id)!
        XCTAssertEqual(co.cash, cash0 - paid, accuracy: 1, "charged once")
        XCTAssertLessThan(co.payables["rent"] ?? 0, 1)
        XCTAssertLessThan(co.payables["other"] ?? 0, 1)
        XCTAssertGreaterThan(co.transactions.count, tx0)
        XCTAssertNil(obligation(e, id, "bills"), "nothing left to pay on the date")
        // The date arrives: the month-end bill run finds nothing owed.
        var again = (paid: 1.0, short: 1.0)
        let day = Payday.dayNumber(week: e.state.week, day: e.state.day)
        let cashBefore = e.state.company(id)!.cash
        e.update { s, d, ctx in again = Payday.payBills(&s, s.companyIndex(id)!, today: day, context: ctx, data: d) }
        XCTAssertEqual(again.paid, 0)
        XCTAssertEqual(again.short, 0)
        XCTAssertEqual(e.state.company(id)!.cash, cashBefore, accuracy: 0.01)
        // Paying again is refused, not charged.
        XCTAssertEqual(e.payObligationNow(o), .refused("Nothing is owed on rent or supplier bills."))
    }

    func testSupplierInvoicePaidEarlyIsNotChargedWhenItFallsDue() throws {
        var (e, id) = try game()
        var invoiceID = 0
        e.update { s, _, _ in invoiceID = SupplyTerms.issue(&s, buyer: id, provider: 0, vendorID: "v", name: "Test Wholesale", kind: "goods", amount: 120_000, weeks: 3) ?? 0 }
        XCTAssertNotEqual(invoiceID, 0)
        let o = try XCTUnwrap(obligation(e, id, "inv"))
        let cash0 = e.state.company(id)!.cash
        XCTAssertEqual(e.payObligationNow(o), .paid(amount: 120_000))
        XCTAssertEqual(e.state.company(id)!.cash, cash0 - 120_000, accuracy: 0.01)
        XCTAssertTrue(SupplyTerms.invoices(e.state, buyer: id).isEmpty)
        XCTAssertLessThan(e.state.company(id)!.payables["inv"] ?? 0, 1)
        // Weeks pass beyond the due week: the weekly run has nothing to collect.
        let cash1 = e.state.company(id)!.cash
        e.update { s, d, ctx in s.week += 4; SupplyTerms.weekly(&s, data: d, context: ctx) }
        XCTAssertEqual(e.state.company(id)!.cash, cash1, accuracy: 0.01, "not charged a second time")
    }

    func testCorporateTaxPaidEarlyIsNotChargedOnTheDueDate() throws {
        var (e, id) = try game()
        let amount = 800_000.0
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].payables["tax"] = amount
            s.companies[i].taxPrevYear = amount
            s.companies[i].taxDue = true
            s.companies[i].taxDueWeek = s.week + 6
        }
        let o = try XCTUnwrap(obligation(e, id, "ctax"))
        let cash0 = e.state.company(id)!.cash, paid0 = e.state.stats.taxPaid
        XCTAssertEqual(e.payObligationNow(o), .paid(amount: amount))
        XCTAssertEqual(e.state.company(id)!.cash, cash0 - amount, accuracy: 0.01)
        XCTAssertEqual(e.state.stats.taxPaid, paid0 + amount, accuracy: 0.01)
        XCTAssertFalse(e.state.company(id)!.taxDue)
        XCTAssertLessThan(e.state.company(id)!.payables["tax"] ?? 0, 1)
        XCTAssertNil(obligation(e, id, "ctax"))
        let cash1 = e.state.company(id)!.cash
        var left = -1.0
        e.update { s, _, ctx in s.week += 7; left = MonthEnd.settleTax(&s, companyIndex: s.companyIndex(id)!, context: ctx) }
        XCTAssertEqual(left, 0)
        XCTAssertEqual(e.state.company(id)!.cash, cash1, accuracy: 0.01, "the due date charges nothing more")
    }

    func testVATPaidEarlyClearsTheReturnAndRefusesWhenTheAccountCannotCoverIt() throws {
        var (e, id) = try game()
        e.update { s, _, _ in s.companies[s.companyIndex(id)!].vatBalance = 90_000 }
        let o = try XCTUnwrap(obligation(e, id, "vat"))
        let cash0 = e.state.company(id)!.cash, paid0 = e.state.stats.taxPaid
        XCTAssertEqual(e.payObligationNow(o), .paid(amount: 90_000))
        let co = e.state.company(id)!
        XCTAssertEqual(co.cash, cash0 - 90_000, accuracy: 0.01)
        XCTAssertEqual(co.vatBalance, 0)
        XCTAssertEqual(e.state.stats.taxPaid, paid0 + 90_000, accuracy: 0.01)
        XCTAssertNil(obligation(e, id, "vat"))
        // Too little money: nothing moves.
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].vatBalance = 90_000
            s.companies[i].cash = -1e12
        }
        let broke = e.state.company(id)!.cash
        if case .refused = e.payObligationNow(Obligation(id: "vat\(id)", title: "", detail: "", amount: 90_000, dayNumber: 0, dateText: "", daysAway: 0, essential: true, companyID: id, kind: .tax)) {} else { XCTFail("should refuse") }
        XCTAssertEqual(e.state.company(id)!.cash, broke)
        XCTAssertEqual(e.state.company(id)!.vatBalance, 90_000)
    }

    func testAddOnMonthlyCostIsTheWeeklyOverheadTimesFiftyTwoOverTwelve() throws {
        let (e, id) = try game()
        let co = try XCTUnwrap(e.state.company(id))
        let bd = try XCTUnwrap(e.data.catalog[co.type])
        for k in bd.knobs where k.isMulti {
            for (n, o) in k.options.enumerated() {
                let m = try XCTUnwrap(e.knobOptionMonthlyCost(companyID: id, knob: k.id, option: n))
                XCTAssertEqual(m, (o.effects["w"] ?? 0) * e.state.economy.inflationIndex * 52 / 12, accuracy: 0.001)
                XCTAssertEqual(e.knobToggleQuote(companyID: id, knob: k.id, option: n, on: true)?.monthlyRunningCost ?? 0, m, accuracy: 0.001)
            }
        }
    }
}
