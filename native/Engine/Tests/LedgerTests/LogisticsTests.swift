import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Events
import Simulation

/// Transport cost and landed cost, shipments with border holds and spoilage, stock insurance and losses, and demand driven by player counts.
final class LogisticsTests: XCTestCase {
    // MARK: Transport cost model

    func testDistancesAreSensible() {
        XCTAssertEqual(TransportCost.distanceKm(from: "UK", to: "UK"), TransportCost.minimumKm)
        let ltDe = TransportCost.distanceKm(from: "LT", to: "DE")
        XCTAssertTrue(ltDe > 500 && ltDe < 900, "\(ltDe)")
        XCTAssertGreaterThan(TransportCost.distanceKm(from: "UK", to: "AU"), 15000)
        XCTAssertEqual(TransportCost.distanceKm(from: "DE", to: "FR"), TransportCost.distanceKm(from: "FR", to: "DE"), accuracy: 0.001)
    }

    func testBordersAndModes() {
        XCTAssertFalse(TransportCost.crossesBorder(from: "DE", to: "FR"))   // inside the EU
        XCTAssertTrue(TransportCost.crossesBorder(from: "DE", to: "UK"))
        XCTAssertFalse(TransportCost.crossesBorder(from: "UK", to: "UK"))
        XCTAssertEqual(TransportCost.mode(from: "DE", to: "FR", cargo: .standard), .road)
        XCTAssertEqual(TransportCost.mode(from: "UK", to: "AU", cargo: .standard), .sea)
        XCTAssertEqual(TransportCost.mode(from: "UK", to: "AU", cargo: .perishable), .air)
    }

    func testQuoteShape() {
        let none = TransportCost.quote(goodsValue: 0, from: "UK", to: "AU")
        XCTAssertEqual(none.fees, 0)
        let bad = TransportCost.quote(goodsValue: .nan, from: "UK", to: "AU")
        XCTAssertEqual(bad.landed, 0)
        let eu = TransportCost.quote(goodsValue: 100_000, from: "DE", to: "FR")
        XCTAssertEqual(eu.customs, 0)
        XCTAssertGreaterThan(eu.transport, 0)
        let far = TransportCost.quote(goodsValue: 100_000, from: "UK", to: "AU")
        XCTAssertGreaterThan(far.customs, 0)
        XCTAssertGreaterThan(far.transport, eu.transport)
        XCTAssertGreaterThan(far.transitWeeks, eu.transitWeeks)
        let light = TransportCost.quote(goodsValue: 100_000, from: "UK", to: "AU", cargo: .light)
        let bulky = TransportCost.quote(goodsValue: 100_000, from: "UK", to: "AU", cargo: .bulky)
        XCTAssertLessThan(light.transport, bulky.transport)
        XCTAssertEqual(far.landed, far.goodsValue + far.transport + far.customs)
    }

    func testCheapFarSupplierLosesToLocalAndNearCheapWins() {
        let far = TransportCost.Offer(id: "far", country: "AU", unitPrice: 92)
        let local = TransportCost.Offer(id: "local", country: "UK", unitPrice: 100)
        let near = TransportCost.Offer(id: "near", country: "DE", unitPrice: 90)
        let ranked = TransportCost.rank([far, local], units: 1000, to: "UK")
        XCTAssertEqual(ranked.map { $0.offer.id }, ["local", "far"])
        XCTAssertGreaterThan(ranked[1].landedUnitCost, ranked[0].landedUnitCost)
        XCTAssertLessThan(far.unitPrice, local.unitPrice)
        XCTAssertEqual(TransportCost.rank([far, local, near], units: 1000, to: "UK").first?.offer.id, "near")
    }

    // MARK: Demand from player counts

    func testPlayerDemandIsBounded() {
        XCTAssertEqual(PlayerDemand.factor(playerCount: PlayerDemand.referenceCount), 1, accuracy: 1e-9)
        XCTAssertEqual(PlayerDemand.factor(playerCount: 0), PlayerDemand.lowest, accuracy: 1e-9)
        XCTAssertEqual(PlayerDemand.factor(playerCount: -50), PlayerDemand.lowest, accuracy: 1e-9)
        XCTAssertEqual(PlayerDemand.factor(playerCount: Int.max), PlayerDemand.highest, accuracy: 1e-9)
        var last = 0.0
        for n in [0, 1, 10, 100, 200, 1000, 10_000, 1_000_000] {
            let f = PlayerDemand.factor(playerCount: n)
            XCTAssertGreaterThanOrEqual(f, last)
            XCTAssertTrue(f >= PlayerDemand.lowest && f <= PlayerDemand.highest)
            last = f
        }
    }

