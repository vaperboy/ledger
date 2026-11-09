import XCTest
import GameCore
@testable import Simulation

/// Treasury, printing, inflation with a lag, donations, rates, price support, the audit log, and the presidency.
final class GovernmentTests: XCTestCase {
    private func gov() -> Government { Government(country: "NO", admins: ["admin"], startingSupply: 1_000_000) }
    private func cit(_ a: String, age: Int = 20, link: String? = nil) -> GovCitizen { GovCitizen(account: a, linkKey: link, country: "NO", name: a, ageWeeks: age) }
    private let anyone: (String) -> Bool = { _ in true }

    /// Runs one election to the end and returns the government with `pres` in office from week 14.
    private func withPresident(promises: [CampaignPromise] = [], approve: Bool = true) throws -> Government {
        var g = gov()
        g.advance(week: 0, canStand: anyone)
        try g.stand(cit("pres"), manifesto: "Fair", promises: promises, fee: 1_000, week: 1)
        if approve, let p = g.openPending.first(where: { $0.kind == .promises }) { try g.confirm(admin: "admin", pendingID: p.id, week: 2) }
        g.advance(week: 7, canStand: anyone)
        try g.castBallot(cit("v1"), for: "pres", week: 8)
        g.advance(week: 14, canStand: anyone)
        let r = try XCTUnwrap(g.openPending.first { $0.kind == .electionResult })
        try g.confirm(admin: "admin", pendingID: r.id, week: 14)
        return g
    }

    // MARK: Treasury and printing

    func testTreasuryNeverGoesNegativeAndOnlyNamedPayoutsLeave() throws {
        var t = GovTreasury()
        try t.post(100, kind: "donation", week: 1)
        XCTAssertThrowsError(try t.post(-10, kind: "burn", week: 1), "no kind may remove money")
        XCTAssertThrowsError(try t.post(-500, kind: "price_support", week: 1), "cannot overdraw")
        try t.post(-40, kind: "price_support", week: 2)
        XCTAssertEqual(t.balance, 60)
        XCTAssertEqual(t.gap, 0)
    }

    func testOnlyAnAdminPrintsAndEveryPrintingIsPublic() throws {
        var g = gov()
        XCTAssertThrowsError(try g.printMoney(admin: "mallory", amount: 1_000, reason: "gift", week: 1)) { XCTAssertEqual($0 as? GovError, .notAdmin) }
        XCTAssertThrowsError(try g.printMoney(admin: "admin", amount: 1_000, reason: " ", week: 1), "a reason is required")
        let m = try g.printMoney(admin: "admin", amount: 40_000, reason: "Road works", week: 1)
        XCTAssertEqual(g.treasury.balance, 40_000)
        XCTAssertEqual(g.supply.mints, [m])
        XCTAssertEqual(g.supply.total, 1_040_000)
        XCTAssertTrue(g.audit.contains { $0.action == "print" })
        XCTAssertTrue(g.news.contains { $0.text.contains("Road works") })
        XCTAssertEqual(g.treasury.gap, 0)
    }

    func testPrintingLimits() throws {
        var g = gov()
        XCTAssertThrowsError(try g.printMoney(admin: "admin", amount: 60_000, reason: "too much", week: 1), "over 5% at once")
        for w in 0..<3 { try g.printMoney(admin: "admin", amount: 49_000, reason: "step \(w)", week: w) }
        XCTAssertThrowsError(try g.printMoney(admin: "admin", amount: 49_000, reason: "fourth", week: 3), "over 15% in twelve weeks")
        XCTAssertNoThrow(try g.printMoney(admin: "admin", amount: 49_000, reason: "later", week: 20))
    }

