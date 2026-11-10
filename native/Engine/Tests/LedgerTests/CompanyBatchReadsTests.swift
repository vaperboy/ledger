import XCTest
import GameCore
import Finance
import Businesses
import Simulation

final class CompanyBatchReadsTests: XCTestCase {
    func testAwarenessWordsFollowTheThresholds() {
        XCTAssertEqual(StandingWords.awareness(0), "Unknown")
        XCTAssertEqual(StandingWords.awareness(11.9), "Unknown")
        XCTAssertEqual(StandingWords.awareness(12), "Few know you")
        XCTAssertEqual(StandingWords.awareness(25), "Few know you")
        XCTAssertEqual(StandingWords.awareness(30), "Known locally")
        XCTAssertEqual(StandingWords.awareness(54.9), "Known locally")
        XCTAssertEqual(StandingWords.awareness(55), "Well known")
        XCTAssertEqual(StandingWords.awareness(77.9), "Well known")
        XCTAssertEqual(StandingWords.awareness(78), "Famous")
        XCTAssertEqual(StandingWords.awareness(100), "Famous")
    }

    func testReputationWordsFollowTheThresholds() {
        XCTAssertEqual(StandingWords.reputation(0), "Poor")
        XCTAssertEqual(StandingWords.reputation(24.9), "Poor")
        XCTAssertEqual(StandingWords.reputation(45), "Fair")
        XCTAssertEqual(StandingWords.reputation(50), "Good")
        XCTAssertEqual(StandingWords.reputation(69.9), "Good")
        XCTAssertEqual(StandingWords.reputation(70), "Very good")
        XCTAssertEqual(StandingWords.reputation(85), "Excellent")
        XCTAssertEqual(StandingWords.reputation(100), "Excellent")
    }

    func testStarsOutOfFive() {
        XCTAssertEqual(StandingWords.starGlyphs(4.2), "\u{2605}\u{2605}\u{2605}\u{2605}\u{2606}")
        XCTAssertEqual(StandingWords.starGlyphs(4.6), "\u{2605}\u{2605}\u{2605}\u{2605}\u{2605}")
        XCTAssertEqual(StandingWords.starGlyphs(0.2), "\u{2606}\u{2606}\u{2606}\u{2606}\u{2606}")
        XCTAssertEqual(StandingWords.starGlyphs(9), "\u{2605}\u{2605}\u{2605}\u{2605}\u{2605}")
        XCTAssertEqual(StandingWords.ratingText(4.2), "\u{2605}\u{2605}\u{2605}\u{2605}\u{2606} 4.2 / 5")
    }

    func testShareGraphNeedsAnAnalyst() {
        XCTAssertFalse(MarketMap.Knowledge.Level.feeling.canDrawShareGraph)
        XCTAssertTrue(MarketMap.Knowledge.Level.dataAnalyst.canDrawShareGraph)
        XCTAssertTrue(MarketMap.Knowledge.Level.marketAnalyst.canDrawShareGraph)
        XCTAssertFalse(MarketMap.Knowledge.nobody.level.canDrawShareGraph, "with nobody measuring, a guess is wording only")
    }

    private func engineWith(_ trades: [String]) throws -> (GameEngine, [String: Int]) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 11)
        e.update { s, _, _ in Ledger.move(&s, .me, 900_000_000, why: "Test funds") }
        var ids: [String: Int] = [:]
        for t in trades {
            if case .success(let id) = e.startCompany(tradeID: t, cityID: e.state.player.cityID) { ids[t] = id }
        }
        return (e, ids)
    }

    func testEverySwitchableWayToSellStatesItsCost() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 11)
        e.update { s, _, _ in Ledger.move(&s, .me, 900_000_000, why: "Test funds") }
        var checked = 0
        for trade in e.data.balance.salesWays.keys.sorted() {
            guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID) else { continue }
            for row in e.waysToSell(companyID: id) where row.canSwitch {
                XCTAssertFalse(row.cost.isEmpty, "\(trade) / \(row.kind) shows its cost")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0)
    }
}
