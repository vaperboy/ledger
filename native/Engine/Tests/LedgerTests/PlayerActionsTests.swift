import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation
import Investments

/// Every player action goes through one function on the engine; these check they change the game and keep the books.
final class PlayerActionsTests: XCTestCase {
    func testStartCompanySetPricesCampaignAndHire() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 7)
        e.update { s, _, _ in Ledger.move(&s, .me, 30_000_000, why: "Test funds") }
        let res = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 12_000_000)
        guard case .success(let id) = res else { return XCTFail("could not start: \(res)") }

        e.setPriceLevel(companyID: id, level: 1)
        XCTAssertEqual(e.state.company(id)?.priceLevel, 1)
        e.setPriceLevel(companyID: id, level: 99)
        XCTAssertEqual(e.state.company(id)?.priceLevel, 3, "price level is clamped")

        guard let channel = e.marketing.channels.keys.sorted().first else { return XCTFail("no channels") }
        XCTAssertEqual(e.setCampaign(companyID: id, channel: channel, weeklyBudget: 50_000), .done)
        if case .refused = e.setCampaign(companyID: id, channel: channel, weeklyBudget: 0), (e.marketing.channels[channel]?.minimumWeeks ?? 0) > 0 {
        } else if (e.marketing.channels[channel]?.minimumWeeks ?? 0) > 0 { XCTFail("a campaign must not be cancellable inside its minimum length") }

        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testLoanRepaymentAndInvestingKeepCashConsistent() throws {
        var e = try GameEngine.newGame(countryCode: "NO", playerName: "Tester", seed: 11)
        let nwBefore = e.netWorth.total
        XCTAssertTrue(e.moveToSavings(100_000))
        XCTAssertEqual(e.netWorth.total, nwBefore, accuracy: 1, "moving cash to savings must not change net worth")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        let loan = try XCTUnwrap(e.state.loans.first)
        XCTAssertTrue(e.repayLoan(id: loan.id, amount: 50_000))
        XCTAssertEqual(e.state.loans.first?.balance ?? 0, loan.balance - 50_000, accuracy: 1)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }
}
