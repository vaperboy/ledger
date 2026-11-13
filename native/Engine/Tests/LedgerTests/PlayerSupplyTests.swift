import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Events
import Simulation

final class PlayerSupplyTests: XCTestCase {
    private func listing(_ id: String, trade: String = "wholesale", line: String = "food", price: Int = 1, quality: Int = 1, country: String = "UK", companyID: Int? = nil) -> SupplyListing {
        SupplyListing(id: id, ownerID: "owner-\(id)", ownerName: "Name \(id)", profileCode: "P-\(id)", companyName: "Co \(id)", companyID: companyID, tradeID: trade, tradeName: trade.capitalized,
                      city: "Leeds", region: "North", lineID: line, lineName: "Stock", priceTier: price, qualityTier: quality, capacityPerWeek: 300, leadDays: 2, minOrder: 10, termsDays: 14,
                      linkKey: "key-\(id)", record: DeliveryRecord(weeksTrading: 20, ordersTotal: 40, ordersOnTime: 39, unitsPromised: 800, unitsDelivered: 790, cleanWeeks: 12, lifetimeUnits: 790),
                      country: country)
    }

    private func engine(trade: String = "grocery") throws -> (GameEngine, Int) {
        var e = try ChainsTests.engine("UK", seed: 777)
        let id = ChainsTests.start(&e, trade)
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].status = .open
            s.companies[i].set("lastW", .object(["cogs": .number(4000), "units": .number(100), "cap": .number(200)]))
        }
        return (e, id)
    }

    private func contract(_ id: String, buyer: Int, line: String = "food", listing l: String, units: Int = 20) -> SupplyContract {
        SupplyContract(id: id, buyerCompanyID: buyer, lineID: line, listingID: l, supplierOwnerID: "owner-\(l)", supplierName: "Name \(l)", unitsPerWeek: units, startDay: 0)
    }

    func testFarCheapSupplierLosesToANearerOne() {
        // Standard goods: perishable food would fly and arrive the same week.
        let near = listing("near", trade: "workshop", line: "wares", price: 1, country: "DE")
        let far = listing("far", trade: "workshop", line: "wares", price: 0, country: "AU")
        let rows = SupplyLanded.compare([far, near], buyerCountry: "UK", marketUnitPrice: 100, units: 20, priceLevel: 1)
        XCTAssertEqual(rows.map { $0.id }, ["near", "far"])
        let f = rows[1]
        XCTAssertLessThan(f.unitPrice, rows[0].unitPrice, "the far one is cheaper before freight")
        XCTAssertGreaterThan(f.freightPerUnit, 0)
        XCTAssertGreaterThan(f.customsPerUnit, 0)
        XCTAssertEqual(f.landedPerUnit, f.unitPrice + f.freightPerUnit + f.customsPerUnit, accuracy: 0.0001)
        XCTAssertGreaterThan(f.transitWeeks, rows[0].transitWeeks)
        XCTAssertTrue(f.crossesBorder)
    }

    func testServicesAreNotFreighted() {
        let svc = listing("s", trade: "webdev", line: "software", country: "AU")
        let r = SupplyLanded.compare([svc], buyerCountry: "UK", marketUnitPrice: 100, units: 10, priceLevel: 1)[0]
        XCTAssertEqual(r.freightPerUnit, 0)
        XCTAssertEqual(r.customsPerUnit, 0)
        XCTAssertNil(r.mode)
        XCTAssertEqual(r.landedFactor, 1)
        XCTAssertEqual(SupplyLanded.transitText(r), "No freight")
    }

    func testAnUnknownCountryIsLocalAndBadInputIsSafe() {
        let l = listing("x", country: "")
        let r = SupplyLanded.compare([l], buyerCountry: "UK", marketUnitPrice: 100, units: 20, priceLevel: 1)[0]
        XCTAssertFalse(r.crossesBorder)
        XCTAssertEqual(r.customsPerUnit, 0)
        let none = SupplyLanded.compare([l], buyerCountry: "UK", marketUnitPrice: .nan, units: 0, priceLevel: 1)[0]
        XCTAssertEqual(none.landedPerUnit, 0)
    }

    func testEveryCatalogueLineHasABuyer() throws {
        let e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 11)
        for (trade, lines) in SupplyMarketCatalogue.supplies {
            for line in lines {
                let buyers = e.data.catalog.trades.filter { SupplyNeeds.uses(buyerTrade: $0.key, buyerFamily: $0.value.family, line: line, supplierTrade: trade) }
                XCTAssertFalse(buyers.isEmpty, "\(trade) supplies \(line) to nobody")
            }
        }
    }

    func testNeedsFollowTheTrade() {
        XCTAssertTrue(SupplyNeeds.uses(buyerTrade: "cafe", buyerFamily: "venue", line: "bread", supplierTrade: "bakery"))
        XCTAssertTrue(SupplyNeeds.uses(buyerTrade: "cafe", buyerFamily: "venue", line: "food", supplierTrade: "wholesale"))
        XCTAssertFalse(SupplyNeeds.uses(buyerTrade: "carrepair", buyerFamily: "svc", line: "bread", supplierTrade: "bakery"))
        XCTAssertFalse(SupplyNeeds.uses(buyerTrade: "cafe", buyerFamily: "venue", line: "food", supplierTrade: "carrepair"))
        XCTAssertTrue(SupplyNeeds.uses(buyerTrade: "taxi", buyerFamily: "logi", line: "fuel", supplierTrade: "fuelstation"))
        XCTAssertFalse(SupplyNeeds.uses(buyerTrade: "taxi", buyerFamily: "logi", line: "fuel", supplierTrade: "oilgas"), "taxis fill up at filling stations")
        XCTAssertTrue(SupplyNeeds.uses(buyerTrade: "shipping", buyerFamily: "logi", line: "fuel", supplierTrade: "oilgas"), "ships buy bulk fuel")
        XCTAssertFalse(SupplyNeeds.uses(buyerTrade: "shipping", buyerFamily: "logi", line: "fuel", supplierTrade: "fuelstation"))
        XCTAssertFalse(SupplyNeeds.uses(buyerTrade: "cafe", buyerFamily: "venue", line: "fuel", supplierTrade: "fuelstation"))
        XCTAssertFalse(SupplyMarketCatalogue.supplies["courier"]?.contains("fuel") ?? false, "a courier does not sell fuel")
        let kept = SupplyNeeds.relevant([listing("a"), listing("b", trade: "carrepair", line: "carserv")], buyerTrade: "grocery", buyerFamily: "retail")
        XCTAssertEqual(kept.map { $0.id }, ["a"])
    }

    func testAContractPricesTheLineAndEndingGoesBack() throws {
        var (e, id) = try engine()
        let base = try XCTUnwrap(e.goodsCostFactor(companyID: id))
        XCTAssertTrue(e.signPlayerSupplier(contract: contract("C1", buyer: id, listing: "cheap"), listing: listing("cheap", price: 0), weeklyMarketSpend: 100_000))
        let cheap = try XCTUnwrap(e.goodsCostFactor(companyID: id))
        XCTAssertTrue(e.signPlayerSupplier(contract: contract("C2", buyer: id, listing: "dear"), listing: listing("dear", price: 2), weeklyMarketSpend: 100_000))
        let dear = try XCTUnwrap(e.goodsCostFactor(companyID: id))
        XCTAssertLessThan(cheap, dear)
        XCTAssertEqual(e.playerSupplyContracts.count, 1, "one contract per line")
        e.endPlayerSupplier(companyID: id, lineID: "food")
        XCTAssertEqual(try XCTUnwrap(e.goodsCostFactor(companyID: id)), base, accuracy: 1e-9)
        XCTAssertTrue(e.playerSupplyContracts.isEmpty)
    }

    func testFreightFromAFarCountryRaisesTheCost() throws {
        var (e, id) = try engine()
        XCTAssertTrue(e.signPlayerSupplier(contract: contract("C1", buyer: id, listing: "home"), listing: listing("home", country: "UK"), weeklyMarketSpend: 100_000))
        let home = try XCTUnwrap(e.goodsCostFactor(companyID: id))
        XCTAssertTrue(e.signPlayerSupplier(contract: contract("C2", buyer: id, listing: "far"), listing: listing("far", country: "AU"), weeklyMarketSpend: 100_000))
        let far = try XCTUnwrap(e.goodsCostFactor(companyID: id))
        XCTAssertGreaterThan(far, home)
    }

    func testTheTradeMustNeedWhatIsOffered() throws {
        var (e, id) = try engine()
        let wrong = listing("w", trade: "carrepair", line: "food")
        XCTAssertFalse(e.signPlayerSupplier(contract: contract("C1", buyer: id, listing: "w"), listing: wrong, weeklyMarketSpend: 100_000))
        XCTAssertTrue(e.playerSupplyContracts.isEmpty)
    }

    func testAShortDeliveryCostsCustomersAndTellsTheBuyer() throws {
        var (e, id) = try engine()
        XCTAssertTrue(e.signPlayerSupplier(contract: contract("C1", buyer: id, listing: "f"), listing: listing("f"), weeklyMarketSpend: 100_000))
        let co = try XCTUnwrap(e.state.company(id))
        let bd = try XCTUnwrap(e.data.catalog[co.type])
        let base = SupplyCatalogue.availability(e.state, co, bd, week: e.state.week, data: e.data)
        e.reportShortDelivery(listingID: "f")
        XCTAssertLessThan(SupplyCatalogue.availability(e.state, co, bd, week: e.state.week, data: e.data), base)
        XCTAssertTrue(e.state.inbox.contains { $0.companyID == id && $0.title == "A delivery arrived short" })
        e.endPlayerSupplier(companyID: id, lineID: "food")
        XCTAssertEqual(SupplyCatalogue.availability(e.state, co, bd, week: e.state.week, data: e.data), base)
    }

    func testAContractEndsWithItsCompany() throws {
        var (e, id) = try engine()
        XCTAssertTrue(e.signPlayerSupplier(contract: contract("C1", buyer: id, listing: "f"), listing: listing("f"), weeklyMarketSpend: 100_000))
        e.update { s, _, _ in
            if let i = s.companyIndex(id) { s.companies[i].status = .bust }
            PlayerSupply.weekly(&s)
        }
        XCTAssertTrue(e.playerSupplyContracts.isEmpty)
    }

    func testListingsAndOrdersSurviveTheSave() throws {
        var (e, id) = try engine(trade: "bakery")
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].set("lastW", .object(["units": .number(0)])) } }
        var l = listing("M1", trade: "bakery", companyID: id)
        l.capacityPerWeek = 1
        l.record.deliveredTrend = 1.5
        l.expiresDay = 99
        l.paused = true
        let order = SupplyOrderRecord(id: "o1", listingID: "M1", buyerName: "Ana Holt", units: 20, delivered: 18, late: true, day: 40, revenue: 1234)
        e.savePlayerListings([l], orders: ["M1": [order]])
        XCTAssertEqual(e.playerSupplyListings, [l])
        XCTAssertEqual(e.playerSupplyOrders["M1"], [order])
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .bust } }
        XCTAssertTrue(e.playerSupplyListings.isEmpty, "a listing of a company that is gone is not kept")
    }

    func testEndingAPlayerSupplyCostsTwoWeeksOfTheOrderForEitherSide() throws {
        var (e, id) = try engine()
        XCTAssertTrue(e.signPlayerSupplier(contract: contract("C1", buyer: id, listing: "f", units: 40), listing: listing("f", price: 1), weeklyMarketSpend: 1_000))
        let fee = e.playerSupplyCancelFee(companyID: id, lineID: "food")
        XCTAssertGreaterThan(fee, 0)
        let signed = try XCTUnwrap(PlayerSupply.contract(e.state, buyer: id, line: "food"))
        XCTAssertEqual(fee, signed.orderValue * 2, accuracy: 1e-9)
        XCTAssertGreaterThan(signed.orderValue, 0)
        let before = try XCTUnwrap(e.state.company(id)).cash
        XCTAssertEqual(e.cancelPlayerSupplier(companyID: id, lineID: "food"), .applied)
        XCTAssertEqual(before - (try XCTUnwrap(e.state.company(id)).cash), fee, accuracy: 1)
        XCTAssertTrue(e.playerSupplyContracts.isEmpty)
        XCTAssertEqual(e.cancelPlayerSupplier(companyID: id, lineID: "food"), .refused("There is no supplier to end."))
        XCTAssertTrue(e.signPlayerSupplier(contract: contract("C2", buyer: id, listing: "g", units: 40), listing: listing("g", price: 1), weeklyMarketSpend: 1_000))
        let cash = try XCTUnwrap(e.state.company(id)).cash
        XCTAssertEqual(e.cancelPlayerSupplier(companyID: id, lineID: "food", bySupplier: true), .applied)
        XCTAssertGreaterThan(try XCTUnwrap(e.state.company(id)).cash, cash)
        XCTAssertTrue(e.state.feedLines.contains { $0.companyID == id && $0.text == "Supplier ended the supply" })
    }

    func testAListingCannotPromiseMoreThanTheCompanyCanSupply() throws {
        var (e, id) = try engine(trade: "bakery")
        let room = try XCTUnwrap(e.physicalSupplyCapacity(companyID: id))
        var big = listing("B1", trade: "bakery", companyID: id)
        big.capacityPerWeek = room + 500
        e.savePlayerListings([big], orders: [:])
        XCTAssertEqual(e.playerSupplyListings.first?.capacityPerWeek, room)
        var small = big
        small.capacityPerWeek = 0
        e.savePlayerListings([small], orders: [:])
        XCTAssertEqual(e.playerSupplyListings.first?.capacityPerWeek, 0)
    }

    func testAnOrderTravelsAndShowsInTransit() throws {
        var (e, id) = try engine()
        let basis = try XCTUnwrap(e.stockOrderBasis(companyID: id))
        XCTAssertGreaterThan(basis.unitCost, 0)
        let far = listing("far", country: "AU")
        let result = e.orderFromSupplier(companyID: id, listing: far, units: 50)
        guard case .ok(_, let ship) = result else { return XCTFail("\(result)") }
        XCTAssertNotNil(ship)
        let rows = e.shipmentsOnTheWay(companyID: id)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].supplier, "Name far")
        XCTAssertEqual(rows[0].from, "AU")
        XCTAssertTrue(rows[0].crossesBorder)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        XCTAssertEqual(e.orderFromSupplier(companyID: id, listing: listing("s", trade: "webdev", line: "software"), units: 5), .badOrder)
    }

    func testDeliveryTroubleIsInTheDaysReport() throws {
        var (e, id) = try engine()
        e.update { s, _, _ in Shipments.tell(&s, companyID: id, title: "Delivery held at the border", body: "Held for a week.") }
        // Delivery news goes to the day's report, not the inbox.
        let m = try XCTUnwrap(e.state.feedLines.first { $0.text == "Delivery held at the border" })
        XCTAssertEqual(m.companyID, id)
        XCTAssertEqual(m.tone, "bad")
    }

    func testStockPolicyIsOnTheInsuranceScreenAndToggles() throws {
        var (e, id) = try engine()
        let off = try XCTUnwrap(e.coverageOverview(companyID: id)?.policies.first { $0.id == StockInsurance.product })
        XCTAssertFalse(off.isOn)
        XCTAssertGreaterThanOrEqual(off.weeklyPremium, 0)
        XCTAssertEqual(e.toggleInsurancePolicy(companyID: id, product: StockInsurance.product), .done)
        let on = try XCTUnwrap(e.coverageOverview(companyID: id)?.policies.first { $0.id == StockInsurance.product })
        XCTAssertTrue(on.isOn)
        XCTAssertTrue(StockInsurance.isInsured(try XCTUnwrap(e.state.company(id))))
        XCTAssertEqual(e.toggleInsurancePolicy(companyID: id, product: StockInsurance.product), .done)
        XCTAssertFalse(StockInsurance.isInsured(try XCTUnwrap(e.state.company(id))))
    }
}
