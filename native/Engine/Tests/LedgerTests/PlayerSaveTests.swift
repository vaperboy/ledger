import XCTest
import GameCore
@testable import Businesses
@testable import Simulation

final class PlayerSaveTests: XCTestCase {
    func testPlayersOldSaveLoadsReadsAndPlays() throws {
        let (data, events, marketing) = try GameEngine.loadResources()
        let s = try Golden.state("save_player_old")
        var e = GameEngine(state: s, data: data, events: events, marketing: marketing)
        var lastSeen = e.gameDayNumber
        for day in 0..<35 {
            _ = e.structureTree()
            _ = e.taxEstimate()
            _ = e.playingPanel()
            _ = e.streakInfo()
            _ = e.sinceYouLeft(lastSeenDay: lastSeen)
            _ = e.unlockRoadmap()
            _ = e.dailyDigest(fresh: [])
            _ = e.pendingReportDigest()
            _ = e.groupBooksProfit
            for c in e.state.companies {
                _ = e.managerOrders(companyID: c.id)
                _ = e.staffingPlan(companyID: c.id)
                _ = e.companyWeekCompare(companyID: c.id)
                _ = e.equipmentRelevance(companyID: c.id)
            }
            for days in [7, 30, 90] { XCTAssertTrue(e.netWorthSeries(days: days).allSatisfy { $0.isFinite }, "day \(day)") }
            XCTAssertTrue(e.netWorth.total.isFinite, "day \(day)")
            e.nextDay()
            e.markSeen()
            lastSeen = e.gameDayNumber
        }
    }
}
