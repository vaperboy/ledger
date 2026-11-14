import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

final class UnlocksTests: XCTestCase {
    static func opened(_ e: inout GameEngine, _ id: Int, weeksAgo: Int) {
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].status = .open
            s.companies[i].openedWeek = s.week - weeksAgo
        }
    }

    static func level(_ e: inout GameEngine, _ l: Int) {
        e.update { s, _, _ in
            var v = s.rest["lvl"] ?? .object([:])
            v["xp"] = .number(Double(PlayerLevel.threshold(l)))
            s.rest["lvl"] = v
        }
    }

    func testWithoutTheLadderEveryPageIsOpen() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        Self.opened(&e, id, weeksAgo: 0)
        let items = e.unlockState(companyID: id)
        XCTAssertEqual(items.map { $0.id }, ["board", "research", "marketplace", "desk", "focus", "rivals"])
        for u in items where u.id != "board" { XCTAssertTrue(u.unlocked, u.id) }
    }

    func testPagesOpenAtTheirLevelAndSayWhich() throws {
        var e = try ChainsTests.engine(ladder: true)
        let id = ChainsTests.start(&e, "cafe")
        Self.opened(&e, id, weeksAgo: 60)
        let research = try XCTUnwrap(e.unlockItem("research", companyID: id))
        XCTAssertFalse(research.unlocked, "company age alone opens nothing")
        XCTAssertEqual(research.reason, "Unlocks at level \(FeatureUnlocks.unlockLevel(.research))")
        Self.level(&e, FeatureUnlocks.unlockLevel(.research))
        XCTAssertTrue(try XCTUnwrap(e.unlockItem("research", companyID: id)).unlocked)
        XCTAssertEqual(try XCTUnwrap(e.unlockItem("marketplace", companyID: id)).unlocked,
                       FeatureUnlocks.unlockLevel(.marketplace) <= FeatureUnlocks.unlockLevel(.research), "each page opens at its own level")
        Self.level(&e, FeatureUnlocks.unlockLevel(.marketplace))
        XCTAssertTrue(try XCTUnwrap(e.unlockItem("marketplace", companyID: id)).unlocked)
        XCTAssertFalse(try XCTUnwrap(e.unlockItem("desk", companyID: id)).unlocked)
        XCTAssertFalse(e.deskOpen)
        Self.level(&e, FeatureUnlocks.unlockLevel(.desk))
        XCTAssertTrue(e.deskOpen)
        XCTAssertTrue(e.weeklyPlanOpen)
        XCTAssertTrue(e.rivalsOpen)
    }

    func testBoardNeedsTheManagerLevelAndASeat() throws {
        var e = try ChainsTests.engine(ladder: true)
        let id = ChainsTests.start(&e, "cafe")
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].managerID = 999_999 } }
        XCTAssertFalse(try XCTUnwrap(e.unlockItem("board", companyID: id)).unlocked, "level 1 keeps the board shut")
        Self.level(&e, FeatureUnlocks.unlockLevel(.management))
        XCTAssertTrue(try XCTUnwrap(e.unlockItem("board", companyID: id)).unlocked)
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].managerID = nil } }
        XCTAssertFalse(try XCTUnwrap(e.unlockItem("board", companyID: id)).unlocked, "no one to take a seat")
    }

    func testOnlyTheBoardGetsItsOwnPopupBecauseLevelsAnnounceTheRest() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        Self.opened(&e, id, weeksAgo: 0)
        ChainsTests.play(&e, days: 14)
        XCTAssertFalse(e.pendingUnlocks().contains { $0.id != "board" }, "\(e.pendingUnlocks().map { $0.id })")
        e.update { s, _, ctx in
            if let i = s.companyIndex(id) { s.companies[i].managerID = 999_999 }
            Unlocks.weekly(&s, context: ctx)
        }
        XCTAssertEqual(e.pendingUnlocks().map { $0.id }, ["board"])
        e.markUnlockShown(id: "board", companyID: id)
        XCTAssertTrue(e.pendingUnlocks().isEmpty)
    }

    func testAPageASaveAlreadyOpenedStaysOpenBelowItsLevel() throws {
        var e = try ChainsTests.engine(ladder: true)
        let id = ChainsTests.start(&e, "cafe")
        e.update { s, _, _ in s.rest["unlkG"] = .object(["research": .object(["w": .number(3), "shown": .number(1), "c": .number(Double(id))])]) }
        XCTAssertTrue(try XCTUnwrap(e.unlockItem("research", companyID: id)).unlocked)
        XCTAssertTrue(FeatureUnlocks.isUnlocked(.research, e.state))
        XCTAssertFalse(FeatureUnlocks.isUnlocked(.desk, e.state))
    }

    func testOlderPerCompanyRecordsMergeIntoThePlayersTable() throws {
        var e = try ChainsTests.engine()
        let a = ChainsTests.start(&e, "cafe")
        e.update { s, _, _ in
            s.rest.removeValue(forKey: "unlkG")
            s.rest["unlk"] = .object(["\(a)": .object(["research": .object(["w": .number(3), "shown": .number(0)])]),
                                      "999": .object(["research": .object(["w": .number(5), "shown": .number(1)])])])
            Unlocks.migrate(&s)
        }
        XCTAssertTrue(e.unlockedFeatures().contains("research"))
        XCTAssertEqual(e.state.rest["unlkG"]?["research"]["w"].int, 3)
        XCTAssertEqual(e.state.rest["unlkG"]?["research"]["shown"].int, 0)
    }
}
