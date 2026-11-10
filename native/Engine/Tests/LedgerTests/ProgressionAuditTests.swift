import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Simulation

final class ProgressionAuditTests: XCTestCase {
    private func fresh() throws -> GameEngine { try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 5) }

    private func vis(_ e: GameEngine, _ g: Gate) -> GateVisibility { Gates.visibility(g, e.state, data: e.data) }

    private static let goalGates: [Gate] = [.marketing, .reviews, .bank, .newCompany, .management, .accounting, .techpro, .group, .property, .rivals, .airstay]

    func testEveryMenuOpensWithTimeAloneForAPlayerWhoNeverMeetsItsGoal() throws {
        var e = try fresh()
        e.update { s, _, _ in s.week = 17 }
        for g in Self.goalGates { XCTAssertEqual(vis(e, g), .open, g.rawValue) }
    }

    func testTheFallbackWeeksOpenTheMenusInOrder() throws {
        var e = try fresh()
        e.update { s, _, _ in s.week = 5 }
        XCTAssertNotEqual(vis(e, .marketing), .open)
        e.update { s, _, _ in s.week = 6 }
        XCTAssertEqual(vis(e, .marketing), .open)
        e.update { s, _, _ in s.week = 8 }
        for g in [Gate.bank, .accounting] { XCTAssertEqual(vis(e, g), .open, g.rawValue) }
        XCTAssertNotEqual(vis(e, .group), .open)
        e.update { s, _, _ in s.week = 13 }
        for g in [Gate.group, .management, .newCompany, .techpro] { XCTAssertEqual(vis(e, g), .open, g.rawValue) }
        XCTAssertNotEqual(vis(e, .property), .open)
        e.update { s, _, _ in s.week = 17 }
        for g in [Gate.property, .rivals, .airstay] { XCTAssertEqual(vis(e, g), .open, g.rawValue) }
    }

    func testTheFirstStepsEndByWeekThirteenWithoutAProfitableMonth() throws {
        var e = try fresh()
        e.update { s, _, _ in s.week = Unlocks.weeksLadderPast - 1 }
        XCTAssertFalse(Unlocks.ladderPast(e.state))
        e.update { s, _, _ in s.week = Unlocks.weeksLadderPast }
        XCTAssertTrue(Unlocks.ladderPast(e.state))
    }

    func testAnOptionalGoalNobodyReachesIsSkippedAfterTwelveWeeksAndPaysNothing() throws {
        var e = try fresh()
        let cur = e.homeCurrency
        e.update { s, _, _ in
            s.week = 0
            s.rest["ldr"] = .object(["done": .object(["M1": .object(["w": .number(0), "u": .number(0)]), "M2": .object(["w": .number(0), "u": .number(0)])])])
            s.week = PlayerGoals.staleWeeks - 1
            XCTAssertEqual(PlayerGoals.ladderSweep(&s, currency: cur), [])
        }
        XCTAssertFalse(Gates.goalDone(e.state, 3))
        e.update { s, _, _ in
            s.week = PlayerGoals.staleWeeks
            XCTAssertEqual(PlayerGoals.ladderSweep(&s, currency: cur), [])
        }
        XCTAssertTrue(Gates.goalDone(e.state, 3))
        XCTAssertEqual(e.state.rest["ldr"]?["done"]["M3"]["u"].int, 0)
        XCTAssertEqual(PlayerGoals.currentLadderGoal(e.state)?.id, "M4")
        XCTAssertNil(PlayerGoals.ladderPastTense(e.state, firstWeek: PlayerGoals.staleWeeks, lastWeek: PlayerGoals.staleWeeks))
    }

    func testTheCoreGoalsNeverSkip() throws {
        for id in ["M1", "M2", "M7", "M9", "M10"] { XCTAssertFalse(PlayerGoals.skippableGoals.contains(id), id) }
    }

    func testLevelThresholdsGrowSmoothly() {
        XCTAssertEqual((1...6).map { PlayerLevel.threshold($0) }, [0, 50, 150, 300, 500, 750])
        for l in 2...12 {
            XCTAssertGreaterThan(PlayerLevel.threshold(l), PlayerLevel.threshold(l - 1))
            XCTAssertGreaterThanOrEqual(PlayerLevel.threshold(l + 1) - PlayerLevel.threshold(l), PlayerLevel.threshold(l) - PlayerLevel.threshold(l - 1))
        }
    }

    func testACasualPlayerReachesLevelFiveWithinAFewSessions() throws {
        var s = try fresh().state
        var sessions = 0
        var firstLevelTwo: Int? = nil
        while PlayerLevel.info(s).level < 5 && sessions < 30 {
            sessions += 1
            if sessions <= 10 { PlayerLevel.award(&s, PlayerLevel.ladderXP) }
            PlayerLevel.award(&s, PlayerLevel.dailyXP)
            PlayerLevel.award(&s, PlayerLevel.weekXP)
            if firstLevelTwo == nil && PlayerLevel.info(s).level >= 2 { firstLevelTwo = sessions }
        }
        XCTAssertEqual(firstLevelTwo, 1)
        XCTAssertLessThanOrEqual(sessions, 6)
    }

    func testAPlayerWhoOnlyOpensTheDailyGoalStillGetsThereWithinAMonth() throws {
        var s = try fresh().state
        var days = 0
        while PlayerLevel.info(s).level < 5 && days < 400 {
            days += 1
            PlayerLevel.award(&s, PlayerLevel.dailyXP)
            if days % 7 == 0 { PlayerLevel.award(&s, PlayerLevel.weekXP) }
        }
        XCTAssertLessThanOrEqual(days, 30)
    }

    func testEveryDepthFeatureIsWithinReachOfADailyPlayerInAFewMonths() {
        for f in LevelFeature.allCases {
            let need: Int = PlayerLevel.threshold(LevelGates.level(f))
            let days: Int = Int((Double(need) / Double(PlayerLevel.dailyXP + PlayerLevel.weekXP / 7)).rounded(.up))
            XCTAssertLessThanOrEqual(days, 40, f.rawValue)
        }
    }

    func testTheStreakDoesNotRevealWhatTheNextMilestoneGives() throws {
        let e = try fresh()
        let info = PlayerGoals.streakInfo(e.state)
        XCTAssertNotNil(info.nextMilestone)
        XCTAssertEqual(info.nextPerk, "")
    }
}
