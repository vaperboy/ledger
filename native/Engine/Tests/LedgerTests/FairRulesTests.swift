import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Investments
@testable import Simulation

final class FairRulesTests: XCTestCase {
    func fresh() throws -> GameEngine {
        try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7, story: .fresh, tradeID: "cafe", companyName: "Test Co", chooseFirstItem: true)
    }

    func testANewGameWritesNoModeAndAnOldModeIsIgnored() throws {
        let e = try fresh()
        XCTAssertNil(e.state.rest["difficulty"])
        let fy = e.data.balance.firstYear
        XCTAssertFalse(fy.bankruptcyActive(week: 26))
        XCTAssertTrue(fy.bankruptcyActive(week: 27))
        for old in ["sandbox", "hard", "classic"] {
            var s = e.state
            s.rest["difficulty"] = .string(old)
            s.rest["difficultyLocked"] = .number(1)
            let back = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(s))
            var loaded = GameEngine(state: back, data: e.data, events: e.events, marketing: e.marketing)
            for _ in 0..<14 { _ = loaded.nextDay() }
            XCTAssertGreaterThanOrEqual(loaded.state.week, 1, old)
            XCTAssertTrue(Ledger.gaps(loaded.state).isEmpty, "\(old): \(Ledger.gaps(loaded.state))")
        }
    }

    func testOneEventRampAndOneEarlyCap() throws {
        let b = try Balance.bundled()
        for w in [1, 3, 13, 60] { XCTAssertEqual(FairRules.eventRamp(b, week: w), b.eventRampMultiplier(week: w)) }
        XCTAssertEqual(FairRules.badEventCapWeeks, 12)
        XCTAssertEqual(FairRules.threatScale, 1)
        XCTAssertEqual(FairRules.rivalSharpness, 1)
    }

    func testMarketDownturnsAreWarnedAhead() throws {
        var s = try fresh().state
        var lastWarn = -99
        var bad = 0
        for _ in 0..<600 {
            let before = s.rest["mkt"]?["regime"].string ?? ""
            s.week += 1
            Markets.weekly(&s)
            for n in s.rest["news"]?.array ?? [] where n["t"].string.hasPrefix("MARKET WARNING") { lastWarn = max(lastWarn, n["w"].int) }
            let after = s.rest["mkt"]?["regime"].string ?? ""
            if after != before, after == "crash" || after == "bear" {
                bad += 1
                XCTAssertTrue((1...3).contains(s.week - lastWarn), "\(after) at week \(s.week), last warning week \(lastWarn)")
            }
        }
        XCTAssertGreaterThan(bad, 0)
    }

    func testBidChanceScalesWithRankAndWealthAndStaysCapped() {
        let c = Threat.bidChance
        XCTAssertGreaterThan(c(1, 0.8), c(2, 0.8))
        XCTAssertEqual(c(3, 1), 0)
        XCTAssertGreaterThan(c(1, 1), c(1, 0))
        XCTAssertLessThanOrEqual(c(1, 1), 0.06)
    }

    func testComplaintDebtAndLateWagesWearReputationButCarefulPlayIsUntouched() throws {
        var careful = try fresh().state, late = careful
        let rep0 = careful.companies[0].reputation
        late.companies[0].wageShortfall = 1
        for _ in 0..<10 {
            careful.week += 1; late.week += 1
            Threat.reputationDebt(&careful)
            Threat.reputationDebt(&late)
        }
        XCTAssertEqual(careful.companies[0].reputation, rep0, accuracy: 1e-9)
        XCTAssertLessThan(late.companies[0].reputation, rep0)
        XCTAssertGreaterThan(late.companies[0].reputation, rep0 - 5, "a slow wear, not a collapse")
    }

    func testCreditorDriftIsSlowAndFloored() throws {
        func run(weeks: Int) throws -> Double {
            let e = try fresh()
            var s = e.state
            let big = s.rest["group"]?["big"].double ?? 0
            XCTAssertGreaterThan(big, 0)
            s.netWorthHistory = [big * 8]
            s.credit = 70
            for w in 0..<weeks { s.week = w + 1; CreditorPressure.weekly(&s, data: e.data) }
            return s.credit
        }
        let eight = try run(weeks: 8)
        XCTAssertLessThan(eight, 70)
        XCTAssertGreaterThan(eight, 68, "one week is a small step")
        XCTAssertGreaterThanOrEqual(try run(weeks: 2000), CreditorPressure.floor)
    }
}
