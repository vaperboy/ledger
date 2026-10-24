import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// A campaign can be given a length; it ends on its date, and the plan never states a reach or a customer count.
final class CampaignDurationTests: XCTestCase {
    private func channel(_ e: GameEngine, minimum: Bool) throws -> String {
        try XCTUnwrap(e.marketing.channels.filter { $0.value.onlyInCountry == nil && !$0.value.isPrimeTime && (minimum ? $0.value.minimumWeeks > 0 : $0.value.minimumWeeks == 0) }.keys.sorted().first)
    }

    func testDefaultCallIsUnchangedAndHasNoEndDate() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        let ch = try channel(e, minimum: false)
        XCTAssertEqual(e.setCampaign(companyID: id, channel: ch, weeklyBudget: 40_000), .done)
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertFalse(co.value("mkt")[ch].isNull)
        XCTAssertTrue(co.value("mktEnd")[ch].isNull, "no length given = runs until stopped")
    }

    func testALengthSetsTheEndDateAndTheCampaignStopsThere() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        let ch = try channel(e, minimum: false)
        let start = e.state.week
        XCTAssertEqual(e.setCampaign(companyID: id, channel: ch, weeklyBudget: 40_000, weeks: 4), .done)
        XCTAssertEqual(e.state.company(id)?.value("mktEnd")[ch].int, start + 4)
        ChainsTests.play(&e, days: 7 * 3)
        XCTAssertFalse(try XCTUnwrap(e.state.company(id)).value("mkt")[ch].isNull, "still running before its end week")
        ChainsTests.play(&e, days: 7 * 2)
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertTrue(co.value("mkt")[ch].isNull, "campaign has stopped")
        XCTAssertTrue(co.value("mktEnd")[ch].isNull, "and its date is gone")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testTooShortALengthIsRefusedWithNoChange() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        let ch = try channel(e, minimum: true)
        let mw = try XCTUnwrap(e.marketing.channels[ch]).minimumWeeks
        let before = e.state.company(id)?.value("mkt")
        if case .refused = e.setCampaign(companyID: id, channel: ch, weeklyBudget: 40_000, weeks: mw - 1) {} else { XCTFail("shorter than the channel minimum") }
        XCTAssertEqual(e.state.company(id)?.value("mkt"), before)
        XCTAssertEqual(e.setCampaign(companyID: id, channel: ch, weeklyBudget: 40_000, weeks: mw), .done)
        XCTAssertTrue(Marketing.lengthChoices(try XCTUnwrap(e.marketing.channels[ch])).allSatisfy { $0 >= mw })
    }

    func testTheLockStillBlocksCuttingEarlyAndCancelRemovesTheDate() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        let locked = try channel(e, minimum: true)
        XCTAssertEqual(e.setCampaign(companyID: id, channel: locked, weeklyBudget: 40_000, weeks: 12), .done)
        if case .refused = e.setCampaign(companyID: id, channel: locked, weeklyBudget: 0) {} else { XCTFail("cut inside the minimum") }
        XCTAssertFalse(try XCTUnwrap(e.state.company(id)).value("mktEnd")[locked].isNull)
        let free = try channel(e, minimum: false)
        XCTAssertEqual(e.setCampaign(companyID: id, channel: free, weeklyBudget: 40_000, weeks: 12), .done)
        XCTAssertEqual(e.setCampaign(companyID: id, channel: free, weeklyBudget: 0), .done)
        XCTAssertTrue(try XCTUnwrap(e.state.company(id)).value("mktEnd")[free].isNull)
        // switching a running campaign to "until stopped" clears the date; changing the budget alone keeps it
        XCTAssertEqual(e.setCampaign(companyID: id, channel: free, weeklyBudget: 40_000, weeks: 8), .done)
        XCTAssertEqual(e.setCampaign(companyID: id, channel: free, weeklyBudget: 50_000), .done)
        XCTAssertFalse(try XCTUnwrap(e.state.company(id)).value("mktEnd")[free].isNull)
        XCTAssertEqual(e.setCampaign(companyID: id, channel: free, weeklyBudget: 50_000, weeks: 0), .done)
        XCTAssertTrue(try XCTUnwrap(e.state.company(id)).value("mktEnd")[free].isNull)
    }

    func testAStaleDateNeverEndsALaterCampaign() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        let ch = try channel(e, minimum: false)
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            var end = s.companies[i].value("mktEnd"); end[ch] = .number(Double(s.week + 1)); s.companies[i].set("mktEnd", end)
        }
        XCTAssertEqual(e.setCampaign(companyID: id, channel: ch, weeklyBudget: 40_000), .done)
        XCTAssertTrue(try XCTUnwrap(e.state.company(id)).value("mktEnd")[ch].isNull, "a new open-ended campaign drops any old date")
    }

    func testPlanShowsCostAndLockButNoCustomerNumber() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        let ch = try channel(e, minimum: true)
        let mw = try XCTUnwrap(e.marketing.channels[ch]).minimumWeeks
        let p = try XCTUnwrap(e.campaignPlan(companyID: id, channel: ch, weeklyBudget: 10_000, weeks: 12))
        XCTAssertEqual(p.totalCost, 120_000)
        XCTAssertEqual(p.lockedWeeks, mw)
        XCTAssertNil(try XCTUnwrap(e.campaignPlan(companyID: id, channel: ch, weeklyBudget: 10_000, weeks: nil)).totalCost, "no end date, no total")
        XCTAssertFalse(p.runByChain)
    }

    func testAStoreCannotCutMarketingTheChainRuns() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        ChainsTests.season(&e, id)
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .open } }
        var chainID = 0
        e.update { s, _, _ in chainID = Chains.make(&s, companyID: id, name: "Beans") ?? 0 }
        XCTAssertNotEqual(chainID, 0)
        e.setChainRule(chainID: chainID, rule: .marketing("normal"))
        ChainsTests.play(&e, days: 14)
        let co = try XCTUnwrap(e.state.company(id))
        let run = try XCTUnwrap(co.value("mk12").array.first?.string)
        if case .refused = e.setCampaign(companyID: id, channel: run, weeklyBudget: 0) {} else { XCTFail("chain-run channel") }
        let taken = Set(co.value("mk12").array.map { $0.string })
        let own = try XCTUnwrap(e.marketing.channels.filter { !taken.contains($0.key) && $0.value.onlyInCountry == nil && $0.value.minimumWeeks == 0 }.keys.sorted().first)
        XCTAssertEqual(e.setCampaign(companyID: id, channel: own, weeklyBudget: 20_000, weeks: 4), .done)
    }
}
