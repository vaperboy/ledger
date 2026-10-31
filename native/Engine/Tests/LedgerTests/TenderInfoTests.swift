import XCTest
import GameCore
import Businesses
import Simulation

/// The tender card reads: the company's own cost estimate and the rivals as a word.
final class TenderInfoTests: XCTestCase {
    func testRivalCountIsAWordScale() {
        func t(_ n: Int) -> ProjectTenders.Tender { ProjectTenders.Tender(raw: ["rivals": .number(Double(n))]) }
        XCTAssertEqual([0, 1, 2, 3, 4, 5, 9].map { ProjectTenders.rivalScale(t($0)) }, ["None", "A few", "A few", "Several", "Several", "Many", "Many"])
    }

    func testCostEstimateIsListPriceTimesMaterialAndSubcontractShare() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "construction")
        var est: Double?
        var share = 0.0
        e.update { s, data, _ in
            let co = s.company(id)!
            let t = ProjectTenders.Tender(raw: ["val": 200_000, "rivals": 3])
            est = ProjectTenders.costEstimate(t, co, data: data)
            let tw = data.catalog["construction"]!.traits
            share = (tw["mat"] ?? 0.5) + (tw["sub"] ?? 0)
        }
        let cost = try XCTUnwrap(est)
        XCTAssertEqual(cost, (200_000 * share).rounded(), accuracy: 1)
        XCTAssertGreaterThan(cost, 0)
        XCTAssertLessThan(cost, 200_000, "a job that costs more than it pays would not be worth bidding at list price")
    }
}
