import XCTest
import GameCore
@testable import Businesses
import Simulation

final class LevelGatesTests: XCTestCase {
    private func fresh() throws -> GameEngine { try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 5) }

    private func give(_ e: inout GameEngine, xp: Int) {
        e.update { s, _, _ in
            var v = s.rest["lvl"] ?? .object([:])
            v["xp"] = .number(Double(xp))
            s.rest["lvl"] = v
        }
    }

    func testTheTableOpensExactlyOneFeaturePerLevelInOrder() {
        let levels: [Int] = FeatureUnlocks.table.map { $0.level }
        XCTAssertEqual(levels, Array(2...(1 + FeatureUnlocks.table.count)), "one feature per level, no gaps, from level 2")
        XCTAssertEqual(Set(FeatureUnlocks.table.map { $0.feature }), Set(LevelFeature.allCases), "every feature has one row")
        XCTAssertLessThanOrEqual(FeatureUnlocks.highestLevel, LevelCurve.maxLevel)
        for r in FeatureUnlocks.table {
            XCTAssertFalse(r.title.isEmpty, r.feature.rawValue)
            XCTAssertFalse(r.gives.isEmpty, r.feature.rawValue)
            XCTAssertEqual(LevelGates.unlocks(atLevel: r.level).map { $0.feature }, [r.feature])
        }
    }

    func testANewPlayerHasOnlyTheCoreOpen() throws {
        let e = try fresh()
        for f in LevelFeature.allCases {
            XCTAssertFalse(LevelGates.isOpen(f, e.state), f.rawValue)
            XCTAssertEqual(LevelGates.lockLine(f), "Unlocks at level \(LevelGates.level(f))")
        }
        for g in Gate.allCases where g.feature == nil { XCTAssertTrue(Gates.isOpen(g, e.state, data: e.data), g.rawValue) }
        XCTAssertEqual(FeatureUnlocks.nextUnlock(e.state)?.feature, .marketing)
        XCTAssertEqual(LevelGates.nextLocked(e.state), .marketing)
    }

    func testEachLevelOpensItsFeatureAndNothingAfterIt() throws {
        var e = try fresh()
        for r in FeatureUnlocks.table {
            give(&e, xp: PlayerLevel.threshold(r.level) - 1)
            XCTAssertFalse(FeatureUnlocks.isUnlocked(r.feature, e.state), "\(r.feature) one XP short")
            give(&e, xp: PlayerLevel.threshold(r.level))
            XCTAssertTrue(FeatureUnlocks.isUnlocked(r.feature, e.state), r.feature.rawValue)
            for later in FeatureUnlocks.table where later.level > r.level { XCTAssertFalse(FeatureUnlocks.isUnlocked(later.feature, e.state), later.feature.rawValue) }
        }
        XCTAssertNil(FeatureUnlocks.nextUnlock(e.state))
    }

    func testGatesFollowTheirFeature() throws {
        var e = try fresh()
        XCTAssertFalse(Gates.isOpen(.marketing, e.state, data: e.data))
        XCTAssertFalse(Gates.isOpen(.reviews, e.state, data: e.data))
        XCTAssertEqual(Gates.visibility(.marketing, e.state, data: e.data), .locked("Unlocks at level 2"))
        XCTAssertEqual(Gates.visibility(.luxury, e.state, data: e.data), .hidden, "far-off locks stay out of the way")
        give(&e, xp: PlayerLevel.threshold(2))
        XCTAssertTrue(Gates.isOpen(.marketing, e.state, data: e.data))
        XCTAssertTrue(Gates.isOpen(.reviews, e.state, data: e.data))
        XCTAssertEqual(Gate.atlas.lockText, Gate.insurance.lockText)
        XCTAssertEqual(LevelGates.visibility(.auctions, e.state), .hidden)
        give(&e, xp: PlayerLevel.threshold(LevelGates.level(.auctions) - 2))
        XCTAssertEqual(LevelGates.visibility(.auctions, e.state), .locked("Unlocks at level \(LevelGates.level(.auctions))"))
    }

    func testProgressCountsExperienceTowardTheLevel() throws {
        var e = try fresh()
        give(&e, xp: PlayerLevel.threshold(LevelGates.level(.abroad)) / 2)
        XCTAssertFalse(LevelGates.isOpen(.abroad, e.state))
        XCTAssertEqual(LevelGates.progress(.abroad, e.state).fraction, 0.5, accuracy: 0.001)
        give(&e, xp: PlayerLevel.threshold(LevelGates.level(.abroad)))
        XCTAssertTrue(LevelGates.isOpen(.abroad, e.state))
        XCTAssertEqual(LevelGates.progress(.abroad, e.state).xpToGo, 0)
    }

    func testChainComesBeforeFranchiseAndAbroad() {
        XCTAssertLessThan(LevelGates.level(.chain), LevelGates.level(.franchise))
        XCTAssertLessThan(LevelGates.level(.franchise), LevelGates.level(.abroad))
        XCTAssertLessThan(LevelGates.level(.marketing), LevelGates.level(.management), "the ladder asks for an ad before a manager")
    }

    func testTheProfileKeepsTheHigherLevelAcrossSaves() throws {
        var low = try fresh()
        give(&low, xp: 40)
        var high = try fresh()
        give(&high, xp: PlayerLevel.threshold(5))
        let profile: ProfileProgress = PlayerLevel.profile(of: high.state)
        low.update { s, _, _ in PlayerLevel.adopt(&s, profile: profile) }
        XCTAssertEqual(PlayerLevel.info(low.state).level, 5)
        high.update { s, _, _ in PlayerLevel.adopt(&s, profile: ProfileProgress(xp: 10, seen: nil)) }
        XCTAssertEqual(PlayerLevel.info(high.state).xp, PlayerLevel.threshold(5), "a lower profile never lowers a save")
    }

    func testAnUnlockIsAnnouncedOnceAndSavedLevelsStartSeen() throws {
        var e = try fresh()
        XCTAssertTrue(e.pendingNotices().isEmpty)
        e.update { s, _, _ in PlayerLevel.award(&s, PlayerLevel.threshold(3)) }
        XCTAssertEqual(e.pendingNotices().map { $0.id }, ["level.marketing", "level.insurance"])
        e.markNoticeSeen(id: "level.marketing")
        XCTAssertEqual(e.pendingNotices().map { $0.id }, ["level.insurance"])
        var other = try fresh()
        other.update { s, _, _ in PlayerLevel.adopt(&s, profile: ProfileProgress(xp: PlayerLevel.threshold(3), seen: nil)) }
        XCTAssertTrue(other.pendingNotices().isEmpty, "a level earned elsewhere is not announced again in a new game")
    }

    func testAFeatureAnnouncedUnderOlderRulesStaysOpen() throws {
        var e = try fresh()
        e.update { s, _, _ in s.rest["lvl"] = .object(["xp": .number(0), "seen": .array(["level.chain"])]) }
        XCTAssertTrue(LevelGates.isOpen(.chain, e.state))
        XCTAssertFalse(LevelGates.isOpen(.franchise, e.state))
        e.update { s, _, _ in s.rest["gateG"] = .object(["management": .number(9)]) }
        XCTAssertTrue(Gates.isOpen(.management, e.state, data: e.data))
    }

    func testAnOldSaveWithoutTheLadderIsNeverGated() throws {
        var e = try fresh()
        e.update { s, _, _ in PlayerLevel.award(&s, PlayerLevel.threshold(4)); s.rest["ldr"] = nil }
        for f in LevelFeature.allCases { XCTAssertTrue(LevelGates.isOpen(f, e.state), f.rawValue) }
        for g in Gate.allCases { XCTAssertEqual(Gates.visibility(g, e.state, data: e.data), .open, g.rawValue) }
        XCTAssertTrue(e.pendingNotices().isEmpty)
        XCTAssertTrue(e.unlockRoadmap().isEmpty)
    }

    func testTheRoadmapListsLockedFeaturesInLevelOrder() throws {
        var e = try fresh()
        give(&e, xp: PlayerLevel.threshold(4))
        let road = e.unlockRoadmap()
        XCTAssertEqual(road.first?.id, "gate.newCompany")
        XCTAssertEqual(road.count, FeatureUnlocks.table.filter { $0.level > 4 }.count)
        XCTAssertEqual(road.first?.condition, "Unlocks at level 5")
        XCTAssertEqual(road.first?.detail, "\(PlayerLevel.threshold(5) - PlayerLevel.threshold(4)) XP to go")
    }

    func testTheLadderListsEveryLevelWithItsXPAndEveryFeatureExactlyOnce() {
        let rungs: [LevelGates.Rung] = LevelGates.ladder()
        XCTAssertEqual(rungs.map { $0.level }, Array(1...(LevelGates.highestUnlockLevel + 1)))
        for r in rungs {
            XCTAssertEqual(r.xpRequired, PlayerLevel.threshold(r.level))
            if r.level > 1 { XCTAssertEqual(r.xpFromPrevious, r.xpRequired - rungs[r.level - 2].xpRequired) }
        }
        let listed: [LevelFeature] = rungs.flatMap { $0.unlocks.map { $0.feature } }
        XCTAssertEqual(listed.count, LevelFeature.allCases.count)
        XCTAssertEqual(Set(listed), Set(LevelFeature.allCases))
    }
}