    func testInflationFollowsPrintingWithALag() throws {
        var g = gov()
        try g.printMoney(admin: "admin", amount: 50_000, reason: "stimulus", week: 10)
        for w in 10..<(10 + GovInflation.lagWeeks) { XCTAssertEqual(GovInflation.rate(g.supply, week: w), 0, "week \(w) is before the lag ends") }
        XCTAssertGreaterThan(GovInflation.rate(g.supply, week: 10 + GovInflation.lagWeeks), 0)
        XCTAssertEqual(GovInflation.index(g.supply, atWeek: 15), 1)
        let later = GovInflation.index(g.supply, atWeek: 40)
        XCTAssertGreaterThan(later, 1)
        XCTAssertEqual(GovInflation.index(g.supply, atWeek: 80), later, accuracy: 1e-12, "the effect ends; prices never fall back")
        XCTAssertLessThanOrEqual(GovInflation.rate(g.supply, week: 17), GovInflation.weeklyCap)
    }

    func testNoSequenceOfActionsReducesTheSupplyOrDestroysMoney() throws {
        var g = try withPresident()
        var last = g.supply.total
        var week = 15
        for n in 0..<40 {
            switch n % 5 {
            case 0: _ = try? g.printMoney(admin: "admin", amount: Double(1_000 * (n + 1)), reason: "round \(n)", week: week)
            case 1: _ = try? g.donate(account: "a\(n)", name: "A", amount: Double(10 * n), week: week)
            case 2: _ = try? g.proposePriceSupport(by: "pres", tradeID: "cafe\(n)", percent: 0.05, weeklyBudget: 100, weeks: 4, week: week)
            case 3: if let p = g.openPending.first { try? g.confirm(admin: "admin", pendingID: p.id, week: week) }
            default: _ = g.supportPayout(account: "u", tradeID: "cafe2", weekRevenue: 5_000, week: week)
            }
            XCTAssertGreaterThanOrEqual(g.supply.total, last)
            XCTAssertEqual(g.treasury.gap, 0, "treasury equals everything posted")
            last = g.supply.total
            week += 1
        }
        let outflow = g.treasury.entries.filter { $0.amount < 0 }
        XCTAssertTrue(outflow.allSatisfy { GovTreasury.spendKinds.contains($0.kind) })
    }

    func testDonationsBuyNothingAndAreRecorded() throws {
        var g = gov()
        XCTAssertThrowsError(try g.donate(account: "a", name: "A", amount: 0.5, week: 1))
        let d = try g.donate(account: "a", name: "Anna", amount: 250, week: 1)
        XCTAssertEqual(g.treasury.balance, 250)
        XCTAssertEqual(g.donations, [d])
        XCTAssertNil(g.office, "a donation gives no office")
        XCTAssertEqual(g.supportPayout(account: "a", tradeID: "cafe", weekRevenue: 1_000, week: 1), 0, "nor any support")
    }

    // MARK: Rates and support need a president and an administrator

    func testPolicyChangeNeedsPresidentLimitsAndConfirmation() throws {
        var g = try withPresident()
        XCTAssertThrowsError(try g.proposePolicy(by: "nobody", transferTax: 0.03, gainsTax: 0.20, week: 15)) { XCTAssertEqual($0 as? GovError, .notPresident) }
        XCTAssertThrowsError(try g.proposePolicy(by: "pres", transferTax: 0.04, gainsTax: 0.20, week: 15), "more than one point")
        XCTAssertThrowsError(try g.proposePolicy(by: "pres", transferTax: 0.06, gainsTax: 0.20, week: 15))
        let id = try g.proposePolicy(by: "pres", transferTax: 0.03, gainsTax: 0.21, week: 15)
        XCTAssertEqual(g.policy.transferTax, 0.02, "nothing changes before confirmation")
        XCTAssertThrowsError(try g.proposePolicy(by: "pres", transferTax: 0.03, gainsTax: 0.21, week: 15)) { XCTAssertEqual($0 as? GovError, .alreadyPending) }
        XCTAssertThrowsError(try g.confirm(admin: "pres", pendingID: id, week: 15)) { XCTAssertEqual($0 as? GovError, .notAdmin) }
        try g.confirm(admin: "admin", pendingID: id, week: 15)
        XCTAssertEqual(g.policy.transferTax, 0.03)
        XCTAssertEqual(g.policy.gainsTax, 0.21)
        XCTAssertThrowsError(try g.proposePolicy(by: "pres", transferTax: 0.04, gainsTax: 0.21, week: 18)) { XCTAssertEqual($0 as? GovError, .tooSoon(weeksLeft: 4)) }
        XCTAssertNoThrow(try g.proposePolicy(by: "pres", transferTax: 0.04, gainsTax: 0.21, week: 22))
    }

