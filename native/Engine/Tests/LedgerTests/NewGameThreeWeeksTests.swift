import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Simulation

/// A new game with one convenience store, no staff and no manager, played day by day for four weeks, reading what the screens read after
/// every day. The first run of every weekly process, the first held-money release and the first reports must not trap.
final class NewGameThreeWeeksTests: XCTestCase {
    private func play(country: String, cityName: String?) throws {
        let (data, _, _) = try GameEngine.loadResources()
        let cityID: String? = cityName.flatMap { n in data.countries[country]?.cities.first { $0.name == n }?.id }
        var e = try GameEngine.newGame(countryCode: country, playerName: "Tester", cityID: cityID, seed: 11, story: .fresh, tradeID: "kiosk", companyName: "MD Butikk")
        let id = try XCTUnwrap(e.state.companies.first).id
        var lastSeen = e.gameDayNumber
        for day in 0..<28 {
            e.nextDay()
            _ = e.structureTree()
            _ = e.taxEstimate()
            _ = e.managerOrders(companyID: id)
            _ = e.staffingPlan(companyID: id)
            _ = e.playingPanel()
            _ = e.streakInfo()
            _ = e.sinceYouLeft(lastSeenDay: lastSeen)
            _ = e.companyWeekCompare(companyID: id)
            _ = e.unlockRoadmap()
            _ = e.delegationLine(firstWeek: max(0, e.state.week - 1), lastWeek: e.state.week)
            _ = e.dailyDigest(fresh: [])
            _ = e.pendingReportDigest()
            _ = e.groupBooksProfit
            for days in [7, 30, 90] {
                let series = e.netWorthSeries(days: days)
                XCTAssertTrue(series.allSatisfy { $0.isFinite }, "net worth series, day \(day)")
            }
            XCTAssertTrue(e.netWorth.total.isFinite, "net worth, day \(day)")
            XCTAssertTrue(e.state.cash.isFinite, "cash, day \(day)")
            e.markSeen()
            lastSeen = e.gameDayNumber
        }
        XCTAssertEqual(e.state.week, 4)
        XCTAssertEqual(e.state.day, 0)
    }

    func testThreeWeeksOfANewGameDoNotTrap() throws {
        try play(country: "NO", cityName: "Oslo")
        try play(country: "UK", cityName: nil)
    }
}
