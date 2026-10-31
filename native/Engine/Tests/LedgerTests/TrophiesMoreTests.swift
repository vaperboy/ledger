import XCTest
@testable import Events
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The extra trophies (acquisitions, gifts, luxury, review counts, franchise units) are reached when their system is used,
/// are kept in the same record, and the books still balance.
final class TrophiesMoreTests: XCTestCase {
    func testAcquisitionGiftAndLuxuryTrophies() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 4242)
        let ids = Set(Trophies.all.map { $0.id })
        for id in ["acq", "give", "g10", "stars", "st48", "rd", "ten10", "mgr10", "hq5", "abr50", "lx1", "lxj", "lxi", "ch3", "fr1", "fr100", "tyall"] {
            XCTAssertTrue(ids.contains(id), id)
        }
        XCTAssertEqual(ids.count, Trophies.all.count, "trophy ids are unique")
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 500_000_000, why: "Test funds")
            Ambitions.countEvent(&s, "buy")
            _ = Luxury.buy(&s, itemID: "e2")
            Trophies.check(&s, data: data, context: ctx)
            Trophies.check(&s, data: data, context: ctx)
        }
        let reached = Set(Trophies.entries(e.state).filter { $0.reachedWeek != nil }.map { $0.id })
        XCTAssertTrue(reached.contains("acq"))
        XCTAssertTrue(reached.contains("lx1"))
        XCTAssertTrue(reached.contains("lxi"))
        XCTAssertFalse(reached.contains("fr1"))
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testMarketRankAndTeamTrophiesExistAndDepositShareReadsMarket() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 4242)
        let ids = Set(Trophies.all.map { $0.id })
        for id in ["no1", "top10", "team56", "n13", "n110", "rk50", "rk3", "rk1"] { XCTAssertTrue(ids.contains(id), id) }
        XCTAssertEqual(Ambitions.marketsLed(e.state, e.data).count, 0)
        let f3a = Ambitions.milestones(e.state, e.data, path: "financier", tier: 2).first { $0.id == "f3a" }
        XCTAssertEqual(f3a?.now, 0)
        e.update { s, data, ctx in Trophies.check(&s, data: data, context: ctx) }
        XCTAssertFalse(Trophies.entries(e.state).contains { $0.id == "team56" && $0.reachedWeek != nil })
    }
}
