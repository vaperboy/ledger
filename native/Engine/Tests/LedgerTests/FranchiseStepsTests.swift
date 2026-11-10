import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

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

    func testBuyoutDoesNotBlowUpEarlyInGameWeekModuloFiftyTwo() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 3)
        e.update { s, _, _ in Ledger.move(&s, .me, 50_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, fundWith: 5_000_000) else { throw XCTSkip("no company") }
        func price(week: Int) -> Double {
            var out = 0.0
            e.update { s, _, _ in
                guard let i = s.companyIndex(id) else { return }
                s.week = week
                s.companies[i].openedWeek = 0
                s.companies[i].set("franchise", .object(["end": .number(Double(week + 156)), "roy": 0.06, "mkt": 0.02, "fee": 100_000, "owed": 0]))
                var b = s.companies[i].books
                b.year["rev"] = 10_000 * Double(GameCalendar.weeksIntoYear(week: week))
                s.companies[i].books = b
                out = Franchising.buyout(s.companies[i], week: week)
            }
            return out
        }
        XCTAssertEqual(price(week: 55), price(week: 80), accuracy: 2_000, "the same weekly revenue gives the same price whatever week of the game it is")
    }
}
