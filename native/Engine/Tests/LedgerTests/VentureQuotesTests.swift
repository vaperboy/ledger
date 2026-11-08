import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Events
@testable import Simulation

/// Quotes match what the venture actions do; asking prices on stake sales; a holding's stakes in startups.
final class VentureQuotesTests: XCTestCase {
    private func rich() throws -> GameEngine {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 92)
        e.update { s, d, _ in
            Ledger.move(&s, .me, 900_000_000, why: "Test funds")
            _ = Startups.pitches(&s, data: d)
        }
        return e
    }

    func testInvestAndCommitQuotesMatchTheActions() throws {
        var e = try rich()
        let pitch = try XCTUnwrap(e.startupPitchesOnOffer.first)
        let q = e.startupInvestQuote(pitchID: pitch.id, amount: pitch.raise)
        XCTAssertEqual(q.result, .ok)
        let before = Payments.liquid(e.state)
        XCTAssertEqual(e.investInStartup(pitchID: pitch.id, amount: pitch.raise), .ok)
        XCTAssertEqual(before - Payments.liquid(e.state), q.amount, accuracy: 0.01)
        XCTAssertEqual(e.startupStakes.last?.ownership ?? 0, q.ownershipPercent, accuracy: 1e-9)
        XCTAssertEqual(e.startupInvestQuote(pitchID: pitch.id, amount: 1).result, .gone)

        let offer = e.privateEquityOffers()[0]
        let check = e.fundCommitCheck(offerID: offer.id, amount: offer.minimum)
        XCTAssertEqual(check.result, .ok)
        XCTAssertEqual(e.fundCommitCheck(offerID: offer.id, amount: 1).result, .tooSmall)
        XCTAssertEqual(e.fundCommitCheck(offerID: offer.id, amount: check.netWorth * 2).result, .notRichEnough)
        XCTAssertEqual(e.commitToFund(offerID: offer.id, amount: offer.minimum), check.result)
    }

    func testStakeSaleQuoteAndAskingPrice() throws {
        var e = try rich()
        let pitches = e.startupPitchesOnOffer
        XCTAssertEqual(e.investInStartup(pitchID: pitches[0].id, amount: pitches[0].raise), .ok)
        XCTAssertEqual(e.investInStartup(pitchID: pitches[1].id, amount: pitches[1].raise), .ok)
        let ids = e.startupStakes.map { $0.id }
        let q = e.startupStakeSellQuote(stakeID: ids[0], fraction: 0.5)
        XCTAssertTrue(q.ok)
        XCTAssertEqual(q.factor, 0.72, accuracy: 1e-9)
        // default: exactly the quote
        let before = Payments.liquid(e.state)
        XCTAssertEqual(e.sellStartupStake(stakeID: ids[0], fraction: 0.5, askingMultiplier: nil), .sold(q.proceeds))
        XCTAssertEqual(Payments.liquid(e.state) - before, q.proceeds, accuracy: 0.01)
        // a lower ask always sells, at the ask
        let q1 = e.startupStakeSellQuote(stakeID: ids[1], fraction: 0.5)
        XCTAssertEqual(e.sellStartupStake(stakeID: ids[1], fraction: 0.5, askingMultiplier: 0.8).proceeds, jsRound(q1.proceeds * 0.8), accuracy: 0.01)
        // an absurd ask is declined and nothing is sold; talks are closed for the week
        let pct = e.startupStakes[1].ownership
        let hi = e.sellStartupStake(stakeID: ids[1], fraction: 0.5, askingMultiplier: 9)
        if case .sold = hi { XCTFail("above the buyer's valuation") }
        XCTAssertEqual(e.startupStakes[1].ownership, pct, accuracy: 1e-9)
        if case .declined = hi {
            guard case .declined = e.sellStartupStake(stakeID: ids[1], fraction: 0.5, askingMultiplier: 1.39) else { return XCTFail("talks are closed for the week") }
        }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testFundSecondaryAskCounterAcceptedExactly() throws {
        var e = try rich()
        let offer = e.privateEquityOffers()[0]
        XCTAssertEqual(e.commitToFund(offerID: offer.id, amount: offer.minimum), .ok)
        e.update { s, _, _ in
            var pe = s.rest["pe56"]!
            var mine = pe["mine"].array
            mine[0]["nav"] = .number(offer.minimum); mine[0]["paid"] = .number(offer.minimum)
            pe["mine"] = .array(mine); s.rest["pe56"] = pe
        }
        let fund = try XCTUnwrap(e.privateEquityFunds.first)
        let q = e.fundSecondaryQuote(fundID: fund.id)
        XCTAssertEqual(q.proceeds, e.secondaryPrice(fundID: fund.id), accuracy: 0.01)
        var counter: Double?
        for m in stride(from: 1.05, through: 1.4, by: 0.05) where counter == nil {
            var probe = e
            if case .counter(let c)? = probe.sellFundStake(fundID: fund.id, askingMultiplier: m) { counter = c }
        }
        if let c = counter {
            XCTAssertEqual(e.sellFundStake(fundID: fund.id, askingMultiplier: c / q.proceeds), .sold(c))
        } else {
            XCTAssertEqual(e.sellFundStake(fundID: fund.id, askingMultiplier: nil), .sold(q.proceeds))
        }
        XCTAssertNil(e.sellFundStake(fundID: fund.id, askingMultiplier: nil))
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testGroupStakeQuoteAndResult() throws {
        var e = try rich()
        XCTAssertEqual(e.groupStakeQuote(groupID: "nope", fraction: 0.1, multiplier: 1, chance: 1).refusal, .noGroup)
        e.update { s, _, _ in
            s.rest["g27"] = .object(["g": .object(["g1": .object(["name": "Acme Group", "owner": "Pat", "rev": 50_000_000, "m": 0.2, "debt": 1_000_000, "cash": 5_000_000, "strat": "cautious"])])])
        }
        let q = e.groupStakeQuote(groupID: "g1", fraction: 0.1, multiplier: 1.1, chance: 1)
        XCTAssertNil(q.refusal)
        XCTAssertEqual(e.groupStakeQuote(groupID: "g1", fraction: 0, multiplier: 1, chance: 1).refusal, .badFraction)
        let before = Payments.liquid(e.state)
        XCTAssertEqual(e.buyGroupStake(groupID: "g1", fraction: 0.1, multiplier: 1.1, chance: 1), .success(q.price))
        XCTAssertEqual(before - Payments.liquid(e.state), q.price, accuracy: 0.01)
        XCTAssertEqual(e.buyGroupStake(groupID: "g1", fraction: 0.1, multiplier: 1.1, chance: 0), .failure(.outbid))
        XCTAssertEqual(e.buyGroupStake(groupID: "g1", fraction: 0.95, multiplier: 1.1, chance: 1), .failure(.alreadyHold(0.1)))
    }

    func testHoldingBuysStartupSharesWithTiersAndNetWorthOnce() throws {
        var e = try ChainsTests.engine("UK")
        guard case .success(let hid) = e.createHolding(name: "H", companies: []) else { throw XCTSkip("holding was not created") }
        e.update { s, d, _ in
            _ = Payments.injectCash(&s, companyID: hid, amount: 3_000_000_000)
            _ = Startups.pitches(&s, data: d)
        }
        let pitch = try XCTUnwrap(e.startupPitchesOnOffer.first)
        let nw0 = Valuation.netWorth(e.state, trades: e.data.catalog).total
        guard case .success(let q) = e.holdingStartupInvestQuote(holdingID: hid, pitchID: pitch.id, amount: pitch.raise) else { return XCTFail("quote") }
        let cash0 = e.state.company(hid)!.cash
        guard case .success(let deal) = e.holdingInvestInStartup(holdingID: hid, pitchID: pitch.id, amount: pitch.raise) else { return XCTFail("invest") }
        XCTAssertEqual(deal.percent, q.ownershipPercent, accuracy: 1e-9)
        XCTAssertEqual(cash0 - e.state.company(hid)!.cash, q.amount, accuracy: 0.01)
        XCTAssertTrue(e.startupStakes.isEmpty, "a holding's stake is not one of the player's own")
        let stake = try XCTUnwrap(e.holdingStartupStakes(holdingID: hid).first)
        XCTAssertEqual(stake.tier, HoldingStakes.tier(forPercent: stake.percent))
        // net worth moves by the money turned into shares, not by double counting
        let nw1 = Valuation.netWorth(e.state, trades: e.data.catalog).total
        XCTAssertEqual(nw1 - nw0, 0, accuracy: q.amount * 0.01 + 1)
        // seed-stage startups cannot be taken over
        if case .success = e.holdingStartupBuyMoreQuote(holdingID: hid, stakeID: stake.id, percent: 60) { XCTFail("no control before a priced round") }
        guard case .success(let more) = e.holdingStartupBuyMoreQuote(holdingID: hid, stakeID: stake.id, percent: 5) else { return XCTFail("more") }
        XCTAssertEqual(more.heldAfter, stake.percent + 5, accuracy: 1e-9)
        guard case .success = e.holdingBuyMoreOfStartup(holdingID: hid, stakeID: stake.id, percent: 5) else { return XCTFail("buy more") }
        guard case .success(let sale) = e.holdingSellStartupStake(holdingID: hid, stakeID: stake.id, fraction: 0.5) else { return XCTFail("sell") }
        XCTAssertGreaterThan(sale.proceeds, 0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        for _ in 0..<(80 * 7) { e.nextDay() }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }
}
