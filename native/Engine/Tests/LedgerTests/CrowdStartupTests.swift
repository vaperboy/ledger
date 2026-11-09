import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Events
@testable import Simulation

/// Startups funded by other players: price rule, caps, escrow, resale band, taxes, viral, and the exploits that must not pay.
final class CrowdStartupTests: XCTestCase {
    typealias R = CrowdStartupRules

    private func plan() -> R.Plan { R.Plan(cost: 900_000, founderPutIn: 300_000) }
    private func startup(linkKey: String = "founderKey") -> R.Startup {
        R.Startup(id: "S1", name: "Nova", trade: "Software", founderID: "f1", founderName: "Fay", founderLinkKey: linkKey, plan: plan(), createdDay: 0)
    }
    private func game(seed: Int = 5) throws -> GameEngine {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 5_000_000_000, why: "Test funds") }
        return e
    }
    private func checkOK(_ r: R.InvestResult, file: StaticString = #filePath, line: UInt = #line) -> R.Quote? {
        if case .ok(let q) = r { return q }
        XCTFail("expected ok, got \(r)", file: file, line: line); return nil
    }
    private func liveStartup() -> R.Startup {
        var st = startup()
        st.status = .live
        st.assets = 1_000_000
        st.weeklyProfit = Array(repeating: 10_000, count: 13)
        return st
    }

    func testPlanNeedsAThirdFromTheFounder() {
        XCTAssertTrue(R.Plan(cost: 900, founderPutIn: 300).valid)
        XCTAssertFalse(R.Plan(cost: 900, founderPutIn: 299).valid)
        XCTAssertLessThan(R.maxInvestorPercent(plan()), 49, "investors can never take control")
        XCTAssertEqual(R.stageShares.reduce(0, +), 1, accuracy: 1e-9)
    }

    func testPriceComesOnlyFromPlanAndStage() {
        let p = plan()
        XCTAssertEqual(R.pricePerPercent(p, stage: 0), 900_000 * 1.25 / 100, accuracy: 1e-6)
        XCTAssertGreaterThan(R.pricePerPercent(p, stage: 2), R.pricePerPercent(p, stage: 0), "later stages cost more")
        var q = startup()
        let a = checkOK(R.investCheck(q, investorID: "i1", linkKeys: ["i1"], accountWeeks: 10, amount: 40_000, today: 5))
        q.investments.append(.init(id: "x", investorID: "i2", linkKey: "i2", stage: 0, amount: 100_000, percent: 4, day: 1))
        let b = checkOK(R.investCheck(q, investorID: "i1", linkKeys: ["i1"], accountWeeks: 10, amount: 40_000, today: 5))
        XCTAssertEqual(a?.percent, b?.percent, "the price does not move with demand or with the founder")
    }

    func testCapsAndNewAccounts() {
        var st = startup()
        // Investor cap: 20% of 600k = 120k.
        XCTAssertEqual(R.investCheck(st, investorID: "i1", linkKeys: ["i1"], accountWeeks: 10, amount: 130_000, today: 0), .refused(.investorCap(room: 120_000)))
        // Stage 0 raise is 240k: two investors at 110k leave room for 20k.
        for k in 0..<2 { st.investments.append(.init(id: "a\(k)", investorID: "p\(k)", linkKey: "p\(k)", stage: 0, amount: 110_000, percent: 4, day: 0)) }
        XCTAssertEqual(R.investCheck(st, investorID: "i3", linkKeys: ["i3"], accountWeeks: 10, amount: 30_000, today: 0), .refused(.stageFull(room: 20_000)))
        XCTAssertEqual(R.investCheck(st, investorID: "i3", linkKeys: ["i3"], accountWeeks: 2, amount: 10_000, today: 0), .refused(.newAccount(weeksLeft: 2)))
        XCTAssertEqual(R.investCheck(st, investorID: "i3", linkKeys: ["i3"], accountWeeks: 10, amount: 100, today: 0), .refused(.tooSmall(minimum: 4_800)))
    }

    func testEscrowReleasesAtMilestonesAndRefundsOnFailure() {
        var st = startup()
        st.investments.append(.init(id: "a", investorID: "i1", linkKey: "i1", stage: 0, amount: 100_000, percent: 4, day: 0))
        XCTAssertEqual(st.escrowHeld, 100_000)
        XCTAssertEqual(R.reachMilestone(&st, today: 20), 100_000)
        XCTAssertEqual(st.escrowHeld, 0)
        XCTAssertEqual(st.openStage, 1)
        st.investments.append(.init(id: "b", investorID: "i1", linkKey: "i1", stage: 1, amount: 50_000, percent: 1.5, day: 21))
        let back = R.fail(&st)
        XCTAssertEqual(back.map { $0.amount }, [50_000], "only the unreleased stage comes back")
        XCTAssertEqual(st.status, .failed)
        var slow = startup()
        slow.investments.append(.init(id: "c", investorID: "i1", linkKey: "i1", stage: 0, amount: 60_000, percent: 2, day: 0))
        XCTAssertTrue(R.expire(&slow, today: 100).isEmpty)
        XCTAssertEqual(R.expire(&slow, today: R.stageDeadlineWeeks * 7 + 1).map { $0.amount }, [60_000])
    }

    func testViralNeedsManyDifferentInvestorsQuicklyAndAddsNoMoney() {
        var st = startup()
        for k in 0..<4 { st.investments.append(.init(id: "v\(k)", investorID: "p\(k)", linkKey: "p\(k)", stage: 0, amount: 10_000, percent: 0.4, day: 10 + k)) }
        XCTAssertFalse(st.viral(today: 14))
        st.investments.append(.init(id: "v4", investorID: "p4", linkKey: "p4", stage: 0, amount: 10_000, percent: 0.4, day: 14))
        XCTAssertTrue(st.viral(today: 14))
        XCTAssertFalse(st.viral(today: 40), "the same investors spread over time are not viral")
        var f = startup()
        for k in 0..<6 { f.investments.append(.init(id: "w\(k)", investorID: "alt\(k)", linkKey: "founderKey", stage: 0, amount: 10_000, percent: 0.4, day: 10)) }
        XCTAssertFalse(f.viral(today: 12))
        XCTAssertEqual(st.raisedTotal, 50_000, "viral changes visibility only")
    }

    func testLinkedAccountCannotFundTheFoundersStartup() {
        let st = startup(linkKey: "ownerA")
        XCTAssertEqual(R.investCheck(st, investorID: "altAccount", linkKeys: ["altAccount", "ownerA"], accountWeeks: 50, amount: 20_000, today: 0), .refused(.linkedToFounder))
        XCTAssertEqual(R.investCheck(st, investorID: "f1", linkKeys: ["f1"], accountWeeks: 50, amount: 20_000, today: 0), .refused(.linkedToFounder))
    }

    func testResaleLockBandAndTaxes() {
        let st = liveStartup()
        let h = R.Holding(startupID: "S1", ownerID: "a", linkKey: "a", percent: 5, paid: 40_000, boughtDay: 0)
        let fair = R.fairPrice(st, percent: 5)
        XCTAssertEqual(fair, (1_000_000 + 130_000) * 0.05, accuracy: 1e-6)
        let locked = R.saleCheck(st, holding: h, percent: 5, price: fair, buyerID: "b", buyerLinkKeys: ["b"], buyerAccountWeeks: 20, gainsRate: 0.2, today: 10)
        XCTAssertEqual(locked, .refused(.locked(untilDay: 84)))
        let day = 84
        let outside: R.SaleResult = .refused(.outsideBand(low: fair * 0.8, high: fair * 1.25))
        XCTAssertEqual(R.saleCheck(st, holding: h, percent: 5, price: fair * 2, buyerID: "b", buyerLinkKeys: ["b"], buyerAccountWeeks: 20, gainsRate: 0.2, today: day), outside)
        XCTAssertEqual(R.saleCheck(st, holding: h, percent: 5, price: fair * 0.1, buyerID: "b", buyerLinkKeys: ["b"], buyerAccountWeeks: 20, gainsRate: 0.2, today: day), outside)
        guard case .ok(let q) = R.saleCheck(st, holding: h, percent: 5, price: fair, buyerID: "b", buyerLinkKeys: ["b"], buyerAccountWeeks: 20, gainsRate: 0.2, today: day) else { return XCTFail("sale") }
        XCTAssertEqual(q.transferTax, fair * 0.02, accuracy: 1e-6)
        XCTAssertEqual(q.gainsTax, (fair - 40_000) * 0.2, accuracy: 1e-6)
        XCTAssertEqual(R.saleCheck(st, holding: h, percent: 5, price: fair, buyerID: "b2", buyerLinkKeys: ["b2", "a"], buyerAccountWeeks: 20, gainsRate: 0.2, today: day), .refused(.linkedParties))
    }

    func testRoundTripSalesLoseMoney() {
        // Two cooperating accounts pass the same shares back and forth at the top of the band: every leg costs taxes, and the lock slows each leg.
        let st = liveStartup()
        var a = R.Holding(startupID: "S1", ownerID: "a", linkKey: "a", percent: 5, paid: 50_000, boughtDay: 0)
        var cashA = 0.0, cashB = 0.0
        var day = 100
        for _ in 0..<4 {
            let price = R.band(st, percent: a.percent).high
            guard case .ok(let q) = R.saleCheck(st, holding: a, percent: a.percent, price: price, buyerID: "b", buyerLinkKeys: ["b"], buyerAccountWeeks: 50, gainsRate: 0.2, today: day) else { return XCTFail("sale a") }
            cashA += q.sellerReceives; cashB -= q.buyerPays
            let b = R.Holding(startupID: "S1", ownerID: "b", linkKey: "b", percent: a.percent, paid: q.price, boughtDay: day)
            XCTAssertEqual(R.saleCheck(st, holding: b, percent: b.percent, price: price, buyerID: "a", buyerLinkKeys: ["a"], buyerAccountWeeks: 50, gainsRate: 0.2, today: day + 1),
                           .refused(.locked(untilDay: day + R.lockWeeks * 7)), "no quick flip")
            day += R.lockWeeks * 7
            let back = R.band(st, percent: b.percent).high
            guard case .ok(let q2) = R.saleCheck(st, holding: b, percent: b.percent, price: back, buyerID: "a", buyerLinkKeys: ["a"], buyerAccountWeeks: 50, gainsRate: 0.2, today: day) else { return XCTFail("sale b") }
            cashB += q2.sellerReceives; cashA -= q2.buyerPays
            a = R.Holding(startupID: "S1", ownerID: "a", linkKey: "a", percent: b.percent, paid: q2.price, boughtDay: day)
            day += R.lockWeeks * 7
        }
        XCTAssertLessThan(cashA + cashB, 0, "the cycle loses money to taxes: \(cashA + cashB)")
    }

    func testFoundingCostsMoreThanACompanyAndConservesMoney() throws {
        var e = try game()
        var q: CrowdStartups.FoundQuote?
        e.update { s, _, c in q = CrowdStartups.foundQuote(s, sector: "saas", who: "c2", seedMultiple: 1, planFactor: 3, context: c) }
        let quote = try XCTUnwrap(q)
        XCTAssertGreaterThan(quote.entryCost, quote.registration * 20, "entry cost is far above a normal opening cost")
        XCTAssertGreaterThanOrEqual(quote.plan.founderPutIn, quote.plan.cost / 3 - 1)
        let cash0 = e.state.cash
        var out: CrowdStartups.FoundOutcome?
        e.update { s, d, c in out = CrowdStartups.found(&s, name: "Crowdco", sector: "saas", product: "crm", model: "sub", who: "c2", seedMultiple: 1, planFactor: 3, pitch: "", accountWeeks: 10, level: 5, today: 0, data: d, context: c) }
        guard case .ok(var st) = try XCTUnwrap(out) else { return XCTFail("found") }
        XCTAssertLessThanOrEqual(cash0 - e.state.cash, quote.total + 1)
        XCTAssertGreaterThanOrEqual(cash0 - e.state.cash, quote.entryCost)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        // A mock investor funds stage 0; the milestone releases it to the real company and the cap table gains the investors.
        st.investments.append(.init(id: "m", investorID: "mock", linkKey: "mock", stage: 0, amount: 100_000, percent: R.percent(for: 100_000, plan: st.plan, stage: 0), day: 3))
        let cid = try XCTUnwrap(st.companyID)
        let before = try XCTUnwrap(e.state.company(cid)).cash
        var released = 0.0
        let value0 = Startups.founded(e.state, id: cid)?.valuation ?? 0
        e.update { s, _, _ in released = CrowdStartups.reachMilestone(&s, startup: &st, today: 40) }
        XCTAssertEqual(released, 100_000)
        XCTAssertEqual((Startups.founded(e.state, id: cid)?.valuation ?? 0) - value0, 100_000, accuracy: 1, "the valuation follows the released money at once")
        XCTAssertEqual(try XCTUnwrap(e.state.company(cid)).cash - before, 100_000, accuracy: 1)
        XCTAssertLessThan(try XCTUnwrap(e.state.company(cid)).ownership, 100)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        var refused = false
        e.update { s, d, c in
            if case .refused = CrowdStartups.found(&s, name: "X", sector: "saas", product: "crm", model: "sub", who: "c2", seedMultiple: 1, planFactor: 3, pitch: "", accountWeeks: 1, level: 5, today: 0, data: d, context: c) { refused = true }
        }
        XCTAssertTrue(refused, "a new account cannot found")
    }

    func testTheEntryCostGrowsWithThePlanSoABigRaiseIsNotCheap() throws {
        var e = try game()
        var small: CrowdStartups.FoundQuote?, big: CrowdStartups.FoundQuote?
        var rich: CrowdStartups.FoundQuote?
        e.update { s, _, c in
            small = CrowdStartups.foundQuote(s, sector: "saas", who: "c2", seedMultiple: 1, planFactor: 1.5, context: c)
            big = CrowdStartups.foundQuote(s, sector: "saas", who: "c2", seedMultiple: 1, planFactor: 3, context: c)
            rich = CrowdStartups.foundQuote(s, sector: "fintech", who: "c2", seedMultiple: 4, planFactor: 3, context: c)
        }
        let a = try XCTUnwrap(small), b = try XCTUnwrap(big), c = try XCTUnwrap(rich)
        XCTAssertGreaterThanOrEqual(b.entryCost, b.plan.cost * R.entryCostPlanShare - 1)
        XCTAssertGreaterThan(b.entryCost, a.entryCost)
        XCTAssertGreaterThanOrEqual(c.entryCost, c.plan.cost * R.entryCostPlanShare - 1, "the biggest plans pay the most")
        // What the investors can send is at most twice the founder's own money; the fee always costs more than a quarter of the raise it unlocks.
        XCTAssertGreaterThan(c.entryCost, c.plan.investorTarget * 0.25)
    }

    func testPlayerInvestingMovesMoneyThroughTheLedger() throws {
        var e = try game(seed: 9)
        var st = startup()
        let cash0 = e.state.cash
        var holdings: [R.Holding] = []
        var done = false
        e.update { s, _, _ in
            if case .ok(_, let h) = CrowdStartups.invest(&s, startup: &st, linkKeys: ["me"], accountWeeks: 10, amount: 50_000, today: 2) { CrowdStartups.add(h, to: &holdings); done = true }
        }
        XCTAssertTrue(done)
        XCTAssertEqual(cash0 - e.state.cash, 50_000, accuracy: 1)
        XCTAssertEqual(st.escrowHeld, 50_000)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        // The startup fails before the milestone: the escrow comes back whole.
        let back = R.fail(&st)
        let name = st.name
        e.update { s, _, _ in CrowdStartups.settleRefunds(&s, back, startupName: name) }
        XCTAssertEqual(cash0, e.state.cash, accuracy: 1)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        // A startup linked to the player and a new account are refused, and nothing moves.
        var linked = startup(linkKey: "me")
        var other = startup()
        let c1 = e.state.cash
        e.update { s, _, _ in
            if case .ok = CrowdStartups.invest(&s, startup: &linked, linkKeys: ["me"], accountWeeks: 10, amount: 50_000, today: 2) { XCTFail("linked") }
            if case .ok = CrowdStartups.invest(&s, startup: &other, linkKeys: ["me"], accountWeeks: 1, amount: 50_000, today: 2) { XCTFail("new") }
        }
        XCTAssertEqual(c1, e.state.cash)
    }

    func testPlayerSellingAndBuyingLosesToTaxesAndKeepsBooksBalanced() throws {
        var e = try game(seed: 11)
        let st = liveStartup()
        var mine = R.Holding(startupID: "S1", ownerID: "me", linkKey: "me", percent: 5, paid: 40_000, boughtDay: 0)
        let fair = R.fairPrice(st, percent: 5)
        let cash0 = e.state.cash
        var res: Result<R.SaleQuote, CrowdStartups.SaleFailure>?
        e.update { s, _, _ in res = CrowdStartups.sell(&s, startup: st, holding: &mine, percent: 5, price: fair, buyerID: "mock", buyerLinkKeys: ["mock"], buyerAccountWeeks: 20, gainsRate: 0.2, today: 100) }
        let q = try XCTUnwrap(res).get()
        XCTAssertEqual(e.state.cash - cash0, q.sellerReceives, accuracy: 1)
        XCTAssertEqual(mine.percent, 0, accuracy: 1e-9)
        // Buying the same shares back costs the price plus the transfer tax: the cycle is a loss.
        let seller = R.Holding(startupID: "S1", ownerID: "mock", linkKey: "mock", percent: 5, paid: fair, boughtDay: 0)
        var buy: Result<(R.SaleQuote, R.Holding), CrowdStartups.SaleFailure>?
        e.update { s, _, _ in buy = CrowdStartups.buy(&s, startup: st, from: seller, percent: 5, price: fair, accountWeeks: 20, linkKeys: ["me"], gainsRate: 0.2, today: 200) }
        _ = try XCTUnwrap(buy).get()
        XCTAssertLessThan(e.state.cash, cash0, "sold and bought back: taxes made it a loss")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }
}
