import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Events
@testable import Simulation

/// A holding buys shares of other companies in whole or in part: price, cap table, tiers, dividends, board, merge and net worth.
final class HoldingStakesTests: XCTestCase {
    /// A holding with plenty of cash and a company whose shares are 70% yours and 30% an outside investor's.
    private func setup() throws -> (GameEngine, hid: Int, cid: Int) {
        var e = try ChainsTests.engine("UK")
        guard case .success(let hid) = e.createHolding(name: "H", companies: []) else { throw XCTSkip("holding was not created") }
        let cid = ChainsTests.start(&e, "cafe")
        e.update { s, _, _ in
            _ = Payments.injectCash(&s, companyID: hid, amount: 2_000_000_000)
            _ = Payments.injectCash(&s, companyID: cid, amount: 100_000_000)
            let i = s.companyIndex(cid)!
            CapTable.issue(&s, i, newShares: CapTable.sharesForPercent(30, total: CapTable.table(s.companies[i]).total), to: "Angel", paid: 1)
        }
        return (e, hid, cid)
    }
    private func cash(_ e: GameEngine, _ id: Int) -> Double { e.state.company(id)?.cash ?? 0 }
    private func pct(_ e: GameEngine, _ hid: Int, _ cid: Int) -> Double { HoldingStakes.sharePercent(of: e.state.company(cid)!, holdingID: hid) }
    private func value(_ e: GameEngine, _ cid: Int) -> Double { Valuation.companyValue(e.state.company(cid)!, state: e.state, trades: e.data.catalog) }
    private func tolerance(_ v: Double) -> Double { max(10, v * 1e-4) }

    func testTierThresholds() {
        XCTAssertEqual(HoldingStakes.tier(forPercent: 0), .none)
        XCTAssertEqual(HoldingStakes.tier(forPercent: 19.99), .passive)
        XCTAssertEqual(HoldingStakes.tier(forPercent: 20), .influence)
        XCTAssertEqual(HoldingStakes.tier(forPercent: 50), .influence)
        XCTAssertEqual(HoldingStakes.tier(forPercent: 50.01), .control)
        XCTAssertEqual(HoldingStakes.tier(forPercent: 89.99), .control)
        XCTAssertEqual(HoldingStakes.tier(forPercent: 90), .squeezeOut)
        XCTAssertEqual(HoldingStakes.tier(forPercent: 100), .whole)
        XCTAssertFalse(HoldingStakes.Tier.passive.canSitOnBoard)
        XCTAssertTrue(HoldingStakes.Tier.influence.canSitOnBoard)
        XCTAssertFalse(HoldingStakes.Tier.influence.isConsolidated)
        XCTAssertTrue(HoldingStakes.Tier.control.isConsolidated)
        XCTAssertEqual(HoldingStakes.buyFactor(afterPercent: 10), HoldingStakes.minorityDiscount)
        XCTAssertEqual(HoldingStakes.buyFactor(afterPercent: 30), 1)
        XCTAssertEqual(HoldingStakes.buyFactor(afterPercent: 60), HoldingStakes.controlPremium)
    }

