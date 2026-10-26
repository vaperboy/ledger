import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

/// Audit part 2: a profitable limited company for one fiscal year in each of the 23 countries.
/// Tax = rate x (profit - loss carried forward), accrued month by month, settled once due (26 weeks after year end).
final class CorporateTaxProfitableTests: XCTestCase {
    func testProfitableLimitedCompanyPaysRateTimesProfitAfterLossCarryInEveryCountry() throws {
        let codes = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 1).data.countries.countries.map { $0.code }
        XCTAssertEqual(codes.count, 23)
        for code in codes {
            var e = try GameEngine.newGame(countryCode: code, playerName: "T", seed: 11)
            e.update { s, _, _ in Ledger.move(&s, .me, 900_000_000, why: "Test funds") }
            guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 5_000_000) else {
                XCTFail("\(code): cafe could not be started"); continue
            }
            let profit = 12_000_000.0, carry = 3_000_000.0
            e.update { s, data, ctx in
                let i = s.companyIndex(id)!
                s.companies[i].status = .open
                s.companies[i].lossCarryForward = carry
                s.companies[i].payables["tax"] = 0
                let rate = data.countries.resolve(s.companies[i].countryCode, orHome: s.homeCountryCode).corporateTax
                XCTAssertGreaterThan(rate, 0.05, code); XCTAssertLessThan(rate, 0.5, code)
                for _ in 0..<12 {
                    var b = s.companies[i].books
                    b.month = ["rev": profit / 12]
                    s.companies[i].books = b
                    MonthEnd.closeMonth(&s, companyIndex: i, data: data, context: ctx)
                }
                let expected = (profit - carry) * rate
                let co = s.companies[i]
                XCTAssertEqual(co.taxAccrued, expected, accuracy: 1, "\(code) accrual")
                XCTAssertEqual(co.payables["tax"] ?? 0, expected, accuracy: 1, "\(code) payable")
                XCTAssertEqual(co.lossCarryForward, 0, accuracy: 1e-6, "\(code) loss used up")
                MonthEnd.closeYear(&s, data: data, context: ctx)
                let c2 = s.companies[s.companyIndex(id)!]
                XCTAssertTrue(c2.taxDue, code)
                XCTAssertEqual(c2.taxPrevYear, expected, accuracy: 1, code)
                XCTAssertEqual(c2.taxDueWeek, s.week + 26, code)
                // Not paid early: a month end before the due week leaves the cash alone.
                Ledger.moveRaw(&s, .company(id), 100_000_000)
                s.week = c2.taxDueWeek - 1
                var b = s.companies[i].books; b.month = [:]; s.companies[i].books = b
                let before = s.companies[i].cash
                MonthEnd.closeMonth(&s, companyIndex: i, data: data, context: ctx)
                XCTAssertEqual(s.companies[i].cash, before, accuracy: 1, "\(code) not paid before the due week")
                s.week = c2.taxDueWeek
                let cashBefore = s.companies[i].cash
                MonthEnd.closeMonth(&s, companyIndex: i, data: data, context: ctx)
                XCTAssertEqual(cashBefore - s.companies[i].cash, expected, accuracy: 2, "\(code) paid on the due date")
                XCTAssertFalse(s.companies[i].taxDue, code)
                XCTAssertEqual(s.companies[i].payables["tax"] ?? 0, 0, accuracy: 1, code)
            }
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(code) ledger gaps")
        }
    }
}
