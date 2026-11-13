import XCTest
import GameCore
import Businesses
@testable import Simulation

final class PassPacingTests: XCTestCase {
    private let start = 21_000

    private struct Player {
        var advances: Int
        var decisions: Int
        var events: Int
    }

    private func daysToFinish(_ who: Player, limit: Int = SeasonPass.seasonDays, afterDays: Int? = nil) -> (days: Int?, xp: Int) {
        var p = SeasonPass(today: start)
        var advanced = 0, decisions = 0, events = 0, answered = 0
        func snap(_ day: Int) -> SeasonPass.Snapshot {
            SeasonPass.Snapshot(seed: 1, week: 1 + advanced / 7, cash: 100, profitMonths: 0, loans: 0, goals: 0, dailyDone: "day\(day)",
                                counters: ["advance": advanced, "decision": decisions, "event": events, "answered": answered])
        }
        p.observe(SeasonPass.Snapshot(seed: 1, week: 1, cash: 100, profitMonths: 0, loans: 0, goals: 0, dailyDone: "", counters: [:]), today: start)
        for d in 0..<limit {
            advanced += who.advances; decisions += who.decisions; events += who.events; answered += who.decisions + who.events
            p.observe(snap(d), today: start + d)
            if p.isComplete { return (d + 1, p.xp) }
            if let a = afterDays, d + 1 == a { return (nil, p.xp) }
        }
        return (nil, p.xp)
    }

    func testADedicatedPlayerFinishesInAboutNinetyDays() {
        let r = daysToFinish(Player(advances: 3, decisions: 2, events: 2))
        let days: Int = r.days ?? 999
        XCTAssertGreaterThanOrEqual(days, 85)
        XCTAssertLessThanOrEqual(days, 100)
    }

    func testAMaxEffortPlayerCannotFinishBeforeAboutThirtyDays() {
        let r = daysToFinish(Player(advances: 12, decisions: 12, events: 12))
        XCTAssertGreaterThanOrEqual(r.days ?? 999, 30)
        XCTAssertNotNil(r.days, "they still finish inside the season")
    }

    func testNobodyFinishesInAWeek() {
        let r = daysToFinish(Player(advances: 40, decisions: 40, events: 40), limit: 7)
        XCTAssertNil(r.days)
        XCTAssertLessThan(r.xp, SeasonPass.tierCount * SeasonPass.xpPerTier / 4)
    }

    func testAPlayerWhoOnlyLogsInStaysFarFromTheEnd() {
        let r = daysToFinish(Player(advances: 0, decisions: 0, events: 0))
        XCTAssertNil(r.days)
        XCTAssertGreaterThan(r.xp, 0)
    }

    func testMissionsPayOncePerPeriodAndResetWithTheDay() {
        var p = SeasonPass(today: start)
        p.observe(SeasonPass.Snapshot(seed: 1, week: 1, cash: 100, profitMonths: 0, loans: 0, goals: 0, dailyDone: "", counters: [:]), today: start)
        let two = SeasonPass.Snapshot(seed: 1, week: 1, cash: 100, profitMonths: 0, loans: 0, goals: 0, dailyDone: "", counters: ["decision": 2, "answered": 2])
        p.observe(two, today: start)
        XCTAssertEqual(p.missionRows(.day, today: start).first { $0.mission.id == "d.decision" }?.done, true)
        XCTAssertEqual(p.missionRows(.week, today: start).first { $0.mission.id == "w.decision" }?.progress, 2)
        p.observe(two, today: start + 1)
        XCTAssertEqual(p.missionRows(.day, today: start + 1).first { $0.mission.id == "d.decision" }?.done, false, "a new day starts the daily missions again")
        XCTAssertEqual(p.missionRows(.week, today: start + 1).first { $0.mission.id == "w.decision" }?.progress, 2, "the week keeps counting")
    }

    func testFreeTrackRewardsAreRarerThanPremium() {
        for season in [1, 2] {
            // Read on the season's own start day: a season that has not started yet shows nothing.
            let day: Int = SeasonCatalog.startDay(of: season) ?? SeasonCatalog.today()
            let free: [Int] = (1...SeasonPass.tierCount).filter { SeasonRewards.reward(.free, tier: $0, season: season, today: day) != nil }
            let premium: [Int] = (1...SeasonPass.tierCount).filter { SeasonRewards.reward(.premium, tier: $0, season: season, today: day) != nil }
            XCTAssertLessThanOrEqual(free.count, 10, "free every three or four tiers")
            XCTAssertGreaterThanOrEqual(premium.count, 28, "premium nearly every tier")
            for (a, b) in zip(free, free.dropFirst()) { XCTAssertLessThanOrEqual(b - a, 5, "season \(season) free gap \(a) to \(b)") }
        }
    }

    func testTheEngineCountsAnsweredDecisionsAndDays() throws {
        var e = try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 3)
        let before: Int = PassMissions.counters(e.state)["advance"] ?? 0
        _ = e.nextDay()
        XCTAssertEqual(PassMissions.counters(e.state)["advance"], before + 1)
        e.update { s, _, _ in PassMissions.noteAnswer(&s, decision: true); PassMissions.noteAnswer(&s, decision: false) }
        let c: [String: Int] = PassMissions.counters(e.state)
        XCTAssertEqual(c["decision"], 1)
        XCTAssertEqual(c["event"], 1)
        XCTAssertEqual(c["answered"], 2)
    }
}
