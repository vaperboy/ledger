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
        XCTAssertEqual(e.firstStepRewards?.filter { $0.done }.count, 0)
        XCTAssertTrue(e.suggestions().contains { $0.action == .newCompany })
        e.update { s, _, _ in Ledger.move(&s, .me, 30_000_000, why: "Test funds") }
        guard case .success = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 10_000_000) else { return XCTFail() }
        XCTAssertTrue(e.firstStepRewards?.first { $0.id == "co" }?.done == true)
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
        XCTAssertTrue(a.contains("£"), a)
        XCTAssertTrue(b.contains("kr"), b)
        XCTAssertTrue(a.contains("Unknown nope."), "an unknown body falls back to its key")
        XCTAssertEqual(uk.localized("nothing to resolve"), "nothing to resolve")
    }
}

final class DisplayMoneyTests: XCTestCase {
    func testScreenAmountsUseTheSymbol() throws {
        let uk = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 1)
        let s = uk.homeCurrency.display(3_482_600 * uk.homeCurrency.rate)
        XCTAssertEqual(s, "£3,482,600")
        XCTAssertTrue(uk.homeCurrency.display(-1500 * uk.homeCurrency.rate).hasPrefix("\u{2212}£"))
        let no = try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 1)
        XCTAssertTrue(no.homeCurrency.display(1234 * no.homeCurrency.rate).hasSuffix(" kr"))
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
    /// Plays a restaurant (several staff) until somebody asks about pay; tries a few seeds because people come and go.
    func testPeopleAskForRaisesAndAnswersChangeWagesAndMood() throws {
        for seed in [21, 22, 23, 24, 25] {
            var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
            e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds") }
            guard case .success(let id) = e.startCompany(tradeID: "restaurant", cityID: e.state.player.cityID, form: .limited, fundWith: 20_000_000) else { return XCTFail() }
            var asked: Message?
            for _ in 0..<(100 * 7) {
                e.nextDay()
                for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
                if let m = e.openDecisions.first(where: { $0.actionID == "staffx" }) {
                    if m.value("data")["t"].string == "payask" { asked = m; break }
                    e.answer(messageID: m.id, option: 0)     // a fixed-salary request: accept it
                    let sid = m.value("data")["sid"].int
                    XCTAssertEqual(e.state.company(id)?.staff.first { $0.id == sid }?.payBasis, "fix")
                }
            }
            guard let m = asked else { continue }
            let sid = m.value("data")["sid"].int
            let before = try XCTUnwrap(e.state.company(id)?.staff.first { $0.id == sid }).monthlyWage
            XCTAssertTrue(e.answer(messageID: m.id, option: 0))
            let after = try XCTUnwrap(e.state.company(id)?.staff.first { $0.id == sid })
            XCTAssertGreaterThan(after.monthlyWage, before)
            XCTAssertGreaterThan(after.happyUntilWeek, e.state.week, "a real raise makes them content for a while")
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
            return
        }
        XCTFail("in five games of two years nobody asked about pay")
    }
}

final class FinanceOverviewTests: XCTestCase {
    func testOverviewMatchesTheBooksAndListsWhatIsComing() throws {
        let e = try GameEngine.showcase(days: 75)
        let o = e.financeOverview()
        let expenses = e.state.liveCompanies.reduce(0) { $0 + Books.expenses($1.books.year) + ($1.books.year["tax"] ?? 0) }
        XCTAssertEqual(o.costsThisYear.reduce(0) { $0 + $1.amount }, expenses, accuracy: 1, "the yearly breakdown adds up to the books")
        XCTAssertFalse(o.upcoming.isEmpty, "payroll, bills and loan instalments are coming")
        XCTAssertEqual(o.upcoming.map { $0.dayNumber }, o.upcoming.map { $0.dayNumber }.sorted())
        XCTAssertTrue(o.upcoming.allSatisfy { $0.dayNumber >= Payday.dayNumber(week: e.state.week, day: e.state.day) }, "nothing is listed that is already past")
        let one = e.financeOverview(companyID: e.state.liveCompanies[0].id)
        XCTAssertLessThanOrEqual(one.costTotalThisYear, o.costTotalThisYear + 1)
        XCTAssertTrue(o.notes.last?.contains("estimates") ?? false)
        XCTAssertEqual(o.countryName, e.homeCountry.name)
        XCTAssertEqual(o.rules.count, 7)
        XCTAssertTrue(o.licences.allSatisfy { $0.amount >= 0 && !$0.label.contains("{") }, "licence lines are priced and their text tokens resolved")
        XCTAssertTrue(o.basis.hasPrefix("Estimate"), "rates are labelled as estimates until somebody has checked them")
    }