    func testRejectedChangeChangesNothing() throws {
        var g = try withPresident()
        let id = try g.proposePolicy(by: "pres", transferTax: 0.03, gainsTax: 0.20, week: 15)
        try g.reject(admin: "admin", pendingID: id, week: 15)
        XCTAssertEqual(g.policy.transferTax, 0.02)
        XCTAssertTrue(g.openPending.isEmpty)
        XCTAssertTrue(g.audit.contains { $0.action == "reject" })
    }

    func testPriceSupportLimitsAndPayout() throws {
        var g = try withPresident()
        try g.donate(account: "d", name: "D", amount: 100_000, week: 14)
        XCTAssertThrowsError(try g.proposePriceSupport(by: "pres", tradeID: "cafe", percent: 0.2, weeklyBudget: 1_000, weeks: 4, week: 15), "share too high")
        XCTAssertThrowsError(try g.proposePriceSupport(by: "pres", tradeID: "cafe", percent: 0.05, weeklyBudget: 9_000, weeks: 4, week: 15), "budget over 5% of treasury")
        let pid = try g.proposePriceSupport(by: "pres", tradeID: "cafe", percent: 0.05, weeklyBudget: 4_000, weeks: 4, week: 15)
        XCTAssertEqual(g.supportPayout(account: "u", tradeID: "cafe", weekRevenue: 10_000, week: 15), 0, "not active before confirmation")
        try g.confirm(admin: "admin", pendingID: pid, week: 15)
        let before = g.treasury.balance
        XCTAssertEqual(g.supportPayout(account: "u", tradeID: "cafe", weekRevenue: 10_000, week: 15), 500)
        XCTAssertEqual(g.treasury.balance, before - 500)
        // One account may draw only a quarter of the weekly budget, however many companies it has.
        XCTAssertEqual(g.supportPayout(account: "u", tradeID: "cafe", weekRevenue: 1_000_000, week: 15), 500)
        XCTAssertEqual(g.supportPayout(account: "u", tradeID: "cafe", weekRevenue: 1_000_000, week: 15), 0)
        XCTAssertEqual(g.supportPayout(account: "pres", tradeID: "cafe", weekRevenue: 10_000, week: 16), 0, "the president gets none")
        XCTAssertEqual(g.supportPayout(account: "admin", tradeID: "cafe", weekRevenue: 10_000, week: 16), 0, "nor an administrator")
        XCTAssertEqual(g.supportPayout(account: "u", tradeID: "bakery", weekRevenue: 10_000, week: 16), 0, "other trades none")
        XCTAssertEqual(g.supportPayout(account: "u", tradeID: "cafe", weekRevenue: 10_000, week: 19 + 1), 0, "ended after its weeks")
        XCTAssertEqual(g.treasury.gap, 0)
    }

    // MARK: The presidency

