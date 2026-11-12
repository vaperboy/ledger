import XCTest
import GameCore
import Businesses
@testable import Simulation

final class LevelRewardsTests: XCTestCase {
    private static let native: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func avatars() throws -> [JSONValue] {
        let url: URL = Self.native.appendingPathComponent("App/Ledger/Resources/Content/avatars/avatars.json")
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))["avatars"].array
    }

    private func rank(_ tier: String) -> Int { ["common": 0, "rare": 1, "epic": 2, "legendary": 3][tier] ?? 0 }

    func testTheLevelStopsAtOneHundred() throws {
        XCTAssertEqual(PlayerLevel.maxLevel, 100)
        XCTAssertEqual(PlayerLevel.level(forXP: PlayerLevel.threshold(100)), 100)
        XCTAssertEqual(PlayerLevel.level(forXP: PlayerLevel.threshold(100) * 10), 100)
        var e = try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 1)
        e.update { s, _, _ in s.rest["lvl"] = .object(["xp": .number(Double(PlayerLevel.threshold(100) * 3))]) }
        let info: PlayerLevel.Info = PlayerLevel.info(e.state)
        XCTAssertEqual(info.level, 100)
        XCTAssertEqual(info.progress, 1)
        XCTAssertEqual(info.xpForNext, 0)
    }

    func testVenturesNeedALevelAndTheMapShowsIt() throws {
        var e = try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 5)
        let l: Int = LevelGates.level(.ventures)
        XCTAssertGreaterThan(l, 1)
        XCTAssertFalse(LevelGates.isOpen(.ventures, e.state))
        XCTAssertEqual(LevelGates.lockLine(.ventures), "Unlocks at level \(l)")
        e.update { s, _, _ in s.rest["lvl"] = .object(["xp": .number(Double(PlayerLevel.threshold(l)))]) }
        XCTAssertTrue(LevelGates.isOpen(.ventures, e.state))
        XCTAssertTrue(LevelGates.ladder().contains { $0.level == l && $0.unlocks.contains { $0.feature == .ventures } })
    }

    func testEveryLevelFromTwoToOneHundredGivesGoldOnce() {
        XCTAssertEqual(LevelRewards.all.map { $0.level }, Array(2...100))
        XCTAssertTrue(LevelRewards.all.allSatisfy { $0.gold > 0 })
        XCTAssertEqual(LevelRewards.due(from: 1, to: 3).map { $0.level }, [2, 3])
        XCTAssertTrue(LevelRewards.due(from: 100, to: 100).isEmpty)
    }

    func testEarlyRewardsAreSmallAndLateOnesRicher() {
        let early: Int = LevelRewards.due(from: 1, to: 10).reduce(0) { $0 + $1.gold }
        let late: Int = LevelRewards.due(from: 60, to: 70).reduce(0) { $0 + $1.gold }
        XCTAssertLessThan(early, late)
        XCTAssertGreaterThan(LevelRewards.reward(at: 100)?.gold ?? 0, LevelRewards.reward(at: 99)?.gold ?? 0)
    }

    func testLevelIconsMatchTheirLevelAndGrowInQuality() throws {
        let list: [JSONValue] = try avatars()
        for r in LevelRewards.all {
            guard let id = r.icon else { continue }
            guard let a = list.first(where: { $0["id"].string == id }) else { return XCTFail("\(id) is missing from avatars.json") }
            XCTAssertEqual(a["unlock"].string, "level", id)
            XCTAssertEqual(a["value"].string, String(r.level), id)
            if r.level > 7 && r.level <= 50 { XCTAssertLessThanOrEqual(rank(a["tier"].string), 1, "\(id) should be basic or rare") }
            if r.level > 60 { XCTAssertGreaterThanOrEqual(rank(a["tier"].string), 2, "\(id) should not be basic") }
        }
        XCTAssertTrue(LevelRewards.all.filter { $0.level <= 15 && $0.icon != nil }.count >= 4, "a few cheap icons come early")
        let top: JSONValue? = list.first { $0["id"].string == LevelRewards.reward(at: 100)?.icon }
        XCTAssertEqual(top?["tier"].string, "legendary")
    }

    func testEveryLevelUnlockedIconIsBoundAndNotTradable() throws {
        for a in try avatars() where a["unlock"].string == "level" {
            XCTAssertTrue(a["bound"].bool, "\(a["id"].string) must be bound")
            XCTAssertTrue(LevelRewards.isLevelIcon(a["id"].string), "\(a["id"].string) must be handed out by a level reward")
        }
        for id in LevelRewards.iconIDs {
            XCTAssertTrue(TradeRules.isAccountBound(id), id)
            XCTAssertFalse(TradeRules.isSellable(ArtifactItem(defID: id, serial: 1)), id)
        }
    }
}
