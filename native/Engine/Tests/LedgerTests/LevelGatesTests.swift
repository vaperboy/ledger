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
        give(&e, xp: 25)
        XCTAssertFalse(LevelGates.isOpen(.auctions, e.state))
        XCTAssertEqual(LevelGates.progress(.auctions, e.state).xpToGo, PlayerLevel.threshold(2) - 25)
        XCTAssertEqual(LevelGates.progress(.auctions, e.state).fraction, 0.5, accuracy: 0.001)
        give(&e, xp: PlayerLevel.threshold(2))
        XCTAssertTrue(LevelGates.isOpen(.auctions, e.state))
        XCTAssertFalse(LevelGates.isOpen(.exchange, e.state))
        give(&e, xp: PlayerLevel.threshold(7))
        for f in LevelFeature.allCases { XCTAssertTrue(LevelGates.isOpen(f, e.state), f.rawValue) }
        XCTAssertNil(LevelGates.nextLocked(e.state))
    }

    func testChainFranchiseAndAbroadFollowTheirLevelsInOrder() {
        XCTAssertEqual([LevelFeature.chain, .franchise, .abroad].map { LevelGates.level($0) }, [3, 5, 7])
        XCTAssertEqual(LevelGates.title(.chain), "Start a chain")
        XCTAssertEqual(LevelGates.title(.franchise), "Franchise this company")
        XCTAssertGreaterThan(LevelGates.level(.abroad), LevelGates.level(.franchise))
    }

    func testAbroadProgressCountsTowardItsLevel() throws {
        var e = try fresh()
        give(&e, xp: PlayerLevel.threshold(7) / 2)
        XCTAssertFalse(LevelGates.isOpen(.abroad, e.state))
        XCTAssertEqual(LevelGates.progress(.abroad, e.state).fraction, 0.5, accuracy: 0.001)
        give(&e, xp: PlayerLevel.threshold(7))
        XCTAssertTrue(LevelGates.isOpen(.abroad, e.state))
        XCTAssertEqual(LevelGates.progress(.abroad, e.state).xpToGo, 0)
    }

    func testTheProfileKeepsTheHigherLevelAcrossSaves() throws {
        var low = try fresh()
        give(&low, xp: 40)
        var high = try fresh()
        give(&high, xp: PlayerLevel.threshold(5))
        let profile: ProfileProgress = PlayerLevel.profile(of: high.state)
        low.update { s, _, _ in PlayerLevel.adopt(&s, profile: profile) }
        XCTAssertEqual(PlayerLevel.info(low.state).level, 5)
        let back: ProfileProgress = PlayerLevel.profile(of: low.state)
        high.update { s, _, _ in PlayerLevel.adopt(&s, profile: ProfileProgress(xp: 10, seen: nil)) }
        XCTAssertEqual(PlayerLevel.info(high.state).xp, PlayerLevel.threshold(5), "a lower profile never lowers a save")
        XCTAssertEqual(back.merged(with: ProfileProgress(xp: 3, seen: ["level.auctions"])).xp, back.xp)
        XCTAssertEqual(back.merged(with: ProfileProgress(xp: 3, seen: ["level.auctions"])).seen?.contains("level.auctions"), true)
    }

    func testAnUnlockIsAnnouncedOnceAndSavedLevelsStartSeen() throws {
        var e = try fresh()
        XCTAssertTrue(e.pendingNotices().isEmpty)
        e.update { s, _, _ in PlayerLevel.award(&s, PlayerLevel.threshold(3)) }
        let ids: [String] = e.pendingNotices().map { $0.id }
        XCTAssertEqual(ids.first, "level.auctions")
        XCTAssertEqual(Set(ids), ["level.auctions", "level.exchange", "level.chain"])
        e.markNoticeSeen(id: "level.auctions")
        XCTAssertEqual(Set(e.pendingNotices().map { $0.id }), ["level.exchange", "level.chain"])
        var other = try fresh()
        let carried: ProfileProgress = ProfileProgress(xp: PlayerLevel.threshold(3), seen: nil)
        other.update { s, _, _ in PlayerLevel.adopt(&s, profile: carried) }
        XCTAssertTrue(other.pendingNotices().isEmpty, "a level earned elsewhere is not announced again in a new game")
    }

    func testNoticesStayQuietWithoutTheLadder() throws {
        var e = try fresh()
        e.update { s, _, _ in PlayerLevel.award(&s, PlayerLevel.threshold(4)); s.rest["ldr"] = nil }
        XCTAssertTrue(e.pendingNotices().isEmpty)
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