    func testCycleFromNominationToTermAndRollOver() throws {
        var g = gov()
        g.advance(week: 0, canStand: anyone)
        let e = try XCTUnwrap(g.election)
        XCTAssertEqual(e.nominateUntil, 7)
        XCTAssertEqual(e.votingUntil, 14)
        XCTAssertThrowsError(try g.castBallot(cit("v"), for: "x", week: 1), "voting not open yet")
        XCTAssertNil(g.tally())
        try g.stand(cit("pres"), manifesto: String(repeating: "x", count: 400), promises: [], fee: 5_000, week: 1)
        XCTAssertEqual(g.election?.candidates.first?.manifesto.count, Politics.manifestoLimit)
        XCTAssertEqual(g.treasury.balance, 5_000, "the fee goes to the treasury")
        g.advance(week: 7, canStand: anyone)
        XCTAssertEqual(g.election?.status, .voting)
        try g.castBallot(cit("v1"), for: "pres", week: 8)
        XCTAssertNil(g.tally(), "no count while voting")
        g.advance(week: 14, canStand: anyone)
        XCTAssertEqual(g.election?.status, .counted)
        XCTAssertNil(g.office, "the winner waits for an administrator")
        XCTAssertEqual(g.tally()?.first?.votes, 1)
        let r = try XCTUnwrap(g.openPending.first)
        try g.confirm(admin: "admin", pendingID: r.id, week: 14)
        XCTAssertEqual(g.office?.holder, "pres")
        XCTAssertEqual(g.office?.termEnd, 14 + Government.termWeeks)
        XCTAssertTrue(g.isPresident("pres", week: 25))
        XCTAssertFalse(g.isPresident("pres", week: 26))
        g.advance(week: 26, canStand: anyone)
        XCTAssertNil(g.office, "the term rolls over")
        XCTAssertEqual(g.election?.status, .nomination, "a new cycle opens at once")
        XCTAssertNotEqual(g.election?.id, e.id)
        XCTAssertEqual(g.election?.nominateUntil, 26 + Politics.nominationWeeks)
        XCTAssertTrue(g.news.contains { $0.text.contains("term has ended") })
    }

    func testOneAccountOneVoteEvenWithLinkedAccounts() throws {
        var g = gov()
        g.advance(week: 0, canStand: anyone)
        try g.stand(cit("a"), manifesto: "", promises: [], fee: 1, week: 1)
        try g.stand(cit("b"), manifesto: "", promises: [], fee: 1, week: 1)
        g.advance(week: 7, canStand: anyone)
        try g.castBallot(cit("v1", link: "owner1"), for: "a", week: 8)
        XCTAssertThrowsError(try g.castBallot(cit("v1", link: "owner1"), for: "b", week: 8)) { XCTAssertEqual($0 as? GovError, .alreadyVoted) }
        XCTAssertThrowsError(try g.castBallot(cit("v1-alt", link: "owner1"), for: "b", week: 8), "a linked account shares the vote")
        XCTAssertThrowsError(try g.castBallot(cit("young", age: 2), for: "a", week: 8), "too new")
        XCTAssertThrowsError(try g.castBallot(GovCitizen(account: "bot", country: "NO", ageWeeks: 30, simulated: true), for: "a", week: 8))
        XCTAssertThrowsError(try g.castBallot(GovCitizen(account: "far", country: "SE", ageWeeks: 30), for: "a", week: 8), "other country")
        XCTAssertThrowsError(try g.castBallot(GovCitizen(account: "barred", country: "NO", ageWeeks: 30, barredFromVoting: true), for: "a", week: 8))
        XCTAssertEqual(g.election?.ballots["a"], 1)
        XCTAssertEqual(g.election?.ballots.values.reduce(0, +), 1)
    }

    func testStandingRulesAndFeeIsNotReturned() throws {
        var g = gov()
        XCTAssertThrowsError(try g.stand(cit("a"), manifesto: "", promises: [], fee: 1, week: 0), "no election yet")
        g.advance(week: 0, canStand: anyone)
        XCTAssertThrowsError(try g.stand(cit("a", age: 7), manifesto: "", promises: [], fee: 1, week: 1), "must be eight weeks old")
        XCTAssertThrowsError(try g.stand(GovCitizen(account: "x", country: "NO", ageWeeks: 30, barredFromOffice: true), manifesto: "", promises: [], fee: 1, week: 1))
        try g.stand(cit("a"), manifesto: "", promises: [], fee: 9_000, week: 1)
        XCTAssertThrowsError(try g.stand(cit("a"), manifesto: "", promises: [], fee: 9_000, week: 2)) { XCTAssertEqual($0 as? GovError, .alreadyStanding) }
        try g.withdraw(account: "a", week: 3)
        XCTAssertEqual(g.treasury.balance, 9_000, "withdrawing returns nothing")
        XCTAssertTrue(g.election?.candidates.isEmpty ?? false)
        g.advance(week: 7, canStand: anyone)
        XCTAssertEqual(g.election?.status, .closed, "no candidates, no vote")
        XCTAssertNil(g.office)
    }