    func testProviderDrivesDemandFactor() {
        defer { PlayerDemand.provider = nil }
        PlayerDemand.provider = nil
        XCTAssertEqual(PlayerDemand.factor(country: "UK"), 1)
        PlayerDemand.provider = StandInPlayerCounts(counts: ["UK": 5000, "NO": 3], fallback: 200)
        XCTAssertGreaterThan(PlayerDemand.factor(country: "UK"), 1.2)
        XCTAssertLessThan(PlayerDemand.factor(country: "NO"), 0.9)
        XCTAssertEqual(PlayerDemand.factor(country: "DE"), 1, accuracy: 1e-9)
    }

    func testDemandModelUsesPlayerFactor() throws {
        defer { PlayerDemand.provider = nil }
        var (e, id) = try engine(weeks: 6)
        let co = try XCTUnwrap(e.state.company(id))
        let w = World(state: e.state, data: e.data)
        let bd = try XCTUnwrap(e.data.catalog[co.type])
        PlayerDemand.provider = nil
        let base = DemandModel.compute(co, bd, w)
        XCTAssertNil(base.part("players"))
        PlayerDemand.provider = StandInPlayerCounts(counts: [co.countryCode: 100_000])
        let boosted = DemandModel.compute(co, bd, w)
        XCTAssertEqual(try XCTUnwrap(boosted.part("players")), PlayerDemand.highest, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(boosted.customers, base.customers)
        _ = e.state
    }

    // MARK: Helpers

    func engine(weeks: Int) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 777)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 80_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            Payments.injectCash(&s, companyID: id, amount: 60_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        for _ in 0..<(weeks * 7) { e.nextDay() }
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .open } }
        return (e, id)
    }

    func loss(_ e: GameEngine, _ id: Int) -> Double { e.state.company(id)?.books.total["loss"] ?? 0 }

    // MARK: Shipments

    func testNearDomesticOrderArrivesAtOnce() throws {
        var (e, id) = try engine(weeks: 4)
        let before = try XCTUnwrap(e.state.company(id)).inventory
        var result: Shipments.OrderResult = .badOrder
        e.update { s, data, _ in result = Shipments.order(&s, companyID: id, offer: .init(id: "V-UK-1", country: "UK", unitPrice: 10), units: 1000, data: data) }
        guard case .ok(let landed, let ship) = result else { return XCTFail("\(result)") }
        XCTAssertNil(ship)
        XCTAssertGreaterThan(landed, 10_000)
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).inventory, before + 10_000)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testOrderRefusals() throws {
        var (e, id) = try engine(weeks: 4)
        e.update { s, data, _ in
            XCTAssertEqual(Shipments.order(&s, companyID: 99_999, offer: .init(id: "x", country: "UK", unitPrice: 1), units: 1, data: data), .unknownCompany)
            XCTAssertEqual(Shipments.order(&s, companyID: id, offer: .init(id: "x", country: "UK", unitPrice: 1), units: 0, data: data), .badOrder)
            XCTAssertEqual(Shipments.order(&s, companyID: id, offer: .init(id: "x", country: "AU", unitPrice: 1e12), units: 1e6, data: data), .noCash)
        }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    /// Many cross-border orders: some are held, all arrive in the end, and stock = ordered goods - losses (nothing appears or vanishes).
    func runShipments(cargo: TransportCost.Cargo) throws -> (held: Int, lost: Double) {
        var (e, id) = try engine(weeks: 4)
        let invBefore = try XCTUnwrap(e.state.company(id)).inventory
        let lossBefore = loss(e, id)
        var ordered = 0.0
        e.update { s, data, _ in
            for n in 0..<40 {
                let price = 100 + Double(n)
                if case .ok = Shipments.order(&s, companyID: id, offer: .init(id: "V-AU-\(n)", country: "AU", unitPrice: price), units: 100, cargo: cargo, data: data) { ordered += price * 100 }
            }
        }
        XCTAssertGreaterThan(ordered, 0)
        let ships = Shipments.inTransit(e.state, companyID: id)
        XCTAssertEqual(ships.count, 40)
        var held = 0
        e.update { s, data, _ in
            for _ in 0..<12 {
                s.week += 1
                Shipments.weekly(&s, data: data)
                held += Shipments.inTransit(s).filter { $0["delay"].int > 0 }.count > 0 ? 1 : 0
            }
        }
        XCTAssertTrue(Shipments.inTransit(e.state).isEmpty)
        XCTAssertGreaterThan(held, 0, "border control held nothing in 40 shipments")
        let co = try XCTUnwrap(e.state.company(id))
        let lost = loss(e, id) - lossBefore
        XCTAssertEqual(co.inventory, invBefore + ordered - lost, accuracy: 0.01)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        return (held, lost)
    }

    func testBorderHoldsAndBooksStayBalanced() throws {
        let r = try runShipments(cargo: .standard)
        XCTAssertGreaterThan(r.held, 0)
    }

    func testPerishableCargoSpoilsWhenHeld() throws {
        let r = try runShipments(cargo: .perishable)
        XCTAssertGreaterThan(r.lost, 0)
    }

    // MARK: Stock insurance

    func testUninsuredLossIsBookedDirectly() throws {
        var (e, id) = try engine(weeks: 4)
        e.update { s, _, _ in s.companies[s.companyIndex(id)!].inventory = 1_000_000 }
        let cash = try XCTUnwrap(e.state.company(id)).cash
        let lossBefore = loss(e, id)
        e.update { s, data, _ in
            let st = StockInsurance.settle(&s, companyID: id, amount: 200_000, fromInventory: true, data: data)
            XCTAssertEqual(st.paid, 0)
            XCTAssertEqual(st.net, 200_000)
        }
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(co.inventory, 800_000)
        XCTAssertEqual(co.cash, cash)
        XCTAssertEqual(loss(e, id) - lossBefore, 200_000)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testInsuredLossPaysOutMinusExcess() throws {
        var (e, id) = try engine(weeks: 4)
        e.update { s, _, _ in
            s.companies[s.companyIndex(id)!].inventory = 1_000_000
            Advisers.togglePolicy(&s, companyID: id, product: StockInsurance.product)
        }
        XCTAssertTrue(StockInsurance.isInsured(try XCTUnwrap(e.state.company(id))))
        let cash = try XCTUnwrap(e.state.company(id)).cash
        let lossBefore = loss(e, id)
        var excess = 0.0
        e.update { s, data, _ in
            excess = StockInsurance.excess(World(state: s, data: data).currency(s.companies[s.companyIndex(id)!]))
            let st = StockInsurance.settle(&s, companyID: id, amount: 200_000, fromInventory: true, data: data)
            XCTAssertEqual(st.paid, 200_000 - excess)
        }
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(co.inventory, 800_000)
        XCTAssertEqual(co.cash, cash + 200_000 - excess, accuracy: 0.01)
        XCTAssertEqual(loss(e, id) - lossBefore, excess, accuracy: 0.01)
        // A loss smaller than the excess pays nothing.
        e.update { s, data, _ in
            let st = StockInsurance.settle(&s, companyID: id, amount: 10, fromInventory: true, data: data)
            XCTAssertEqual(st.paid, 0)
        }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testPremiumIsBookedAsInsuranceCost() throws {
        var (e, id) = try engine(weeks: 4)
        e.update { s, _, _ in
            s.companies[s.companyIndex(id)!].inventory = 2_000_000
            Advisers.togglePolicy(&s, companyID: id, product: StockInsurance.product)
        }
        let co0 = try XCTUnwrap(e.state.company(id))
        let premium = StockInsurance.weeklyPremium(co0)
        XCTAssertGreaterThan(premium, 0)
        let ins0 = co0.books.total["ins"] ?? 0
        e.update { s, data, _ in StockInsurance.weekly(&s, data: data) }
        let co1 = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(co0.cash - co1.cash, premium, accuracy: 0.01)
        XCTAssertEqual((co1.books.total["ins"] ?? 0) - ins0, premium, accuracy: 0.01)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        // Uninsured pays no premium.
        e.update { s, _, _ in Advisers.togglePolicy(&s, companyID: id, product: StockInsurance.product) }
        XCTAssertEqual(StockInsurance.weeklyPremium(try XCTUnwrap(e.state.company(id))), 0)
    }

    func testRandomStockLossesOnlyRollWhenSwitchedOnAndKeepBooksBalanced() throws {
        var (e, id) = try engine(weeks: 4)
        let lossBefore = loss(e, id)
        e.update { s, data, _ in
            for _ in 0..<400 { s.week += 1; s.companies[s.companyIndex(id)!].inventory = 1_000_000; StockInsurance.weekly(&s, data: data) }
        }
        XCTAssertEqual(loss(e, id), lossBefore, "events must not roll while switched off")
        e.update { s, data, _ in
            StockInsurance.setEventsOn(&s, true)
            for _ in 0..<3000 { s.week += 1; s.companies[s.companyIndex(id)!].inventory = 1_000_000; StockInsurance.weekly(&s, data: data) }
        }
        XCTAssertGreaterThan(loss(e, id), lossBefore, "no fire, water damage or theft in 3000 weeks")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }
}
