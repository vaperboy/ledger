import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The franchisee's road into a brand, step by step: eligibility, entry fee, approval and terms, opening.
final class FranchiseStepsTests: XCTestCase {
    private func openBrand(_ e: GameEngine) throws -> FranchiseBrands.Brand {
        let w = World(state: e.state, data: e.data)
        return try XCTUnwrap(["cafe", "gym", "barber", "bakery"].lazy.compactMap { FranchiseBrands.brands($0, country: "NO", w).first { $0.openness == "open" } }.first)
    }

    private func states(_ e: GameEngine, _ b: FranchiseBrands.Brand) -> [FranchiseBrands.StepState] { e.franchiseeSteps(b).map { $0.state } }

    func testStepsFollowTheApplicationToTheOpening() throws {
        var e = try ChainsTests.engine()
        let b = try openBrand(e)
        XCTAssertEqual(e.franchiseeSteps(b).map { $0.key }, ["eligibility", "fee", "approval", "opening"])
        XCTAssertEqual(states(e, b), [.done, .done, .current, .todo])
        XCTAssertEqual(e.applyToFranchiseBrand(b.id), .ok)
        XCTAssertEqual(states(e, b), [.done, .done, .waiting, .todo])
        e.update { s, _, _ in s.rest["fbApps"]?[b.id]["st"] = "invited" }
        XCTAssertEqual(states(e, b), [.done, .done, .current, .todo])
        e.update { s, _, _ in s.rest["fbApps"]?[b.id]["st"] = "agreed" }
        XCTAssertEqual(states(e, b), [.done, .done, .done, .current])
        e.update { s, _, _ in s.rest["fbApps"]?[b.id]["st"] = "refused" }
        XCTAssertEqual(states(e, b)[2], .blocked)
    }

    func testClosedBrandBlocksAndShortCashShowsInTheFeeStep() throws {
        var e = try ChainsTests.engine()
        let w = World(state: e.state, data: e.data)
        let closed = try XCTUnwrap(["cafe", "gym", "barber", "bakery", "restaurant"].lazy.compactMap { FranchiseBrands.brands($0, country: "NO", w).first { $0.openness == "closed" } }.first)
        XCTAssertEqual(states(e, closed)[0], .blocked)
        XCTAssertEqual(states(e, closed)[3], .blocked)
        let b = try openBrand(e)
        e.update { s, _, _ in Ledger.move(&s, .me, -s.cash, why: "Spent") }
        let fee = try XCTUnwrap(e.franchiseeSteps(b).first { $0.key == "fee" })
        XCTAssertEqual(fee.state, .current)
        XCTAssertTrue(fee.detail.contains("short"))
    }
}
