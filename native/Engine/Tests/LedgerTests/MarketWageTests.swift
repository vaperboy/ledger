import XCTest
import GameCore
import Finance
import Businesses
import Simulation

final class MarketWageTests: XCTestCase {
    private func cafe() throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 11)
        e.update { s, _, _ in Ledger.move(&s, .me, 80_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID) else { XCTFail("start"); throw CocoaError(.fileReadUnknown) }
        return (e, id)
    }

    func testGoingRateIsTheSameForEveryoneInTheRole() throws {
        var (e, id) = try cafe()
        let market = e.marketWage(role: "barista", companyID: id)
        XCTAssertGreaterThan(market, 0)
        var people: [Person] = []
        e.update { s, d, _ in
            for tier in ["young", "mid", "senior"] { for _ in 0..<5 { people.append(Hiring.generateCandidate(role: "barista", company: s.company(id), tier: tier, state: &s, data: d)) } }
        }
        XCTAssertEqual(e.marketWage(role: "barista", companyID: id), market, "generating candidates does not move the going rate")
        XCTAssertEqual(Set(people.map(\.role)), ["barista"])
    }

    func testAtTheGoingRateSomeAreABargainAndSomeCostMore() throws {
        var (e, id) = try cafe()
        let market = e.marketWage(role: "barista", companyID: id)
        var people: [Person] = []
        e.update { s, d, _ in for _ in 0..<80 { people.append(Hiring.generateCandidate(role: "barista", company: s.company(id), state: &s, data: d)) } }
        let takeIt = people.filter { $0.askingMonthlyWage <= market }
        let wantMore = people.filter { $0.askingMonthlyWage > market }
        XCTAssertFalse(takeIt.isEmpty); XCTAssertFalse(wantMore.isEmpty)
        let avgSkill: ([Person]) -> Double = { $0.map(\.skill).reduce(0, +) / Double($0.count) }
        XCTAssertGreaterThan(avgSkill(wantMore), avgSkill(takeIt))
    }

    func testTrialWeekCostsAQuarterOfTheGoingRate() throws {
        var (e, id) = try cafe()
        var pid = 0
        e.update { s, d, _ in pid = Hiring.generateCandidate(role: "barista", company: s.company(id), tier: "senior", state: &s, data: d).id }
        let market = e.marketWage(role: "barista", companyID: id)
        let before = e.state.company(id)!.cash
        XCTAssertNotNil(e.startTrialWeek(personID: pid, companyID: id))
        XCTAssertEqual(before - e.state.company(id)!.cash, (market / 4).rounded(), accuracy: 1)
    }
}