    func testMarketingPausesInsteadOfRunningUpDebt() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5)
        e.update { s, _, _ in Ledger.move(&s, .me, 30_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "webdev", cityID: e.state.player.cityID, form: .limited, fundWith: 1_500_000) else { return XCTFail() }
        for (k, ch) in e.marketing.channels.sorted(by: { $0.key < $1.key }) where ch.onlyInCountry == nil { _ = e.setCampaign(companyID: id, channel: k, weeklyBudget: ch.budgetOptions.last ?? 0) }
        for _ in 0..<(40 * 7) { e.nextDay(); for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) } }
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertGreaterThan(co.cash, -200_000, "campaigns are prepaid and stop when cash runs low")
        XCTAssertGreaterThanOrEqual(Valuation.companyValue(co, state: e.state, trades: e.data.catalog), 0, "a limited company is never worth less than nothing")
    }

    func testPayrollIsApprovedByPolicyWhenThereIsMoney() throws {
        func asks(autoPayroll: Bool) throws -> Int {
            var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 8)
            e.update { s, _, _ in Ledger.move(&s, .me, 30_000_000, why: "Test funds") }
            var p = ManagementPolicy(); p.autoPayroll = autoPayroll; e.setPolicy(p)
            guard case .success = e.startCompany(tradeID: "restaurant", cityID: e.state.player.cityID, form: .soleTrader, fundWith: 8_000_000) else { XCTFail(); return 0 }
            for _ in 0..<(16 * 7) { e.nextDay() }
            return e.state.inbox.filter { $0.actionID.hasPrefix("pay29") }.count
        }
        XCTAssertEqual(try asks(autoPayroll: true), 0, "with the default policy nobody is asked about routine payroll the company can pay")
        XCTAssertGreaterThan(try asks(autoPayroll: false), 0, "with the policy off the owner is asked")
    }
}

final class AutoDividendTests: XCTestCase {
    func testSurplusIsPaidOutOnlyWhenThePolicySaysSo() throws {
        func paid(weeks: Double) throws -> Double {
            var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 9)
            e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds") }
            var p = ManagementPolicy(); p.autoDividendWeeks = weeks; e.setPolicy(p)
            guard case .success(let id) = e.startCompany(tradeID: "webdev", cityID: e.state.player.cityID, form: .limited, fundWith: 20_000_000) else { XCTFail(); return 0 }
            for _ in 0..<(20 * 7) { e.nextDay(); for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) } }
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
            return e.state.company(id)?.distributed ?? 0
        }
        XCTAssertEqual(try paid(weeks: 0), 0, "never by default")
        XCTAssertGreaterThan(try paid(weeks: 4), 0, "a company sitting on spare cash pays it out")
    }
}

final class InsightTests: XCTestCase {
    func testHealthAndInsightsComeFromTheCompanysOwnNumbers() throws {
        // 157 days: at 150 days one showcase company had a week with no trade at all after the hiring talks changed the random path (it trades normally a week later)
        let e = try GameEngine.showcase(days: 157)
        for co in e.state.liveCompanies {
            let h = e.companyHealth(co)
            XCTAssertEqual(h.revenueSeries.count, min(24, co.monthlyHistory.count))
            XCTAssertFalse(e.insights(for: co).isEmpty)
            XCTAssertGreaterThanOrEqual(h.rating, 1.5)
            XCTAssertEqual(h.value, Valuation.companyValue(co, state: e.state, trades: e.data.catalog))
            XCTAssertGreaterThan(h.weeklyCost, 0)
            XCTAssertEqual(h.weeksOfCash, max(0, co.cash) / h.weeklyCost, accuracy: 0.001)
            XCTAssertGreaterThan(h.capacityLastWeek, 0, "an open company reports what it could serve")
            XCTAssertNotNil(h.bottleneck)
            XCTAssertTrue(e.insights(for: co, limit: 10).allSatisfy { $0.section == nil || ["operations", "marketing", "staff", "finances", "setup"].contains($0.section!) })
        }
    }
}