    func testPartialPurchaseFromOwnerUpdatesCapTableAndCash() throws {
        var (e, hid, cid) = try setup()
        let v = value(e, cid)
        XCTAssertGreaterThan(v, 0)
        XCTAssertTrue(e.holdingStakeOffers(holdingID: hid).contains { $0.companyID == cid })
        let h0 = cash(e, hid), p0 = e.state.cash
        let q = try e.holdingStakeQuote(holdingID: hid, companyID: cid, percent: 25).get()
        XCTAssertEqual(q.fromOwnerPercent, 25, accuracy: 0.01)
        XCTAssertEqual(q.fromOthersPercent, 0, accuracy: 1e-9)
        XCTAssertEqual(q.price, v * 0.25, accuracy: tolerance(v))
        XCTAssertEqual(q.tierAfter, .influence)
        let deal = try e.holdingBuyStake(holdingID: hid, companyID: cid, percent: 25).get()
        XCTAssertEqual(deal.amount, q.price, accuracy: 1e-9)
        XCTAssertEqual(cash(e, hid), h0 - q.price, accuracy: 1e-6)
        XCTAssertEqual(e.state.cash, p0 + q.price, accuracy: 1, "the owner is paid for the shares")
        let co = try XCTUnwrap(e.state.company(cid))
        XCTAssertEqual(pct(e, hid, cid), 25, accuracy: 0.01)
        XCTAssertEqual(co.ownership, 45, accuracy: 0.01)
        XCTAssertEqual(co.value("holders").array.first { $0["name"].string == "Angel" }?["pct"].double ?? 0, 30, accuracy: 0.01)
        let t = CapTable.table(co)
        XCTAssertEqual(t.you + t.holders.reduce(0) { $0 + $1.shares }, t.total, "shares still add up")
        XCTAssertEqual(e.holdingStakeTier(holdingID: hid, companyID: cid), .influence)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testOutsiderSharesCostMoreOrLessByTier() throws {
        var (e, hid, cid) = try setup()
        let v = value(e, cid)
        let p0 = e.state.cash
        let small = try e.holdingStakeQuote(holdingID: hid, companyID: cid, percent: 10, from: .others).get()
        XCTAssertEqual(small.priceFactor, HoldingStakes.minorityDiscount)
        XCTAssertEqual(small.price, v * 0.10 * 0.85, accuracy: tolerance(v))
        _ = try e.holdingBuyStake(holdingID: hid, companyID: cid, percent: 10, from: .others).get()
        XCTAssertEqual(e.state.cash, p0, accuracy: 1, "nothing is paid to you when outsiders sell")
        XCTAssertEqual(pct(e, hid, cid), 10, accuracy: 0.01)
        XCTAssertEqual(e.holdingStakeTier(holdingID: hid, companyID: cid), .passive)
        XCTAssertEqual(try XCTUnwrap(e.state.company(cid)).ownership, 70, accuracy: 0.01, "your own share did not change")
        // outsiders hold 20% now; 15% more takes the holding to 25%, the price of an influence stake
        let more = try e.holdingStakeQuote(holdingID: hid, companyID: cid, percent: 15, from: .others).get()
        XCTAssertEqual(more.priceFactor, 1)
        XCTAssertEqual(more.price, v * 0.15, accuracy: tolerance(v))
        _ = try e.holdingBuyStake(holdingID: hid, companyID: cid, percent: 15, from: .others).get()
        XCTAssertEqual(e.holdingStakeTier(holdingID: hid, companyID: cid), .influence)
        let rest = try XCTUnwrap(e.state.company(cid)).value("holders").array.first { $0["name"].string == "Angel" }
        XCTAssertEqual(rest?["pct"].double ?? 0, 5, accuracy: 0.01)
        // more than is for sale is refused with a reason
        if case .failure(let f) = e.holdingStakeQuote(holdingID: hid, companyID: cid, percent: 10, from: .others) { XCTAssertFalse(f.reason.isEmpty) } else { XCTFail("only 5% is left to buy") }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testRefusalsCarryReasons() throws {
        var (e, hid, cid) = try setup()
        if case .failure(let f) = e.holdingBuyStake(holdingID: cid, companyID: cid, percent: 10) { XCTAssertEqual(f, .notAHolding) } else { XCTFail("a company is not a holding") }
        if case .failure(let f) = e.holdingBuyStake(holdingID: hid, companyID: cid, percent: 0) { XCTAssertFalse(f.reason.isEmpty) } else { XCTFail("zero percent") }
        if case .failure(let f) = e.holdingBuyStake(holdingID: hid, companyID: 999_999, percent: 10) { XCTAssertEqual(f, .notFound) } else { XCTFail("no such company") }
        e.update { s, _, _ in Ledger.moveRaw(&s, .company(hid), -(s.company(hid)?.cash ?? 0)) }
        let before = try XCTUnwrap(e.state.company(cid)).ownership
        if case .failure(.notEnoughCash(let need)) = e.holdingBuyStake(holdingID: hid, companyID: cid, percent: 25) { XCTAssertGreaterThan(need, 0) } else { XCTFail("the holding has no cash") }
        XCTAssertEqual(try XCTUnwrap(e.state.company(cid)).ownership, before, "nothing changed")
        XCTAssertEqual(pct(e, hid, cid), 0)
    }

    func testMergeNeedsTheThreshold() throws {
        var (e, hid, cid) = try setup()
        _ = try e.holdingBuyStake(holdingID: hid, companyID: cid, percent: 60).get()
        XCTAssertEqual(e.holdingStakeTier(holdingID: hid, companyID: cid), .control)
        let terms = e.holdingMergeTerms(holdingID: hid, companyID: cid)
        XCTAssertFalse(terms.allowed, "control, but an outside investor still holds 30%")
        XCTAssertFalse(terms.reason.isEmpty)
        if case .failure = e.holdingMergeStake(holdingID: hid, companyID: cid) {} else { XCTFail("no forced merge below 90%") }
        XCTAssertEqual(try XCTUnwrap(e.state.company(cid)).holdingID, 0)

        _ = try e.holdingBuyStake(holdingID: hid, companyID: cid, percent: 30, from: .others).get()
        XCTAssertEqual(e.holdingStakeTier(holdingID: hid, companyID: cid), .squeezeOut)
        let v = value(e, cid)
        let squeeze = e.holdingMergeTerms(holdingID: hid, companyID: cid)
        XCTAssertTrue(squeeze.allowed, squeeze.reason)
        XCTAssertEqual(squeeze.cost, v * 0.10, accuracy: tolerance(v), "the last 10% at fair value")
        XCTAssertEqual(squeeze.paidToYou, squeeze.cost, accuracy: 1, "that 10% is yours")

        let nw0 = e.netWorth.total
        let h0 = cash(e, hid)
        let paid = try e.holdingMergeStake(holdingID: hid, companyID: cid).get()
        XCTAssertEqual(paid, squeeze.cost, accuracy: 1e-9)
        XCTAssertEqual(cash(e, hid), h0 - paid, accuracy: 1e-6)
        let co = try XCTUnwrap(e.state.company(cid))
        XCTAssertEqual(co.holdingID, hid)
        XCTAssertEqual(co.ownership, 100, accuracy: 1e-9)
        XCTAssertTrue(co.value("holders").array.isEmpty)
        XCTAssertEqual(CapTable.table(co).you, CapTable.table(co).total)
        XCTAssertTrue(HoldingModel.subsidiaries(of: hid, in: e.state).contains { $0.id == cid })
        XCTAssertEqual(e.holdingStakeTier(holdingID: hid, companyID: cid), .whole)
        XCTAssertEqual(e.netWorth.total, nw0, accuracy: tolerance(v), "buying the rest at fair value does not change what you are worth")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testMergeWithControlWhenOnlyYouOwnTheRest() throws {
        var (e, hid, cid) = try setup()
        _ = try e.holdingBuyStake(holdingID: hid, companyID: cid, percent: 30, from: .others).get()   // the investor sells; you hold the rest
        XCTAssertEqual(e.holdingStakeTier(holdingID: hid, companyID: cid), .influence)
        XCTAssertFalse(e.holdingMergeTerms(holdingID: hid, companyID: cid).allowed, "30% is not control")
        _ = try e.holdingBuyStake(holdingID: hid, companyID: cid, percent: 30).get()   // 30% more of your own shares: 60% in all
        XCTAssertEqual(pct(e, hid, cid), 60, accuracy: 0.01)
        let terms = e.holdingMergeTerms(holdingID: hid, companyID: cid)
        XCTAssertTrue(terms.allowed, terms.reason)
        XCTAssertEqual(terms.paidToYou, terms.cost, accuracy: 1)
    }

    func testNoDoubleCountingInNetWorth() throws {
        var (e, hid, cid) = try setup()
        let v = value(e, cid)
        let nw0 = e.netWorth.total
        _ = try e.holdingBuyStake(holdingID: hid, companyID: cid, percent: 25).get()
        XCTAssertEqual(e.netWorth.total, nw0, accuracy: tolerance(v), "cash turned into shares of the same value")
        let fm = try XCTUnwrap(e.state.company(hid)).value("fm")
        XCTAssertEqual(fm["assets"].double, v * 0.25, accuracy: tolerance(v), "the holding's assets are company value x its share")
        let o = try XCTUnwrap(e.holdingOverview(companyID: hid))
        XCTAssertEqual(o.companiesValue, v * 0.25, accuracy: tolerance(v))
        XCTAssertEqual(o.subsidiaries.first { $0.id == cid }?.ownership ?? 0, 25, accuracy: 0.01)
        // moving your remaining shares under the holding does not change net worth either
        XCTAssertTrue(e.moveToHolding(companyID: cid, holdingID: hid))
        XCTAssertEqual(pct(e, hid, cid), 70, accuracy: 0.01, "25% bought + your 45% moved")
        XCTAssertEqual(e.netWorth.total, nw0, accuracy: tolerance(v))
    }

    func testPartialMoveKeepsTheRestPersonal() throws {
        var (e, hid, cid) = try setup()
        let v = value(e, cid)
        let nw0 = e.netWorth.total
        let r = try e.moveToHolding(companyID: cid, holdingID: hid, percent: 40).get()
        XCTAssertEqual(r, 40, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(e.state.company(cid)).ownership, 30, accuracy: 0.01, "you keep 30% personally")
        XCTAssertEqual(try XCTUnwrap(e.state.company(cid)).holdingID, 0)
        XCTAssertEqual(e.holdingStakeTier(holdingID: hid, companyID: cid), .influence)
        XCTAssertEqual(e.netWorth.total, nw0, accuracy: tolerance(v))
        XCTAssertTrue(e.holdingReleaseStake(holdingID: hid, companyID: cid))
        XCTAssertEqual(try XCTUnwrap(e.state.company(cid)).ownership, 70, accuracy: 0.01)
        XCTAssertEqual(e.netWorth.total, nw0, accuracy: tolerance(v))
        // the whole-company move still works as before
        XCTAssertTrue(e.moveToHolding(companyID: cid, holdingID: hid))
        XCTAssertEqual(try XCTUnwrap(e.state.company(cid)).holdingID, hid)
        XCTAssertTrue(e.releaseFromHolding(companyID: cid))
        XCTAssertEqual(try XCTUnwrap(e.state.company(cid)).holdingID, 0)
    }

    func testDividendsGoToHoldersProRata() throws {
        var (e, hid, cid) = try setup()
        _ = try e.holdingBuyStake(holdingID: hid, companyID: cid, percent: 25).get()   // holding 25%, you 45%, investor 30%
        let amount = (e.maximumDividend(companyID: cid) * 0.5).rounded(.down)
        XCTAssertGreaterThan(amount, 0)
        let h0 = cash(e, hid), p0 = e.state.cash
        let hp = pct(e, hid, cid), mine = try XCTUnwrap(e.state.company(cid)).ownership
        XCTAssertEqual(e.payDividend(companyID: cid, amount: amount), .ok)
        XCTAssertEqual(cash(e, hid) - h0, amount * hp / 100, accuracy: 1e-6, "the holding's share lands in its cash")
        XCTAssertEqual(e.state.cash - p0, amount * mine / 100, accuracy: 1, "your own share is paid to you")
        XCTAssertEqual((cash(e, hid) - h0) / amount, 0.25, accuracy: 0.0001)
        XCTAssertEqual((e.state.cash - p0) / amount, 0.45, accuracy: 0.0001)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testSellingBackToTheMarketAndToYou() throws {
        var (e, hid, cid) = try setup()
        let v = value(e, cid)
        _ = try e.holdingBuyStake(holdingID: hid, companyID: cid, percent: 25).get()
        let h0 = cash(e, hid)
        let q = try e.holdingSellStakeQuote(holdingID: hid, companyID: cid, percent: 10).get()
        XCTAssertEqual(q.priceFactor, 0.9, "an influence stake sells at a discount")
        XCTAssertEqual(q.price, v * 0.10 * 0.9, accuracy: tolerance(v))
        _ = try e.holdingSellStake(holdingID: hid, companyID: cid, percent: 10).get()
        XCTAssertEqual(cash(e, hid), h0 + q.price, accuracy: 1e-6)
        XCTAssertEqual(pct(e, hid, cid), 15, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(e.state.company(cid)).ownership, 45, accuracy: 0.01)
        // selling to you is at fair value and the shares come back to you
        let p0 = e.state.cash
        let toYou = try e.holdingSellStake(holdingID: hid, companyID: cid, percent: 15, to: .owner).get()
        XCTAssertEqual(toYou.amount, v * 0.15, accuracy: tolerance(v))
        XCTAssertEqual(e.state.cash, p0 - toYou.amount, accuracy: 1)
        XCTAssertEqual(pct(e, hid, cid), 0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(e.state.company(cid)).ownership, 60, accuracy: 0.01)
        if case .failure(let f) = e.holdingSellStake(holdingID: hid, companyID: cid, percent: 5) { XCTAssertFalse(f.reason.isEmpty) } else { XCTFail("nothing left to sell") }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testBoardSeatNeedsInfluenceAndOpensTheBoardCalls() throws {
        var (e, hid, cid) = try setup()
        _ = try e.holdingBuyStake(holdingID: hid, companyID: cid, percent: 10, from: .others).get()
        let passive = e.holdingBoardSeat(holdingID: hid, companyID: cid)
        XCTAssertFalse(passive.canTake)
        XCTAssertFalse(passive.reason.isEmpty)
        if case .failure = e.holdingTakeBoardSeat(holdingID: hid, companyID: cid) {} else { XCTFail("a passive stake has no seat") }
        if case .failure = e.holdingBoardRound(holdingID: hid, companyID: cid) {} else { XCTFail("no seat, no round") }

        _ = try e.holdingBuyStake(holdingID: hid, companyID: cid, percent: 15, from: .others).get()   // 25%
        XCTAssertTrue(e.holdingBoardSeat(holdingID: hid, companyID: cid).canTake)
        _ = try e.holdingTakeBoardSeat(holdingID: hid, companyID: cid).get()
        let seat = e.holdingBoardSeat(holdingID: hid, companyID: cid)
        XCTAssertTrue(seat.hasSeat)
        XCTAssertEqual(seat.votePercent, 25, accuracy: 0.01)
        _ = try e.holdingBoardRound(holdingID: hid, companyID: cid).get()
        let vote = try e.holdingBoardVote(holdingID: hid, companyID: cid, kind: "sell").get()
        XCTAssertTrue(vote.owners.contains { $0.title == "Your holding" && $0.isYou }, "the holding votes on your side")
        XCTAssertEqual(HoldingStakes.votingPercent(try XCTUnwrap(e.state.company(cid))), 95, accuracy: 0.01, "your 70% and the holding's 25%")
        _ = try e.holdingLeaveBoardSeat(holdingID: hid, companyID: cid).get()
        XCTAssertFalse(e.holdingBoardSeat(holdingID: hid, companyID: cid).hasSeat)
    }

    func testControlGivesTheSeatWithoutChoosing() throws {
        var (e, hid, cid) = try setup()
        _ = try e.holdingBuyStake(holdingID: hid, companyID: cid, percent: 60).get()
        XCTAssertEqual(e.holdingStakeTier(holdingID: hid, companyID: cid), .control)
        XCTAssertTrue(e.holdingBoardSeat(holdingID: hid, companyID: cid).hasSeat)
        _ = try e.holdingBoardRound(holdingID: hid, companyID: cid).get()
    }

    func testRivalStakeBuyAndSell() throws {
        var (e, hid, _) = try setup()
        guard let offer = e.holdingStakeOffers(holdingID: hid).first(where: { !$0.isOwn }), let rid = offer.rivalID else { throw XCTSkip("no rival in this market yet") }
        let h0 = cash(e, hid)
        switch e.holdingBuyRivalStake(holdingID: hid, rivalID: rid, percent: 10) {
        case .failure(let f):
            XCTAssertFalse(f.reason.isEmpty)
        case .success(let deal):
            XCTAssertEqual(cash(e, hid), h0 - deal.amount, accuracy: 1e-6)
            let st = try XCTUnwrap(e.holdingRivalStakes(holdingID: hid).first { $0.id == rid })
            XCTAssertEqual(st.percent, 10, accuracy: 1e-9)
            XCTAssertEqual(try XCTUnwrap(e.state.company(hid)).value("fm")["assets"].double, st.share, accuracy: tolerance(st.value), "rival stakes are in the holding's assets")
            let sold = try e.holdingSellRivalStake(holdingID: hid, rivalID: rid, percent: 10).get()
            XCTAssertTrue(e.holdingRivalStakes(holdingID: hid).isEmpty)
            XCTAssertEqual(cash(e, hid), h0 - deal.amount + sold.amount, accuracy: 1e-6)
        }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testStakeSurvivesAWeekOfPlay() throws {
        var (e, hid, cid) = try setup()
        _ = try e.holdingBuyStake(holdingID: hid, companyID: cid, percent: 25).get()
        ChainsTests.play(&e, days: 8)
        let co = try XCTUnwrap(e.state.company(cid))
        let t = CapTable.table(co)
        XCTAssertEqual(t.you + t.holders.reduce(0) { $0 + $1.shares }, t.total)
        XCTAssertEqual(pct(e, hid, cid), 25, accuracy: 0.01)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }
}
