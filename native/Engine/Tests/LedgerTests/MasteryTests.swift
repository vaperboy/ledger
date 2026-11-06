import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

/// Skill pays: advertising stacks on the organic name with diminishing returns, the planner's payback figure is the one the game plays,
/// and opening a second outlet tells the player what cash and time it takes.
final class MasteryTests: XCTestCase {
    private func game(trade: String = "cafe", seed: Int = 7) throws -> (GameEngine, Int) {
        let e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed, story: .fresh, tradeID: trade, companyName: "T")
        return (e, e.state.companies[0].id)
    }

    func testCampaignRaisesAwarenessAboveTheOrganicName() throws {
        var (a, ida) = try game()
        var (b, idb) = try game()
        let ch = try XCTUnwrap(a.marketing.channels["google"])
        let budget = ch.budgets(in: a.homeCurrency)[1]
        _ = b.setCampaign(companyID: idb, channel: "google", weeklyBudget: budget)
        for _ in 0..<(30 * 7) { a.nextDay(); b.nextDay() }
        let plain = try XCTUnwrap(a.state.company(ida)).awareness, ads = try XCTUnwrap(b.state.company(idb)).awareness
        XCTAssertGreaterThan(ads, plain + 3, "a modest campaign must add to the name the shop already has, not vanish under it")
        XCTAssertLessThanOrEqual(ads, 100)
    }

    func testBiggerBudgetsHaveDiminishingReturns() throws {
        let (e, id) = try game()
        let co = try XCTUnwrap(e.state.company(id))
        let ch = try XCTUnwrap(e.marketing.channels["google"])
        let b = ch.budgets(in: e.homeCurrency)
        var lifts: [Double] = []
        for x in b where x > 0 {
            let est = try XCTUnwrap(Marketing.estimate(co, channel: "google", weeklyBudget: x, state: e.state, data: e.data, tables: e.marketing))
            XCTAssertGreaterThanOrEqual(est.awarenessWith, est.awarenessWithout)
            lifts.append(est.awarenessWith - est.awarenessWithout)
        }
        XCTAssertEqual(lifts, lifts.sorted(), "more money never buys less name")
        if lifts.count >= 3 {
            let first = lifts[1] - lifts[0], last = lifts[lifts.count - 1] - lifts[lifts.count - 2]
            let spendFirst = b[2] - b[1], spendLast = b[b.count - 1] - b[b.count - 2]
            XCTAssertLessThan(last / spendLast, first / spendFirst, "each extra pound buys less than the one before")
        }
        let none = try XCTUnwrap(Marketing.estimate(co, channel: "google", weeklyBudget: 0, state: e.state, data: e.data, tables: e.marketing))
        XCTAssertEqual(none.paybackWeeks, 0)
        XCTAssertEqual(none.netPerWeek, 0, accuracy: 1e-9)
    }

    func testSensibleSpendPaysBackAndAbsurdSpendDoesNot() throws {
        var (e, id) = try game()
        for _ in 0..<(8 * 7) { e.nextDay() }
        let co = try XCTUnwrap(e.state.company(id))
        let b = try XCTUnwrap(e.marketing.channels["google"]).budgets(in: e.homeCurrency)
        var best = -Double.infinity
        for x in b where x > 0 {
            if let est = Marketing.estimate(co, channel: "google", weeklyBudget: x, state: e.state, data: e.data, tables: e.marketing) { best = max(best, est.netPerWeek) }
        }
        let huge = try XCTUnwrap(Marketing.estimate(co, channel: "google", weeklyBudget: b[b.count - 1] * 20, state: e.state, data: e.data, tables: e.marketing))
        XCTAssertNil(huge.paybackWeeks, "twenty times the top budget cannot pay for itself")
        XCTAssertLessThan(huge.netPerWeek, best)
    }

    func testSecondOutletReadinessSaysWhatItNeeds() throws {
        var (e, id) = try game()
        for _ in 0..<(30 * 7) { e.nextDay() }
        let co = try XCTUnwrap(e.state.company(id))
        let here = try XCTUnwrap(Expansion.readiness(e.state, data: e.data, companyID: id, cityID: co.cityID))
        let other = e.homeCountry.cities.first { $0.id != co.cityID }?.id ?? co.cityID
        let away = try XCTUnwrap(Expansion.readiness(e.state, data: e.data, companyID: id, cityID: other))
        XCTAssertGreaterThan(here.rampReserve, 0)
        XCTAssertEqual(here.cashNeeded, here.startCost + here.rampReserve, accuracy: 1e-6)
        XCTAssertGreaterThan(here.cannibalisation, 0, "two outlets in one city share customers")
        XCTAssertEqual(away.cannibalisation, 0, "a second city shares none")
        XCTAssertFalse(here.advice.isEmpty)
    }

    func testBrandMoatOnlyHelpsKnownTrustedBusinesses() throws {
        let (e, id) = try game()
        var co = try XCTUnwrap(e.state.company(id))
        let w = World(state: e.state, data: e.data)
        co.awareness = 10; co.reputation = 40
        let unknown = Competition.rivalFactor(co, w)
        co.awareness = 90; co.reputation = 90
        let known = Competition.rivalFactor(co, w)
        XCTAssertGreaterThanOrEqual(known, unknown)
    }
}
