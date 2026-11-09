import XCTest
import GameCore
@testable import Businesses
import Simulation

final class LevelGatesTests: XCTestCase {
    private func fresh() throws -> GameEngine { try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 5) }

    private func give(_ e: inout GameEngine, xp: Int) {
        e.update { s, _, _ in s.rest["lvl"] = .object(["xp": .number(Double(xp))]) }
    }

    func testANewPlayerSeesEveryDepthFeatureClosedWithItsLine() throws {
        let e = try fresh()
        for f in LevelFeature.allCases {
            XCTAssertFalse(LevelGates.isOpen(f, e.state), f.rawValue)
            XCTAssertTrue(LevelGates.lockLine(f).hasPrefix("Unlocks at level \(LevelGates.level(f)): "))
        }
        XCTAssertEqual(LevelGates.nextLocked(e.state), .auctions)
    }

    func testAFeatureOpensAtItsLevelAndProgressCountsExperience() throws {
        var e = try fresh()
        give(&e, xp: 50)
        XCTAssertEqual(LevelGates.progress(.auctions, e.state).xpToGo, PlayerLevel.threshold(2) - 50)
        XCTAssertEqual(LevelGates.progress(.auctions, e.state).fraction, 0.5, accuracy: 0.001)
        give(&e, xp: PlayerLevel.threshold(2))
        XCTAssertTrue(LevelGates.isOpen(.auctions, e.state))
        XCTAssertFalse(LevelGates.isOpen(.exchange, e.state))
        give(&e, xp: PlayerLevel.threshold(6))
        for f in LevelFeature.allCases { XCTAssertTrue(LevelGates.isOpen(f, e.state), f.rawValue) }
        XCTAssertNil(LevelGates.nextLocked(e.state))
    }

    func testAnOldSaveWithoutTheLadderIsNeverGated() throws {
        var e = try fresh()
        e.update { s, _, _ in s.rest["ldr"] = nil }
        for f in LevelFeature.allCases { XCTAssertTrue(LevelGates.isOpen(f, e.state), f.rawValue) }
    }

    func testEveryLevelIsReachableWithinTwoYearsOfWeeklyPoints() {
        for f in LevelFeature.allCases {
            XCTAssertLessThanOrEqual(PlayerLevel.threshold(LevelGates.level(f)), 104 * PlayerLevel.weekXP + 10 * PlayerLevel.ladderXP, f.rawValue)
        }
    }
}
