import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

/// Goal rewards wait as completed and unclaimed; claiming pays through the ledger, once. The player level keeps its points in the save.
final class GoalClaimsTests: XCTestCase {
    private func game() throws -> GameEngine {
        try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7, story: .fresh, tradeID: "cafe", companyName: "Test")
    }

    func testLadderGoalWaitsThenPaysOnceWithBalancedBooks() throws {
        var e = try game()
        let cur = e.homeCurrency
        e.update { s, _, _ in
            s.rest["ldr"] = .object(["done": .object([:])])
            s.rest["reports"] = .object([ReportKind.week.storeKey: .array([.object([:])])])
            XCTAssertEqual(PlayerGoals.ladderSweep(&s, currency: cur), ["M1"])
        }
        XCTAssertEqual(PlayerGoals.ladder(e.state)?.first { $0.id == "M1" }?.unclaimed, true)
        XCTAssertTrue(Gates.goalDone(e.state, 1), "finishing still counts for the gates")
        XCTAssertTrue(e.claimableGoals().contains { $0.kind == .ladder && $0.goalID == "M1" })
        let credit = e.state.credit, cash = e.state.cash
        let flowBefore = e.state.cashFlow["me", default: 0]
        guard case .claimed(_, _, let paid) = e.claimGoal(kind: .ladder, id: "M1") else { return XCTFail("claim failed") }
        XCTAssertEqual(paid, jsRound(cur.scaledPrice(500)))
        XCTAssertEqual(e.state.cash, cash + paid, accuracy: 0.001)
        XCTAssertEqual(e.state.cashFlow["me", default: 0] - flowBefore, paid, accuracy: 0.001, "the payment is booked")
        XCTAssertEqual(e.state.statement.first?.label, GoalClaims.rewardLabel("Get through your first week"))
        XCTAssertGreaterThan(e.state.credit, credit)
        XCTAssertEqual(e.claimGoal(kind: .ladder, id: "M1"), .notReady, "once only")
        XCTAssertFalse(e.claimableGoals().contains { $0.goalID == "M1" })
    }

    func testCareerGoalAndDailyGoalClaims() throws {
        var e = try game()
        e.update { s, _, _ in s.rest["miles"] = .object(["s": 3]) }
        e.sweepCareer()
        XCTAssertEqual(e.careerGoals.first { $0.id == "k1" }?.unclaimed, true)
        XCTAssertEqual(e.claimGoal(kind: .career, id: "k2"), .notReady, "an unfinished goal cannot be claimed")
        let cash = e.state.cash
        guard case .claimed = e.claimGoal(kind: .career, id: "k1") else { return XCTFail("claim failed") }
        XCTAssertGreaterThan(e.state.cash, cash)
        XCTAssertEqual(e.careerGoals.first { $0.id == "k1" }?.unclaimed, false)

        let now = Date()
        XCTAssertEqual(e.claimGoal(kind: .daily, id: "x", now: now), .notReady, "no daily goal is done yet")
        let today = GameEngine.dayString(now)
        e.update { s, _, _ in
            s.rest["dy59"] = .object(["d": .string(today), "k": .string("grow"), "got": .number(1), "streak": .number(1), "last": .string(today)])
        }
        let before = e.state.cash
        guard case .claimed = e.claimGoal(kind: .daily, id: "grow", now: now) else { return XCTFail("daily claim failed") }
        XCTAssertGreaterThan(e.state.cash, before)
        XCTAssertEqual(e.claimGoal(kind: .daily, id: "grow", now: now), .notReady)
    }

    func testLevelMathAndPersistence() throws {
        XCTAssertEqual(PlayerLevel.level(forXP: 0), 1)
        XCTAssertEqual(PlayerLevel.level(forXP: 49), 1)
        XCTAssertEqual(PlayerLevel.level(forXP: 50), 2)
        XCTAssertEqual(PlayerLevel.level(forXP: 150), 3)
        XCTAssertEqual(PlayerLevel.level(forXP: 500), 5)
        var e = try game()
        XCTAssertEqual(e.playerLevel.level, 1)
        e.update { s, _, _ in PlayerLevel.award(&s, 80) }
        let info = e.playerLevel
        XCTAssertEqual(info.level, 2)
        XCTAssertEqual(info.xpIntoLevel, 30)
        XCTAssertEqual(info.xpForNext, 100)
        XCTAssertEqual(info.progress, 0.3, accuracy: 1e-9)
        XCTAssertTrue(e.pendingCelebrations.contains { $0.title == "Level 2" })
        let back = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(e.state))
        XCTAssertEqual(PlayerLevel.info(back), info)
    }

    func testRemovedDailyGoalsNeverReturn() {
        XCTAssertFalse(PlayerGoals.dailyDefs.contains { $0.title.lowercased().contains("payroll") || $0.link == "accounting" })
    }
}
