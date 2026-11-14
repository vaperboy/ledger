import XCTest
import GameCore
@testable import Businesses
@testable import Simulation

final class StoreRotationTests: XCTestCase {
    func testTheShelfNeverHoldsPassItems() {
        let pass: Set<String> = Set(SeasonRewards.everything.map { $0.id })
        XCTAssertFalse(pass.isEmpty)
        for day in 739_000..<739_060 {
            for c in StoreRotation.pick(day: day) {
                XCTAssertFalse(pass.contains(c.id), "\(c.id) is a pass item")
                XCTAssertTrue(c.source == .box || c.source == .store, c.id)
            }
        }
        XCTAssertTrue(StoreRotation.eligible().allSatisfy { !pass.contains($0.id) })
    }

    func testTheShelfIsTheSameAllDayAndChangesBetweenDays() {
        let a: [String] = StoreRotation.pick(day: 739_100).map { $0.id }
        XCTAssertEqual(a, StoreRotation.pick(day: 739_100).map { $0.id })
        XCTAssertEqual(a.count, min(StoreRotation.size, StoreRotation.eligible().count))
        XCTAssertEqual(Set(a).count, a.count, "no item twice")
        let later: [[String]] = (739_101...739_107).map { StoreRotation.pick(day: $0).map { $0.id } }
        XCTAssertTrue(later.contains { $0 != a }, "a week of shelves should not all match")
    }

    func testEveryShelfItemHasAPriceAndSlotsStayOff() {
        for c in StoreRotation.eligible() {
            XCTAssertGreaterThan(StoreRotation.price(c) ?? 0, 0, c.id)
            XCTAssertNotEqual(c.item.kind, .saveSlot)
            XCTAssertNotEqual(c.item.kind, .tradePlate)
            XCTAssertNotEqual(c.rarity, .legendary, "legendary items stay box-only")
        }
    }

    func testAllOpenOpensEveryLevelGateAndCanBeTakenBack() throws {
        var e = try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 5)
        XCTAssertFalse(FeatureUnlocks.isUnlocked(.luxury, e.state))
        e.update { s, _, _ in FeatureUnlocks.setAllOpen(&s, true) }
        XCTAssertTrue(FeatureUnlocks.allOpen(e.state))
        for f in LevelFeature.allCases { XCTAssertTrue(FeatureUnlocks.isUnlocked(f, e.state), f.rawValue) }
        e.update { s, _, _ in FeatureUnlocks.setAllOpen(&s, false) }
        XCTAssertFalse(FeatureUnlocks.isUnlocked(.luxury, e.state))
    }
}
