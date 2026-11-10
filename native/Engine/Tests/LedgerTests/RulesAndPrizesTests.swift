import XCTest
import GameCore
import Finance
import Businesses
@testable import Simulation

final class RulesAndPrizesTests: XCTestCase {
    private func game() throws -> GameEngine {
        try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7, story: .fresh, tradeID: "cafe", companyName: "Test")
    }

    func testBoxMoneyIsRareCappedAndDisclosed() {
        for kind in BoxKind.standard {
            XCTAssertGreaterThan(BoxOdds.largestMoney(kind), 0, "\(kind)")
            XCTAssertLessThanOrEqual(BoxOdds.largestMoney(kind), BoxOdds.moneyCap)
            XCTAssertTrue(BoxOdds.isFair(kind))
            XCTAssertTrue(BoxOdds.disclosure(kind).contains { $0.title.contains("cash prize") }, "the odds list the cash prizes")
        }
        for kind in BoxKind.allCases where kind.isPaid {
            for row in BoxOdds.rows(kind) { if case .money = row.prize { XCTAssertGreaterThanOrEqual(row.rarity, .rare) } }
        }
    }

    func testBoxMoneyPaysOnceAndBalances() throws {
        var e = try game()
        let before = e.state.cash
        let paid = e.claimBoxMoney(1_000, claimID: "open-1")
        XCTAssertNotNil(paid)
        XCTAssertNil(e.claimBoxMoney(1_000, claimID: "open-1"), "the same opening pays once")
        XCTAssertNil(e.claimBoxMoney(BoxOdds.moneyCap + 1, claimID: "open-2"), "above the cap is refused")
        XCTAssertGreaterThan(e.state.cash, before)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testAuctionCashMovesThroughTheLedgerOncePerSettlement() throws {
        var e = try game()
        let rate = e.homeCurrency.rate
        let before = e.state.cash
        XCTAssertEqual(e.auctionCash, Int((before / rate).rounded(.down)))
        XCTAssertGreaterThan(e.auctionPriceLevel, 0)
        XCTAssertNotNil(e.settleAuctionCash(500, claimID: "A1|sold", label: "Auction"))
        XCTAssertNil(e.settleAuctionCash(500, claimID: "A1|sold", label: "Auction"), "the same settlement pays once")
        XCTAssertEqual(e.state.cash, before + 500 * rate, accuracy: 1)
        XCTAssertNotNil(e.settleAuctionCash(-200, claimID: "A2|won", label: "Auction"))
        XCTAssertEqual(e.state.cash, before + 300 * rate, accuracy: 1)
        XCTAssertNil(e.settleAuctionCash(0, claimID: "A3", label: "Auction"))
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testStartupGateNeedsAgeAndLevel() {
        XCTAssertFalse(CrowdStartupRules.foundGate(accountWeeks: 0, level: 5).allowed)
        XCTAssertFalse(CrowdStartupRules.foundGate(accountWeeks: 50, level: 1).allowed)
        let ok = CrowdStartupRules.foundGate(accountWeeks: 50, level: CrowdStartupRules.minFounderLevel)
        XCTAssertTrue(ok.allowed)
        XCTAssertTrue(ok.reasons.isEmpty)
        XCTAssertTrue(ok.lines.contains { $0.hasPrefix("If you open it") })
    }

    func testLinkedAccountCannotBidOnItsOwnSale() throws {
        var a = Auction(id: "A1", item: ArtifactItem(defID: "abacus", serial: 1), seller: "s", startPrice: 100, reserve: nil,
                        startsAt: 0, endsAt: 3_600, duration: .oneHour)
        a.bids = []
        var b = AuctionBook(me: "me")
        b.auctions.append(a)
        b.linkKeys = ["me": "grp", "s": "grp"]
        XCTAssertThrowsError(try b.place("A1", bidder: "me", amount: 100, now: 10, cash: 1_000))
        XCTAssertEqual(b.held, 0)
    }

    func testPenaltyConstantsArePublic() {
        XCTAssertGreaterThan(DirtyTrick.fineMultiple, 1)
        XCTAssertGreaterThan(DirtyTrick.banWeeks, 0)
        XCTAssertGreaterThan(DirtyTrick.traceChance, 0)
        XCTAssertLessThan(DirtyTrick.traceChance, 1)
        XCTAssertGreaterThan(RouteRules.tradeBanWeeks(grave: true), RouteRules.tradeBanWeeks(grave: false))
    }

    func testGovernmentIsCreatedAtGameStartWithAdmins() throws {
        let e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7, story: .fresh, tradeID: "cafe", companyName: "Test", admins: ["boss"])
        XCTAssertNotNil(e.state.rest["gov"])
    }

    func testWorldRulesDefaultsClampAndIgnoreUnknown() {
        XCTAssertEqual(WorldRules().printSingleLimit, WorldRules.defaults.printSingleLimit)
        let r = WorldRules(snapshot: ["nonsense": 5, "print.single_limit": -1e12])
        XCTAssertEqual(r.printSingleLimit, WorldRules.limits["print.single_limit"]?.min)
        XCTAssertNil(WorldRules.limits["nonsense"])
    }

    func testEngineReadsAnAdminSnapshot() throws {
        var e = try game()
        XCTAssertEqual(e.state.worldRules, WorldRules.defaults)
        e.applyWorldRules(snapshot: ["band.exchange_low": 0.9])
        XCTAssertNotEqual(e.state.worldRules, WorldRules.defaults)
        XCTAssertEqual(e.state.worldRules.exchangeBand.lowerBound, 0.9, accuracy: 0.0001)
    }

    func testPreviewsLeaveTheGameAlone() throws {
        let e = try game()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let saved = try? encoder.encode(e.state)
        _ = e.previewOrder(instrument: "none", side: .buy, shares: 1, limit: 1)
        XCTAssertEqual(saved, try? encoder.encode(e.state))
    }

    func testLeaderboardInitialisersAreUsable() {
        let s = LeaderboardSubmission(playerID: "p", name: "N", week: 3, netWorth: 10, tradingResult: 1)
        XCTAssertEqual(s.name, "N")
        let en = LeaderboardEntry(id: "p", rank: 1, name: "N", value: 10, isYou: true)
        XCTAssertTrue(en.isYou)
    }
}
