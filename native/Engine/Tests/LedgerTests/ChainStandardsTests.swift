import XCTest
import GameCore
import Finance
import Businesses
import Simulation

/// What the stores of a chain follow: a price band, a headcount floor and an ordering policy, kept on the chain and read through one call.
final class ChainStandardsTests: XCTestCase {
    private func chain() throws -> (e: GameEngine, id: Int, a: Int, b: Int) {
        var e = try ChainsTests.engine("NO")
        let a = ChainsTests.start(&e, "cafe")
        ChainsTests.season(&e, a)
        let id = try XCTUnwrap(e.makeChain(companyID: a, name: "Khan Shop"))
        guard case .success(let b) = e.openLocation(chainID: id, cityID: e.state.player.cityID) else { throw XCTSkip("location not opened") }
        return (e, id, a, b)
    }

    func testAChainThatNeverSetStandardsHasTheWidestBand() throws {
        let (e, id, _, _) = try chain()
        let st = try XCTUnwrap(e.chainStandards(chainID: id))
        XCTAssertEqual(st.priceLow, -3); XCTAssertEqual(st.priceHigh, 3)
        XCTAssertEqual(st.headcountFloor, 0)
        XCTAssertEqual(st.ordering, 1)
        XCTAssertNil(e.chainStandards(chainID: 987_654))
    }

    func testStandardsAreStoredOnTheChainAndSurviveASave() throws {
        var (e, id, _, _) = try chain()
        XCTAssertEqual(e.setChainStandards(chainID: id, priceLow: -1, priceHigh: 1, headcountFloor: 3, ordering: 2), .applied)
        let st = try XCTUnwrap(e.chainStandards(chainID: id))
        XCTAssertEqual(st, Chains.StoreStandards(priceLow: -1, priceHigh: 1, headcountFloor: 3, ordering: 2))
        let back = try JSONDecoder().decode(GameState.self, from: try JSONEncoder().encode(e.state))
        XCTAssertEqual(Chains.chainStandards(back, chainID: id), st)
        XCTAssertEqual(e.setChainStandards(chainID: id, priceLow: -1, priceHigh: 1, headcountFloor: 3, ordering: 2), .unchanged)
        XCTAssertEqual(e.setChainStandards(chainID: 987_654, headcountFloor: 1), .refused("That chain no longer exists."))
    }

    func testAStoresOwnPriceStepStaysInsideTheBand() throws {
        var (e, id, a, b) = try chain()
        e.setChainStandards(chainID: id, priceLow: -1, priceHigh: 1)
        e.setStoreRule(companyID: b, rule: .priceSteps(3))
        e.setStoreRule(companyID: a, rule: .priceSteps(-3))
        let chainPrice = Chains.chain(e.state, id: id)?["rules"]["price"].double ?? 0
        XCTAssertEqual(e.state.company(b)?.priceLevel ?? 99, min(3, chainPrice + 1), "asked for +3, held to the band")
        XCTAssertEqual(e.state.company(a)?.priceLevel ?? 99, max(-3, chainPrice - 1), "asked for -3, held to the band")
        // widening the band lets the store's own step through
        e.setChainStandards(chainID: id, priceLow: -3, priceHigh: 3)
        XCTAssertEqual(e.state.company(b)?.priceLevel ?? 99, min(3, chainPrice + 3))
    }

    func testTheOrderingPolicyIsTheChainsStockRuleAndReachesTheStores() throws {
        var (e, id, a, b) = try chain()
        e.setChainStandards(chainID: id, ordering: 2)
        XCTAssertEqual(e.chainStandards(chainID: id)?.ordering, 2)
        XCTAssertEqual(e.state.company(a)?.num("stockPol"), 2)
        XCTAssertEqual(e.state.company(b)?.num("stockPol"), 2)
    }

    func testAStoreReadsItsChainsStandards() throws {
        var (e, id, a, _) = try chain()
        e.setChainStandards(chainID: id, headcountFloor: 4)
        XCTAssertEqual(Chains.chainStandards(e.state, of: try XCTUnwrap(e.state.company(a)))?.headcountFloor, 4)
        let loose = ChainsTests.start(&e, "cafe", name: "Loner")
        XCTAssertNil(Chains.chainStandards(e.state, of: try XCTUnwrap(e.state.company(loose))), "a company outside a chain follows no standards")
    }
}
