import XCTest
import GameCore
import Finance
import Businesses
import Simulation

/// The reads behind the Company screens batch: standing words, the market-analyst gate for the share graph, development named for the
/// trade, and the review data the Reviews app shows (your own and the rivals').
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
            if case .success(let id) = e.startCompany(tradeID: t, cityID: e.state.player.cityID, form: .limited, fundWith: 40_000_000) { ids[t] = id }
        }
        return (e, ids)
    }

    func testDevelopmentIsNamedForTheTradeAndHiddenWhereGeneric() throws {
        let (e, ids) = try engineWith(["cafe", "bakery", "webshop", "tutor", "construction"])
        let expectNoun: [String: String] = ["cafe": "menu item", "bakery": "bake", "webshop": "product range", "tutor": "course"]
        for (trade, noun) in expectNoun {
            guard let id = ids[trade], let co = e.state.company(id) else { continue }
            XCTAssertTrue(Development.isSpecific(co, data: e.data), trade)
            XCTAssertEqual(Development.noun(for: co, data: e.data), noun, trade)
            XCTAssertFalse(e.developmentProjects(companyID: id).isEmpty, trade)
        }
        XCTAssertFalse(ids.isEmpty, "at least one trade could be started")
        if let id = ids["construction"], let co = e.state.company(id) {
            XCTAssertFalse(Development.isSpecific(co, data: e.data), "project businesses only have generic projects")
            XCTAssertNil(Development.noun(for: co, data: e.data))
        }
    }

    func testEveryTradeFamilyIsEitherNamedOrHidden() throws {
        let e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 11)
        for (id, bd) in e.data.catalog.trades {
            let co = Company(raw: ["id": .number(1), "type": .string(id)])
            let specific = Development.isSpecific(co, data: e.data)
            XCTAssertEqual(specific, Development.specificFamilies.contains(bd.family), id)
            XCTAssertEqual(Development.noun(for: co, data: e.data) != nil, specific, id)
        }
    }

    func testReviewReadsForOwnAndRivals() throws {
        var (e, ids) = try engineWith(["cafe"])
        guard let id = ids["cafe"] else { return XCTFail("start") }
        for _ in 0..<(7 * 12) { e.nextDay() }
        let co = e.state.company(id)!
        let own = e.reviewSummary(co, limit: max(1, co.value("rv41").array.count))
        XCTAssertEqual(own.count, Reviews.count(co))
        XCTAssertEqual(own.histogram.reduce(0, +), co.value("rv41").array.count)
        XCTAssertTrue(own.lines.allSatisfy { (1...5).contains($0.stars) })
        let groups = e.reviewBoard()
        let mine = groups.first { $0.rows.contains { $0.companyID == id } }
        XCTAssertNotNil(mine, "the review board has a group for the company's market")
        let rivalRows = (mine?.rows ?? []).filter { !$0.mine }
        for r in rivalRows {
            guard let rid = r.rivalID, let d = e.rivalDetail(companyID: id, rivalID: rid) else { XCTFail("rival detail"); continue }
            XCTAssertEqual(d.reviewRating, r.rating, accuracy: 1e-9, "the board and the rival's sheet show the same rating")
            XCTAssertEqual(d.reviewCount, r.count)
            XCTAssertLessThanOrEqual(d.reviews.count, 5)
            XCTAssertTrue(d.reviews.allSatisfy { (1...5).contains($0.stars) })
        }
    }

    func testEverySwitchableWayToSellStatesItsCost() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 11)
        e.update { s, _, _ in Ledger.move(&s, .me, 900_000_000, why: "Test funds") }
        var checked = 0
        for trade in e.data.balance.salesWays.keys.sorted() {
            guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, form: .limited, fundWith: 20_000_000) else { continue }
            for row in e.waysToSell(companyID: id) where row.canSwitch {
                XCTAssertFalse(row.cost.isEmpty, "\(trade) / \(row.kind) shows its cost")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0)
    }
}
