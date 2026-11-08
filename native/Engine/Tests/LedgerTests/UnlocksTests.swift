import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Progressive unlocks: the registry, the one-time announcement and the silent seeding of old saves.
final class UnlocksTests: XCTestCase {
    /// An open company that opened `weeksAgo` weeks ago.
    static func opened(_ e: inout GameEngine, _ id: Int, weeksAgo: Int) {
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].status = .open
            s.companies[i].openedWeek = s.week - weeksAgo
        }
    }

    func testFreshCompanyHasLockedItemsWithReasons() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        Self.opened(&e, id, weeksAgo: 0)
        let items = e.unlockState(companyID: id)
        XCTAssertEqual(items.map { $0.id }, ["board", "chain", "franchise", "abroad", "research", "dividends", "marketplace"])
        let chain = try XCTUnwrap(items.first { $0.id == "chain" })
        XCTAssertFalse(chain.unlocked)
        XCTAssertTrue(chain.reason.hasPrefix("Unlocks when"), chain.reason)
        XCTAssertFalse(try XCTUnwrap(items.first { $0.id == "research" }).unlocked)
        XCTAssertTrue(try XCTUnwrap(items.first { $0.id == "marketplace" }).unlocked)
        XCTAssertTrue(try XCTUnwrap(items.first { $0.id == "board" }).hiddenUntilUnlocked)
        XCTAssertFalse(items.filter { $0.id != "board" }.contains { $0.hiddenUntilUnlocked })
    }

    func testSeasonedCompanyOpensEverythingItCan() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        ChainsTests.season(&e, id)
        let items = e.unlockState(companyID: id)
        for k in ["chain", "franchise", "abroad", "research"] {
            XCTAssertTrue(try XCTUnwrap(items.first { $0.id == k }).unlocked, k)
        }
    }

    func testNewUnlockIsAnnouncedExactlyOnce() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        Self.opened(&e, id, weeksAgo: 0)
        ChainsTests.play(&e, days: 14)   // the first sweep seeds the record silently
        for u in e.pendingUnlocks() { e.markUnlockShown(id: u.id, companyID: u.companyID) }
        Self.opened(&e, id, weeksAgo: 60)
        ChainsTests.play(&e, days: 7)
        let waiting = e.pendingUnlocks().filter { $0.companyID == id }
        XCTAssertTrue(waiting.contains { $0.id == "research" }, "\(waiting.map { $0.id })")
        XCTAssertTrue(waiting.contains { $0.id == "chain" })
        XCTAssertFalse(waiting.contains { $0.id == "marketplace" })
        let first = try XCTUnwrap(waiting.first)
        XCTAssertNotNil(first.since)
        e.markUnlockShown(id: first.id, companyID: id)
        XCTAssertFalse(e.pendingUnlocks().contains { $0.id == first.id && $0.companyID == id })
        ChainsTests.play(&e, days: 14)
        XCTAssertFalse(e.pendingUnlocks().contains { $0.id == first.id && $0.companyID == id }, "announced again")
    }

    func testPlayerLevelUnlocksFollowThePlayerToANewCompany() throws {
        var e = try ChainsTests.engine()
        let a = ChainsTests.start(&e, "cafe")
        Self.opened(&e, a, weeksAgo: 0)
        ChainsTests.play(&e, days: 14)
        for u in e.pendingUnlocks() { e.markUnlockShown(id: u.id, companyID: u.companyID) }
        Self.opened(&e, a, weeksAgo: 60)
        ChainsTests.play(&e, days: 7)
        for u in e.pendingUnlocks() { e.markUnlockShown(id: u.id, companyID: u.companyID) }
        let b = ChainsTests.start(&e, "bakery")
        Self.opened(&e, b, weeksAgo: 0)
        let items = e.unlockState(companyID: b)
        for k in ["chain", "research"] {
            XCTAssertTrue(try XCTUnwrap(items.first { $0.id == k }).unlocked, "\(k) should follow the player")
        }
        ChainsTests.play(&e, days: 14)
        XCTAssertFalse(e.pendingUnlocks().contains { $0.companyID == b && ["chain", "franchise", "abroad", "research"].contains($0.id) }, "announced again for the new company")
    }

    func testOldSaveIsSeededSilently() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        Self.opened(&e, id, weeksAgo: 200)
        ChainsTests.season(&e, id)
        Self.opened(&e, id, weeksAgo: 200)
        e.update { s, _, _ in s.rest.removeValue(forKey: "unlk"); s.rest.removeValue(forKey: "unlkG") }
        XCTAssertTrue(e.pendingUnlocks().isEmpty)
        ChainsTests.play(&e, days: 7)
        XCTAssertTrue(e.pendingUnlocks().isEmpty, "\(e.pendingUnlocks().map { $0.id })")
        XCTAssertNotNil(e.state.rest["unlkG"])
        XCTAssertNotNil(try XCTUnwrap(e.unlockState(companyID: id).first { $0.id == "chain" }).since)
    }

    func testBoardOpensForALimitedCompanyWithAManager() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        XCTAssertEqual(e.state.company(id)?.form, .limited)
        XCTAssertFalse(try XCTUnwrap(e.unlockItem("board", companyID: id)).unlocked)
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].managerID = 999_999
        }
        XCTAssertTrue(try XCTUnwrap(e.unlockItem("board", companyID: id)).unlocked)
    }

    func testUnlockEarnedByOneCompanyOpensForALaterCompany() throws {
        var e = try ChainsTests.engine()
        let a = ChainsTests.start(&e, "cafe")
        Self.opened(&e, a, weeksAgo: 0)
        ChainsTests.play(&e, days: 14)
        for u in e.pendingUnlocks() { e.markUnlockShown(id: u.id, companyID: u.companyID) }
        Self.opened(&e, a, weeksAgo: 60)
        ChainsTests.play(&e, days: 7)
        XCTAssertTrue(e.unlockedFeatures().contains("research"))
        let b = ChainsTests.start(&e, "bakery")
        Self.opened(&e, b, weeksAgo: 0)
        for u in e.unlockState(companyID: b) where u.id != "board" && u.id != "dividends" && e.unlockedFeatures().contains(u.id) {
            XCTAssertTrue(u.unlocked, "\(u.id) should be open at the new company")
        }
        XCTAssertFalse(try XCTUnwrap(e.unlockItem("research", companyID: b)).reason.hasPrefix("Unlocks when"))
    }

    func testPendingHasOneEntryPerUnlockNotPerCompany() throws {
        var e = try ChainsTests.engine()
        let a = ChainsTests.start(&e, "cafe")
        let b = ChainsTests.start(&e, "bakery")
        Self.opened(&e, a, weeksAgo: 0)
        Self.opened(&e, b, weeksAgo: 0)
        ChainsTests.play(&e, days: 14)
        for u in e.pendingUnlocks() { e.markUnlockShown(id: u.id, companyID: u.companyID) }
        Self.opened(&e, a, weeksAgo: 60)
        Self.opened(&e, b, weeksAgo: 60)
        ChainsTests.play(&e, days: 7)
        let ids = e.pendingUnlocks().map { $0.id }
        XCTAssertEqual(ids.count, Set(ids).count, "\(ids)")
        XCTAssertTrue(ids.contains("research"))
        e.markUnlockShown(id: "research", companyID: a)
        XCTAssertFalse(e.pendingUnlocks().contains { $0.id == "research" })
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
