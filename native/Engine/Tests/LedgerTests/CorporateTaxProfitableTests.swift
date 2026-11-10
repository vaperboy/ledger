import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

final class CorporateTaxProfitableTests: XCTestCase {
    func testProfitableLimitedCompanyPaysRateTimesProfitAfterLossCarryInEveryCountry() throws {
        let codes = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 1).data.countries.countries.map { $0.code }
        XCTAssertEqual(codes.count, 23)
        for code in codes {
            var e = try GameEngine.newGame(countryCode: code, playerName: "T", seed: 11)
            e.update { s, _, _ in Ledger.move(&s, .me, 900_000_000, why: "Test funds") }
            guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, fundWith: 5_000_000) else {
                XCTFail("\(code): cafe could not be started"); continue
            }
            let profit = 12_000_000.0, carry = 3_000_000.0
            e.update { s, data, ctx in
                let i = s.companyIndex(id)!
                s.companies[i].status = .open
                s.companies[i].lossCarryForward = carry
                s.companies[i].payables["tax"] = 0
                Ledger.moveRaw(&s, .company(id), 100_000_000)
                let rate = data.countries.resolve(s.companies[i].countryCode, orHome: s.homeCountryCode).corporateTax
                XCTAssertGreaterThan(rate, 0.05, code); XCTAssertLessThan(rate, 0.5, code)
                let cash0 = s.companies[i].cash, paid0 = s.stats.taxPaid
                for _ in 0..<12 {
                    var b = s.companies[i].books
                    b.month = ["rev": profit / 12]
                    s.companies[i].books = b
                    MonthEnd.closeMonth(&s, companyIndex: i, data: data, context: ctx)
                }
                let expected = (profit - carry) * rate
                let co = s.companies[i]
                XCTAssertEqual(co.taxAccrued, expected, accuracy: 1, "\(code) accrual")
                XCTAssertEqual(co.payables["tax"] ?? 0, 0, accuracy: 1, "\(code) nothing left owing: paid as it arose")
                XCTAssertEqual(cash0 - co.cash, expected, accuracy: 2, "\(code) tax paid out of the account during the year")
                XCTAssertEqual(s.stats.taxPaid - paid0, expected, accuracy: 2, "\(code) counted as tax paid")
                XCTAssertEqual(co.lossCarryForward, 0, accuracy: 1e-6, "\(code) loss used up")
                MonthEnd.closeYear(&s, data: data, context: ctx)
                let c2 = s.companies[s.companyIndex(id)!]
                XCTAssertFalse(c2.taxDue, "\(code) no arrears at the year end")
                XCTAssertEqual(c2.taxPrevYear, 0, accuracy: 1, code)
                var b = s.companies[i].books; b.month = [:]; s.companies[i].books = b
                let before = s.companies[i].cash
                MonthEnd.closeMonth(&s, companyIndex: i, data: data, context: ctx)
                XCTAssertEqual(s.companies[i].cash, before, accuracy: 1, "\(code) nothing more to pay")
            }
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(code) ledger gaps")
        }
    }

    func testTaxPaidOnProfitSoFarIsRefundedWhenTheYearTurnsToALoss() throws {
        var e = try GameEngine.newGame(countryCode: "US", playerName: "T", seed: 12)
        e.update { s, _, _ in Ledger.move(&s, .me, 900_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, fundWith: 5_000_000) else { return XCTFail("cafe") }
        e.update { s, data, ctx in
            let i = s.companyIndex(id)!
            s.companies[i].status = .open
            s.companies[i].payables["tax"] = 0
            Ledger.moveRaw(&s, .company(id), 100_000_000)
            let cash0 = s.companies[i].cash
            for m in 0..<12 {
                var b = s.companies[i].books
                b.month = m < 6 ? ["rev": 2_000_000] : ["oth": 4_000_000]
                s.companies[i].books = b
                MonthEnd.closeMonth(&s, companyIndex: i, data: data, context: ctx)
                if m == 5 { XCTAssertLessThan(s.companies[i].cash, cash0, "tax was paid on the profit so far") }
            }
            XCTAssertEqual(s.companies[i].taxAccrued, 0, accuracy: 1)
            XCTAssertEqual(s.companies[i].cash, cash0, accuracy: 2, "everything paid came back")
            XCTAssertEqual(s.companies[i].lossCarryForward, 12_000_000, accuracy: 1, "the year's loss is carried forward")
        }
    }
}