    func testTieGoesToTheEarlierNominationAndNoBallotsLeavesItVacant() throws {
        var g = gov()
        g.advance(week: 0, canStand: anyone)
        try g.stand(cit("late"), manifesto: "", promises: [], fee: 1, week: 3)
        try g.stand(cit("early"), manifesto: "", promises: [], fee: 1, week: 2)
        g.advance(week: 7, canStand: anyone)
        try g.castBallot(cit("v1"), for: "late", week: 8)
        try g.castBallot(cit("v2"), for: "early", week: 8)
        g.advance(week: 14, canStand: anyone)
        XCTAssertEqual(g.election?.winner, "early")

        var h = gov()
        h.advance(week: 0, canStand: anyone)
        try h.stand(cit("a"), manifesto: "", promises: [], fee: 1, week: 1)
        h.advance(week: 7, canStand: anyone)
        h.advance(week: 14, canStand: anyone)
        XCTAssertNil(h.election?.winner)
        XCTAssertNil(h.office)
        h.advance(week: 15, canStand: anyone)
        XCTAssertEqual(h.election?.status, .closed, "two weeks of cool-down")
        h.advance(week: 16, canStand: anyone)
        XCTAssertEqual(h.election?.status, .nomination)
    }

    func testABarredWinnerCannotWin() throws {
        var g = gov()
        g.advance(week: 0, canStand: anyone)
        try g.stand(cit("a"), manifesto: "", promises: [], fee: 1, week: 1)
        try g.stand(cit("b"), manifesto: "", promises: [], fee: 1, week: 1)
        g.advance(week: 7, canStand: anyone)
        try g.castBallot(cit("v1"), for: "a", week: 8)
        try g.castBallot(cit("v2"), for: "a", week: 8)
        try g.castBallot(cit("v3"), for: "b", week: 8)
        g.advance(week: 14, canStand: { $0 != "a" })
        XCTAssertEqual(g.election?.winner, "b")
    }

    func testAdministratorMayRefuseAnElectionResult() throws {
        var g = gov()
        g.advance(week: 0, canStand: anyone)
        try g.stand(cit("a"), manifesto: "", promises: [], fee: 1, week: 1)
        g.advance(week: 7, canStand: anyone)
        try g.castBallot(cit("v1"), for: "a", week: 8)
        g.advance(week: 14, canStand: anyone)
        let r = try XCTUnwrap(g.openPending.first)
        try g.reject(admin: "admin", pendingID: r.id, week: 14)
        XCTAssertNil(g.office)
        XCTAssertEqual(g.election?.status, .closed)
    }

    // MARK: Promises and the realism check

