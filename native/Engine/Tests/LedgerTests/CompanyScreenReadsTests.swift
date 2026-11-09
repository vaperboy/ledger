import XCTest
import GameCore
import Finance
import Businesses
import Simulation

final class CompanyScreenReadsTests: XCTestCase {
    private func cafe() throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 11)
        e.update { s, _, _ in Ledger.move(&s, .me, 40_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, fundWith: 12_000_000) else {
            XCTFail("start"); throw XCTSkip("no company")
        }
        return (e, id)
    }

    func testLoanPaymentMatchesWhatTheBankSets() throws {
        var (e, id) = try cafe()
        let preview = e.companyLoanPayment(amount: 2_000_000, termMonths: 24, companyID: id)
        XCTAssertEqual(e.takeLoan(kind: "biz", amount: 2_000_000, termMonths: 24, companyID: id), .ok)
        let loan = try XCTUnwrap(e.state.loans.last { $0.companyID == id })
        XCTAssertEqual(loan.monthlyPayment, preview, accuracy: 1)
        XCTAssertGreaterThan(e.companyLoanPayment(amount: 2_000_000, termMonths: 12, companyID: id), preview, "a shorter term costs more a month")
    }
}
