import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation
import Investments
import Events

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

final class PreviewAndAdvisorTests: XCTestCase {
    func testEffectPreviewDescribesOnlyWhatTheDataDoes() throws {
        let e = try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 3)
        let fx: JSONValue = .object(["cash": -5000, "rep": 3, "dem": .array([0.9, 4])])
        let lines = EffectPreview.lines(fx, currency: e.homeCurrency)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasPrefix("Costs"))
        XCTAssertTrue(lines.contains("+3 reputation"))
        XCTAssertTrue(lines.contains("Demand −10% for 4 weeks"))
        XCTAssertTrue(EffectPreview.lines(.null, currency: e.homeCurrency).isEmpty)
    }

    func testFirstStepsAndSuggestionsFollowTheGame() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5)
        XCTAssertEqual(e.firstSteps().filter { $0.done }.count, 0)
        XCTAssertTrue(e.suggestions().contains { $0.action == .newCompany })
        e.update { s, _, _ in Ledger.move(&s, .me, 30_000_000, why: "Test funds") }
        guard case .success = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 10_000_000) else { return XCTFail() }
        XCTAssertTrue(e.firstSteps().first { $0.id == "start" }!.done)
        for _ in 0..<10 { e.nextDay() }
        let h = e.dayHistory
        XCTAssertEqual(h.netWorth.count, 11, "one history entry for the start and one per day")
        XCTAssertEqual(h.netWorth.last ?? 0, e.netWorth.total.rounded(), accuracy: 1)
    }
}

final class TextTokenTests: XCTestCase {
    func testAuthorityAndAmountTokensAreResolvedPerCountry() throws {
        let uk = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 1)
        let no = try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 1)
        let text = "{auth:food} says: fine of {m:10000}. Unknown {auth:nope}."
        let a = uk.localized(text), b = no.localized(text)
        XCTAssertNotEqual(a, b)
        XCTAssertFalse(a.contains("{auth:food}") || a.contains("{m:"))
        XCTAssertTrue(a.contains("GBP"), a)
        XCTAssertTrue(b.contains("NOK"), b)
        XCTAssertTrue(a.contains("Unknown nope."), "an unknown body falls back to its key")
        XCTAssertEqual(uk.localized("nothing to resolve"), "nothing to resolve")
    }
}

final class ShowcaseTests: XCTestCase {
    func testShowcaseGameIsPopulatedAndConsistent() throws {
        let e = try GameEngine.showcase(days: 60)
        XCTAssertEqual(e.state.liveCompanies.count, 2)
        XCTAssertGreaterThan(e.dayHistory.netWorth.count, 50)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        XCTAssertFalse(e.state.isGameOver)
    }
}

final class StaffTalksTests: XCTestCase {
    func testPeopleAskForRaisesAndAnswersChangeWagesAndMood() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 21)
        e.update { s, _, _ in Ledger.move(&s, .me, 40_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 8_000_000) else { return XCTFail() }
        var asked: Message?
        for _ in 0..<(70 * 7) {
            e.nextDay()
            for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
            if let m = e.openDecisions.first(where: { $0.actionID == "staffx" }) {
                if m.value("data")["t"].string == "payask" { asked = m; break }
                e.answer(messageID: m.id, option: 0)     // a fixed-salary request: accept it
                let sid = m.value("data")["sid"].int
                XCTAssertEqual(e.state.company(id)?.staff.first { $0.id == sid }?.payBasis, "fix")
            }
        }
        let m = try XCTUnwrap(asked, "after a year and a half somebody should have asked about pay")
        let sid = m.value("data")["sid"].int
        let before = try XCTUnwrap(e.state.company(id)?.staff.first { $0.id == sid }).monthlyWage
        XCTAssertTrue(e.answer(messageID: m.id, option: 0))
        let after = try XCTUnwrap(e.state.company(id)?.staff.first { $0.id == sid })
        XCTAssertGreaterThan(after.monthlyWage, before)
        XCTAssertGreaterThan(after.happyUntilWeek, e.state.week, "a real raise makes them content for a while")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }
}