    func testRealismCheck() {
        let p = GovPolicy()
        XCTAssertNil(Politics.realismProblem(CampaignPromise(kind: .transferTax, value: 0.03), policy: p, treasury: 1))
        XCTAssertNil(Politics.realismProblem(CampaignPromise(kind: .transferTax, value: 0.04), policy: p, treasury: 1), "two steps fit in a term")
        XCTAssertNil(Politics.realismProblem(CampaignPromise(kind: .transferTax, value: 0.0), policy: p, treasury: 1), "two points down is within reach")
        XCTAssertNotNil(Politics.realismProblem(CampaignPromise(kind: .transferTax, value: 0.05), policy: p, treasury: 1), "three points is out of reach")
        XCTAssertNotNil(Politics.realismProblem(CampaignPromise(kind: .transferTax, value: 0.02), policy: p, treasury: 1), "already the rate")
        XCTAssertNotNil(Politics.realismProblem(CampaignPromise(kind: .gainsTax, value: 0.01), policy: p, treasury: 1))
        XCTAssertNotNil(Politics.realismProblem(CampaignPromise(kind: .gainsTax, value: 0.50), policy: p, treasury: 1))
        XCTAssertNil(Politics.realismProblem(CampaignPromise(kind: .gainsTax, value: 0.18), policy: p, treasury: 1))
        XCTAssertNotNil(Politics.realismProblem(CampaignPromise(kind: .priceSupport, value: 0.05, tradeID: "cafe"), policy: p, treasury: 0), "empty treasury")
        XCTAssertNotNil(Politics.realismProblem(CampaignPromise(kind: .priceSupport, value: 0.30, tradeID: "cafe"), policy: p, treasury: 5))
        XCTAssertNotNil(Politics.realismProblem(CampaignPromise(kind: .priceSupport, value: 0.05), policy: p, treasury: 5), "needs a trade")
    }

    func testUnrealisticPromisesAreRefusedAtStanding() throws {
        var g = gov()
        g.advance(week: 0, canStand: anyone)
        XCTAssertThrowsError(try g.stand(cit("a"), manifesto: "", promises: [CampaignPromise(kind: .gainsTax, value: 0.05)], fee: 1, week: 1)) {
            guard let e = $0 as? GovError, case .unrealistic = e else { return XCTFail("\($0)") }
        }
        XCTAssertThrowsError(try g.stand(cit("a"), manifesto: "", promises: [CampaignPromise(kind: .transferTax, value: 0.03), CampaignPromise(kind: .transferTax, value: 0.01)], fee: 1, week: 1))
        XCTAssertTrue(g.election?.candidates.isEmpty ?? false)
        XCTAssertEqual(g.treasury.balance, 0, "nothing was taken")
    }

    func testPromisesBindOnlyAfterConfirmationAndAreScoredAtTheEnd() throws {
        var g = try withPresident(promises: [CampaignPromise(kind: .transferTax, value: 0.03), CampaignPromise(kind: .gainsTax, value: 0.18)])
        XCTAssertEqual(g.office?.promises.count, 2)
        let id = try g.proposePolicy(by: "pres", transferTax: 0.03, gainsTax: 0.19, week: 15)
        try g.confirm(admin: "admin", pendingID: id, week: 15)
        XCTAssertEqual(g.office?.promises.filter { $0.kept }.map { $0.kind }, [.transferTax])
        g.advance(week: 26, canStand: anyone)
        XCTAssertTrue(g.news.contains { $0.text.contains("1 of 2 promises kept") })

        let h = try withPresident(promises: [CampaignPromise(kind: .transferTax, value: 0.03)], approve: false)
        XCTAssertEqual(h.office?.promises, [], "unconfirmed promises are not published or tracked")
    }

    func testConvictionRemovesAPresidentAndLapsesTheirProposals() throws {
        var g = try withPresident()
        let id = try g.proposePolicy(by: "pres", transferTax: 0.03, gainsTax: 0.20, week: 15)
        g.removeFromOffice(account: "pres", reason: "convicted", week: 16)
        XCTAssertNil(g.office)
        XCTAssertEqual(g.pending.first { $0.id == id }?.status, .rejected)
        XCTAssertThrowsError(try g.proposePolicy(by: "pres", transferTax: 0.03, gainsTax: 0.20, week: 17))
    }

    func testStateRoundTripsThroughJSON() throws {
        var g = try withPresident(promises: [CampaignPromise(kind: .transferTax, value: 0.03)])
        try g.printMoney(admin: "admin", amount: 1_000, reason: "test", week: 15)
        try g.donate(account: "a", name: "A", amount: 10, week: 15)
        let data = try JSONEncoder().encode(g)
        let back = try JSONDecoder().decode(Government.self, from: data)
        XCTAssertEqual(back, g)
    }
}
