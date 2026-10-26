import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

/// A franchise brand fixes how its units sell (format, menu, price tier) and how they may market locally; the choices are written
/// at the grant, shown as locked with the reason, and honoured by every way of starting a campaign.
final class FranchiseStandardsTests: XCTestCase {
    private func brands(_ e: GameEngine, tier: Int, trades: [String]? = nil) -> [FranchiseBrands.Brand] {
        let w = World(state: e.state, data: e.data)
        return (trades ?? FranchiseBrands.tradeIDs).flatMap { FranchiseBrands.brands($0, country: "NO", w) }.filter { $0.tier == tier }
    }

    /// A company of the brand's trade, granted the franchise as the engine does it.
    private func franchisee(_ e: inout GameEngine, _ b: FranchiseBrands.Brand) -> Int {
        let id = ChainsTests.start(&e, b.tradeID)
        e.update { s, d, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].status = .open
            let t = FranchiseBrands.Terms(fee: 0, royalty: b.royalty, marketing: b.marketingFund, cover: 0, rent: 0, vehicles: 0, building: 0, brandID: b.id)
            FranchiseBrands.applyToCompany(&s, companyIndex: i, brand: b, terms: t, data: d)
        }
        return id
    }

    func testBrandsDictateTheirFormatAtGrantAcrossSeedsAndTiers() throws {
        var checked = 0, locked = 0
        for seed in [3, 11, 29, 57] {
            var e = try ChainsTests.engine(seed: seed)
            for tier in 1...4 {
                for b in brands(e, tier: tier) {
                    let id = franchisee(&e, b)
                    let co = try XCTUnwrap(e.state.company(id)), bd = try XCTUnwrap(e.data.catalog[b.tradeID])
                    let rules = FranchiseStandards.table.knobs[b.tradeID] ?? []
                    for k in bd.knobs {
                        let rule = rules.first { $0.knob == k.id }
                        let std = co.value("franchise")["knobStd"][k.id]
                        if let rule, b.tier >= rule.fromTier {
                            XCTAssertFalse(std.isNull, "\(b.id) fixes \(k.id)")
                            XCTAssertEqual(co.value("knob")[k.id].int, std.int)
                            XCTAssertTrue(k.options[std.int].requiredDocs.isEmpty)
                            XCTAssertNotNil(e.knobGovernedBy(companyID: id, knob: k.id))
                            XCTAssertTrue(e.knobGovernedBy(companyID: id, knob: k.id)!.contains(b.name))
                            let other = k.options.indices.first { $0 != std.int }!
                            if case .refused(let why) = e.changeKnob(companyID: id, knob: k.id, option: other) { XCTAssertTrue(why.contains(b.name), why) } else { XCTFail("locked") }
                            locked += 1
                        } else {
                            XCTAssertTrue(std.isNull, "\(b.id) leaves \(k.id) to the franchisee")
                            XCTAssertNil(e.knobGovernedBy(companyID: id, knob: k.id))
                        }
                        checked += 1
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 100); XCTAssertGreaterThan(locked, 10)
    }

    func testTheSameBrandAlwaysDictatesTheSameChoiceAndLocalBrandsDictateNothing() throws {
        var e = try ChainsTests.engine()
        let b = try XCTUnwrap(brands(e, tier: 3, trades: ["cafe", "gym", "barber", "restaurant", "bakery"]).first)
        let bd = try XCTUnwrap(e.data.catalog[b.tradeID])
        XCTAssertEqual(FranchiseStandards.knobStandards(brand: b, trade: bd), FranchiseStandards.knobStandards(brand: b, trade: bd))
        var local = b; local.tier = 1
        XCTAssertTrue(FranchiseStandards.knobStandards(brand: local, trade: bd).isEmpty)
        let id = franchisee(&e, b)
        XCTAssertFalse(try XCTUnwrap(e.state.company(id)).value("franchise")["knobStd"].isNull)
    }

    func testLocalCampaignsFollowTheAgreement() throws {
        var e = try ChainsTests.engine()
        let free = franchisee(&e, try XCTUnwrap(brands(e, tier: 1).first))
        let budget = try XCTUnwrap(e.marketing.channels["flyer"]).budgets(in: e.currency(for: try XCTUnwrap(e.state.company(free)))).first { $0 > 0 }!
        // tier 1: free
        XCTAssertEqual(e.setCampaign(companyID: free, channel: "tiktok", weeklyBudget: budget), .done)
        // tier 3: only the listed channels
        let b3 = try XCTUnwrap(brands(e, tier: 3).first)
        let c3 = franchisee(&e, b3)
        XCTAssertEqual(e.setCampaign(companyID: c3, channel: "flyer", weeklyBudget: budget), .done)
        if case .refused(let why) = e.setCampaign(companyID: c3, channel: "tiktok", weeklyBudget: budget) { XCTAssertTrue(why.contains(b3.name), why) } else { XCTFail("tiktok not allowed") }
        XCTAssertNotNil(e.campaignPlan(companyID: c3, channel: "tiktok", weeklyBudget: budget, weeks: nil)?.blocked)
        XCTAssertNil(e.campaignPlan(companyID: c3, channel: "flyer", weeklyBudget: budget, weeks: nil)?.blocked)
        // tier 4: the brand runs it all; stopping is always possible
        let b4 = try XCTUnwrap(brands(e, tier: 4).first)
        let c4 = franchisee(&e, b4)
        if case .refused(let why) = e.setCampaign(companyID: c4, channel: "google", weeklyBudget: budget) { XCTAssertTrue(why.contains("reserves local marketing"), why) } else { XCTFail("global brand reserves marketing") }
        XCTAssertEqual(e.setCampaign(companyID: c4, channel: "google", weeklyBudget: 0), .done)
        // an independent is unaffected
        let indep = ChainsTests.start(&e, "cafe")
        XCTAssertEqual(e.setCampaign(companyID: indep, channel: "tiktok", weeklyBudget: budget), .done)
    }

    /// A franchise unit that also belongs to the owner's own chain: the chain's brand marketing may only buy channels the franchise
    /// agreement allows, and the refusal shown for a forbidden channel names the franchise, not the chain.
    func testChainBrandMarketingRespectsTheFranchiseAgreement() throws {
        for tier in [3, 4] {
            var e = try ChainsTests.engine()
            let b = try XCTUnwrap(brands(e, tier: tier).first)
            let id = franchisee(&e, b)
            ChainsTests.season(&e, id)
            e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .open } }
            var chainID = 0
            e.update { s, _, _ in chainID = Chains.make(&s, companyID: id, name: "Mixed") ?? 0 }
            XCTAssertNotEqual(chainID, 0)
            e.setChainRule(chainID: chainID, rule: .marketing("heavy"))
            ChainsTests.play(&e, days: 21)
            let co = try XCTUnwrap(e.state.company(id))
            for ch in co.value("mk12").array { XCTAssertNil(FranchiseStandards.campaignRefusal(co, channel: ch.string), "tier \(tier): chain bought \(ch.string)") }
            for (ch, _) in co.value("mkt").object { XCTAssertNil(FranchiseStandards.campaignRefusal(co, channel: ch), "tier \(tier): running \(ch)") }
            if tier == 4 { XCTAssertTrue(co.value("mk12").array.isEmpty); XCTAssertTrue(co.value("mkt").object.isEmpty) }
            // a forbidden channel is refused for the franchise reason, and the plan says so
            let forbidden = try XCTUnwrap(e.marketing.channels.keys.sorted().first { FranchiseStandards.campaignRefusal(co, channel: $0) != nil })
            if case .refused(let why) = e.setCampaign(companyID: id, channel: forbidden, weeklyBudget: 20_000) { XCTAssertTrue(why.contains(b.name), why) } else { XCTFail("forbidden") }
            XCTAssertNotNil(e.campaignPlan(companyID: id, channel: forbidden, weeklyBudget: 20_000, weeks: nil)?.blocked)
        }
    }

    func testRequiredLocalMarketingTopsUpTheBrandFundAndTheBooksBalance() throws {
        for seed in [3, 11, 29] {
            var e = try ChainsTests.engine(seed: seed)
            let b = try XCTUnwrap(brands(e, tier: 3).first)
            let id = franchisee(&e, b)
            let share = FranchiseStandards.requiredShare(try XCTUnwrap(e.state.company(id)))
            XCTAssertGreaterThan(share, 0)
            let rev = 1_000_000.0
            func paid(spend: Double) -> Double {
                var s = e.state
                let i = s.companyIndex(id)!
                s.companies[i].cash = 1e12
                var mkt = s.companies[i].value("mkt")
                if spend > 0 { mkt["flyer"] = .object(["b": .number(spend)]) }
                s.companies[i].set("mkt", mkt)
                let before = s.companies[i].cash
                Franchising.franchiseeWeek(&s, i, rev: rev, context: FinanceContext(countries: e.data.countries, trades: e.data.catalog))
                return before - s.companies[i].cash
            }
            let f = try XCTUnwrap(e.state.company(id)).value("franchise")
            let base = rev * (f["roy"].double + f["mkt"].double)
            XCTAssertEqual(paid(spend: 0), base + rev * share, accuracy: 1, "nothing spent locally: the whole requirement goes to the fund")
            XCTAssertEqual(paid(spend: rev * share / 2), base + rev * share / 2, accuracy: 1, "half spent: the rest goes to the fund")
            XCTAssertEqual(paid(spend: rev * share * 2), base, accuracy: 1, "requirement met: nothing extra")
            ChainsTests.play(&e, days: 7 * 8)
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        }
    }

    func testManagersDoNotBreakTheAgreement() throws {
        var e = try ChainsTests.engine()
        let b4 = try XCTUnwrap(brands(e, tier: 4).first)
        let id = franchisee(&e, b4)
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertNotNil(FranchiseStandards.campaignRefusal(co, channel: "google"))
        XCTAssertNotNil(FranchiseStandards.campaignRefusal(co, channel: "meta"))
        XCTAssertFalse(e.state.company(id)!.value("mkt").object.keys.contains("google"))
    }
}
