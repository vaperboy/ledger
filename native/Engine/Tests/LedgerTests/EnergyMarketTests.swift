import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The global electricity price: demand from every company, supply from the world and the player's plants.
final class EnergyMarketTests: XCTestCase {
    private let d = EnergyMarket.worldDemand, s = EnergyMarket.worldSupply

    func testPriceRisesWithDemandAndFallsWithSupply() {
        let even = EnergyMarket.target(demand: d, supply: s)
        XCTAssertEqual(even, 1, accuracy: 1e-9)
        XCTAssertGreaterThan(EnergyMarket.target(demand: d * 1.08, supply: s), even)
        XCTAssertGreaterThan(EnergyMarket.target(demand: d * 1.2, supply: s), EnergyMarket.target(demand: d * 1.08, supply: s))
        XCTAssertLessThan(EnergyMarket.target(demand: d, supply: s * 1.1), even)
        // Far out it stays inside the band.
        XCTAssertEqual(EnergyMarket.target(demand: d * 9, supply: s), EnergyMarket.band.upperBound)
        XCTAssertEqual(EnergyMarket.target(demand: d, supply: s * 9), EnergyMarket.band.lowerBound)
    }

    func testOnePlantBarelyMovesThePrice() {
        // A 30 MW wind park: about 1,800 MWh a week.
        let withPlant = EnergyMarket.target(demand: d, supply: s + 1_800)
        XCTAssertLessThan(abs(withPlant - 1), 0.01)
        // A very large one (100 MW) still moves it by only a few percent.
        XCTAssertLessThan(abs(EnergyMarket.target(demand: d, supply: s + 6_000) - 1), 0.03)
    }

    func testPriceFollowsTheTargetSlowlyAndStaysInTheBand() {
        var p = 1.0
        for _ in 0..<4 { p = EnergyMarket.step(index: p, target: 1.5, noise: 0) }
        XCTAssertGreaterThan(p, 1)
        XCTAssertLessThan(p, 1.3, "four weeks do not get most of the way")
        for _ in 0..<400 { p = EnergyMarket.step(index: p, target: 9, noise: 3) }
        XCTAssertLessThanOrEqual(p, EnergyMarket.band.upperBound)
    }

    func testPlantAndConsumersChangeTheTotals() throws {
        var e = try ChainsTests.engine("NO", seed: 21)
        let base = EnergyMarket.totals(e.state, data: e.data)
        XCTAssertEqual(base.supply, EnergyMarket.worldSupply, accuracy: 1e-6)
        let gym = ChainsTests.start(&e, "gym")
        let plant = ChainsTests.start(&e, "power")
        e.update { st, _, _ in
            for id in [gym, plant] { if let i = st.companyIndex(id) { st.companies[i].status = .open } }
            if let i = st.companyIndex(plant) {
                var lw = st.companies[i].value("lastW"); lw["cap"] = .number(1_800); st.companies[i].set("lastW", lw)
            }
        }
        let now = EnergyMarket.totals(e.state, data: e.data)
        XCTAssertGreaterThan(now.demand, base.demand, "a company that runs a gym uses electricity")
        XCTAssertEqual(now.supply, base.supply + 1_800, accuracy: 1e-6)
        XCTAssertLessThan(abs(EnergyMarket.target(demand: now.demand, supply: now.supply) - 1), 0.01)
    }

    func testBoomRaisesTheGlobalPriceAndTheSnapshotSaysSo() throws {
        var e = try ChainsTests.engine("NO", seed: 5)
        e.update { st, _, _ in st.economy.demand = 1.12; st.economy.phase = "boom"; st.economy.weeksLeftInPhase = 80 }
        for _ in 0..<8 * 7 { e.nextDay() }
        let snap = EnergyMarket.snapshot(e.state)
        XCTAssertGreaterThan(snap.priceIndex, 1.0)
        XCTAssertEqual(snap.balanceWord, "Tight")
        XCTAssertTrue(EnergyMarket.worldPrices(e.state).contains { $0.id == "power" })
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "the books balance")
    }

    func testDirectionNeedsMoreThanTwoPercent() {
        XCTAssertEqual(EnergyMarket.direction(change: 0.01), .flat)
        XCTAssertEqual(EnergyMarket.direction(change: 0.05), .up)
        XCTAssertEqual(EnergyMarket.direction(change: -0.05), .down)
    }

    func testUtilityCostFollowsTheGlobalPrice() throws {
        func powerSpend(_ index: Double) throws -> Double {
            var e = try ChainsTests.engine("NO", seed: 31)
            let id = ChainsTests.start(&e, "gym")
            e.update { st, _, _ in
                if let i = st.companyIndex(id) { st.companies[i].status = .open }
                _ = Payments.injectCash(&st, companyID: id, amount: 5_000_000)
                st.economy.power = index
            }
            for _ in 0..<7 { e.nextDay() }
            let co = try XCTUnwrap(e.state.company(id))
            return try XCTUnwrap(SupplyCatalogue.weeklySpend(co, line: "power")).now
        }
        let cheap = try powerSpend(0.8), dear = try powerSpend(1.5)
        XCTAssertGreaterThan(cheap, 0)
        XCTAssertGreaterThan(dear, cheap * 1.4)
    }

    func testPowerPlantSellsAtTheGlobalPrice() {
        func price(_ index: Double) -> Double {
            EnergyModel.powerWeek(megawattsBought: 30, building: 0, month: 3, source: EnergyModel.sources[0], hedge: 0, capacityFactor: 0.36, opexRate: 0.025,
                                  condition: 1, technicianFTE: 4, capacityModifier: 1, demandModifier: 1, economyPower: index, inflationIndex: 1, noise: 0).price
        }
        XCTAssertEqual(price(1.25) / price(1.0), 1.25, accuracy: 1e-9)
    }

    // MARK: Retired trades

    func testRetiredTradesAreNotOfferedButOwnedOnesStayOpen() throws {
        var e = try ChainsTests.engine("UK", seed: 3)
        let ids = Set(e.tradePickerRows().map { $0.tradeID })
        for t in ["bank", "insco", "fund", "casino", "club"] { XCTAssertFalse(ids.contains(t), t) }
        XCTAssertTrue(ids.contains("power") && ids.contains("gym"))
        for t in ["bank", "insco", "fund", "casino"] {
            if case .success = e.startCompany(tradeID: t, cityID: e.state.player.cityID, form: .limited, fundWith: 1_000_000) { XCTFail("\(t) could be started") }
        }
        XCTAssertEqual(e.foundClub(countryCode: "UK"), .notAvailable)
        // A saved company of a retired trade keeps trading.
        let casino = ChainsTests.start(&e, "casino")
        XCTAssertNotEqual(casino, 0)
        ChainsTests.play(&e, days: 14)
        XCTAssertEqual(e.state.company(casino)?.type, "casino")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }
}
