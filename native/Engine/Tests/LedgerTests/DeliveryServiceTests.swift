import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Delivery as a service: a restaurant, cafe, kiosk or grocery that offers its delivery add-on needs couriers (an outside courier, or one of
/// your own courier companies). The add-on only brings customers for the orders that actually get delivered, and the delivery is paid for.
final class DeliveryServiceTests: XCTestCase {
    private func deliveryOn(_ e: inout GameEngine, _ id: Int, on: Bool = true) {
        e.update { s, d, _ in XCTAssertEqual(SalesWays.setOn(&s, companyID: id, kind: "platform", on: on, data: d), .changed) }
    }

    /// Play until every given company has opened (documents and permits take weeks).
    private func openUp(_ e: inout GameEngine, _ ids: [Int]) {
        e.update { s, d, _ in
            for id in ids { guard let co = s.company(id), let bd = d.catalog[co.type] else { continue }
                for doc in Documents.needed(co, bd, World(state: s, data: d)) { _ = Documents.apply(doc, companyID: id, state: &s, data: d) } }
        }
        for _ in 0..<40 where ids.contains(where: { e.state.company($0)?.status != .open }) { ChainsTests.play(&e, days: 7) }
        for id in ids { XCTAssertEqual(e.state.company(id)?.status, .open, "company \(id) did not open: \(OpeningChecklist.items(e.state.company(id)!, e.data.catalog[e.state.company(id)!.type]!, World(state: e.state, data: e.data)).filter { !$0.isDone }.map { $0.title + $0.detail })") }
    }

    func testEveryShippingTradeBuysADeliveryServiceFromTheData() throws {
        let e = try ChainsTests.engine()
        let parcel = try XCTUnwrap(IntercompanySupply.kind("parcel"))
        let deliv = try XCTUnwrap(IntercompanySupply.deliveryKind)
        XCTAssertEqual(deliv.suppliers, ["courier"])
        for (id, bd) in e.data.catalog.trades where id != "courier" {
            // a trade whose equipment list has a delivery vehicle ships its goods; a trade with a delivery add-on sends orders to customers
            let ships = bd.equipment.contains { $0.name.lowercased().contains("delivery") }
            let apps = IntercompanySupply.deliveryWay(id, e.data.balance) != nil
            if ships { XCTAssertTrue(parcel.buyers[id] != nil || deliv.buyers[id] != nil, "\(id) ships but buys no delivery") }
            if apps { XCTAssertNotNil(deliv.buyers[id], "\(id) has a delivery add-on but no delivery input") }
        }
        for t in ["bakery", "hardware", "furniture", "webshop"] { XCTAssertNotNil(parcel.buyers[t], t) }
    }

    func testAddOnBringsCustomersOnlyForDeliveredOrdersAndPaysTheCourier() throws {
        var e = try ChainsTests.engine()
        let r = ChainsTests.start(&e, "cafe")
        let courier = ChainsTests.start(&e, "courier")
        ChainsTests.season(&e, r)
        let way = try XCTUnwrap(IntercompanySupply.deliveryWay("cafe", e.data.balance))
        let rel = try XCTUnwrap(way.options["rel"])
        XCTAssertLessThan(rel, 1)
        // no add-on: no delivery cost, nothing stored
        openUp(&e, [r, courier])
        XCTAssertNil(e.state.company(r)?.raw["dlvRev"])
        deliveryOn(&e, r)
        // outside courier: reliability is the data's
        XCTAssertEqual(IntercompanySupply.deliveryFill(e.state, buyer: e.state.company(r)!, way: way), rel, accuracy: 1e-12)
        ChainsTests.play(&e, days: 14)
        let rev = try XCTUnwrap(e.state.company(r)).num("dlvRev")
        XCTAssertGreaterThan(rev, 0, "delivery orders are tracked once the add-on sells \(e.state.company(r)!.status) \(e.state.company(r)!.lastWeekRevenue) \(e.state.company(r)!.value("lastW")) \(e.state.company(r)!.value("sw33"))")
        let inputs = e.supplierInputs(companyID: r)
        let dl = try XCTUnwrap(inputs.first { $0.id == "deliv" }, "the Suppliers section lists delivery")
        XCTAssertEqual(dl.current?.kind, .outside)
        XCTAssertGreaterThan(dl.yearlySpend ?? 0, 0)
        // an own courier company supplies it
        XCTAssertEqual(e.switchSupplier(companyID: r, input: "deliv", to: .ownCompany(courier, mode: "mkt")), .ok)
        let cash0 = e.state.company(courier)!.cash
        ChainsTests.play(&e, days: 28)
        let link = try XCTUnwrap(IntercompanySupply.link(e.state, buyer: r, kind: "deliv"))
        XCTAssertGreaterThan(link.lastSpend, 0)
        let fill = IntercompanySupply.deliveryFill(e.state, buyer: e.state.company(r)!, way: way)
        XCTAssertGreaterThanOrEqual(fill, rel)
        XCTAssertLessThanOrEqual(fill, 1)
        XCTAssertNotEqual(e.state.company(courier)!.cash, cash0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        // switching the add-on off ends the demand and the cost
        deliveryOn(&e, r, on: false)
        ChainsTests.play(&e, days: 14)
        XCTAssertNil(e.state.company(r)?.raw["dlvRev"])
        let after = try XCTUnwrap(e.supplierInputs(companyID: r).first { $0.id == "deliv" })
        XCTAssertEqual(after.yearlySpend ?? 0, 0, accuracy: 1e-9)
    }

    func testDeliveryDemandFollowsSupply() throws {
        var e = try ChainsTests.engine()
        let r = ChainsTests.start(&e, "cafe")
        let courier = ChainsTests.start(&e, "courier")
        openUp(&e, [r, courier])
        deliveryOn(&e, r)
        let way = try XCTUnwrap(IntercompanySupply.deliveryWay("cafe", e.data.balance))
        // a courier that delivers nothing last week brings only the outside share; a perfect one brings the whole lift
        XCTAssertEqual(e.switchSupplier(companyID: r, input: "deliv", to: .ownCompany(courier, mode: "mkt")), .ok)
        func setShare(_ f: Double) {
            e.update { s, _, _ in
                var L = s.rest["l27"]!.array
                L[0]["last"] = .object(["x": 1, "f": .number(f), "pf": 1, "w": .number(Double(s.week))])
                s.rest["l27"] = .array(L)
            }
        }
        setShare(0)
        XCTAssertEqual(IntercompanySupply.deliveryFill(e.state, buyer: e.state.company(r)!, way: way), way.options["rel"]!, accuracy: 1e-12)
        setShare(1)
        XCTAssertEqual(IntercompanySupply.deliveryFill(e.state, buyer: e.state.company(r)!, way: way), 1, accuracy: 1e-12)
        // the courier closes: the link ends and the outside courier takes over
        e.update { s, _, _ in s.companies[s.companyIndex(courier)!].status = .closed }
        XCTAssertEqual(IntercompanySupply.deliveryFill(e.state, buyer: e.state.company(r)!, way: way), way.options["rel"]!, accuracy: 1e-12)
    }

    func testOneYearManySeedsBooksBalanceAndNothingGrowsWithoutBound() throws {
        for seed in [3, 11, 29] {
            var e = try ChainsTests.engine("NO", seed: seed)
            let trades = ["restaurant", "cafe", "grocery", "kiosk"]
            let buyers = trades.map { ChainsTests.start(&e, $0) }
            let courier = ChainsTests.start(&e, "courier")
            openUp(&e, buyers + [courier])
            for b in buyers { deliveryOn(&e, b) }
            _ = e.switchSupplier(companyID: buyers[0], input: "deliv", to: .ownCompany(courier, mode: "c10"))
            _ = e.switchSupplier(companyID: buyers[1], input: "deliv", to: .ownCompany(courier, mode: "mkt"))
            ChainsTests.play(&e, days: 364)
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "seed \(seed): \(Ledger.gaps(e.state))")
            for b in buyers {
                guard let c = e.state.company(b), c.status.isLive else { continue }
                let rev = c.num("dlvRev")
                XCTAssertTrue(rev.isFinite && rev >= 0 && rev < c.lastWeekRevenue + 1, "seed \(seed) \(c.type): \(rev) of \(c.lastWeekRevenue)")
            }
            XCTAssertLessThan((e.state.rest["l27"]?.array.count ?? 0), 10)
        }
    }
}
