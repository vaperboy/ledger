import XCTest
import GameCore
import Finance
import Simulation
@testable import Businesses

final class SupplyMarketTests: XCTestCase {
    private func listing(_ id: String, owner: String = "o", tier: Int = 1,
                         record: DeliveryRecord = DeliveryRecord(weeksTrading: 20, ordersTotal: 60, ordersOnTime: 58, unitsPromised: 1000, unitsDelivered: 990, cleanWeeks: 12, lifetimeUnits: 990),
                         link: String? = nil, cap: Int = 200) -> SupplyListing {
        SupplyListing(id: id, ownerID: owner, ownerName: "Name \(id)", profileCode: "P-\(id)", companyName: "Co \(id)", tradeID: "bakery", tradeName: "Bakery", city: "Leeds", region: "North",
                      lineID: "goods", lineName: "Stock and ingredients", priceTier: tier, qualityTier: 1, capacityPerWeek: cap, leadDays: 2, minOrder: 10, termsDays: 14,
                      linkKey: link ?? "link-\(id)", record: record)
    }

    func testRecordWords() {
        XCTAssertEqual(SupplyRecordRules.word(DeliveryRecord(weeksTrading: 2, ordersTotal: 3)), .unproven)
        XCTAssertEqual(SupplyRecordRules.word(DeliveryRecord(weeksTrading: 20, ordersTotal: 60, ordersOnTime: 58, unitsPromised: 1000, unitsDelivered: 990)), .reliable)
        XCTAssertEqual(SupplyRecordRules.word(DeliveryRecord(weeksTrading: 20, ordersTotal: 60, ordersOnTime: 50, unitsPromised: 1000, unitsDelivered: 900, complaints: 2)), .mostlyReliable)
        XCTAssertEqual(SupplyRecordRules.word(DeliveryRecord(weeksTrading: 20, ordersTotal: 60, ordersOnTime: 35, unitsPromised: 1000, unitsDelivered: 700, complaints: 9, disputes: 3)), .struggling)
        let steady = DeliveryRecord(weeksTrading: 20, ordersTotal: 20, ordersOnTime: 20, unitsPromised: 400, unitsDelivered: 400)
        var changed = steady
        changed.priceChanges = 4
        XCTAssertGreaterThan(SupplyRecordRules.score(steady), SupplyRecordRules.score(changed))
    }

    func testApplyingAWeekMovesTheTrend() throws {
        let r = DeliveryRecord(weeksTrading: 10, ordersTotal: 30, ordersOnTime: 30, unitsPromised: 300, unitsDelivered: 300, cleanWeeks: 10)
        let bad = SupplyRecordRules.applying(r, promised: 100, delivered: 60, orders: 3, late: 1, complaints: 1)
        XCTAssertEqual(bad.cleanWeeks, 0)
        XCTAssertLessThan(try XCTUnwrap(bad.deliveredTrend), 0)
        XCTAssertLessThan(try XCTUnwrap(bad.onTimeTrend), 0)
        let good = SupplyRecordRules.applying(r, promised: 100, delivered: 100, orders: 3, late: 0, complaints: 0)
        XCTAssertEqual(good.cleanWeeks, 11)
        XCTAssertEqual(good.weeksTrading, 11)
    }

    func testNewSupplierCapRisesWithACleanRecordAndLifts() {
        var r = DeliveryRecord(weeksTrading: 1)
        XCTAssertEqual(SupplyGuards.newSupplierCap(r), 20)
        r.cleanWeeks = 5
        XCTAssertEqual(SupplyGuards.newSupplierCap(r), 80)
        r.cleanWeeks = 10
        XCTAssertNil(SupplyGuards.newSupplierCap(r))
        r.disputes = 1
        XCTAssertNotNil(SupplyGuards.newSupplierCap(r), "a dispute keeps the limit")
        var l = listing("n", record: DeliveryRecord(weeksTrading: 1), cap: 500)
        XCTAssertEqual(SupplyGuards.effectiveCapacity(l), 20)
        XCTAssertEqual(SupplyGuards.limitText(l), "Limit while new: 20 units/week")
        l.record.cleanWeeks = 10
        XCTAssertEqual(SupplyGuards.effectiveCapacity(l), 500)
        XCTAssertNil(SupplyGuards.limitText(l))
    }

    func testLinkedAccountsAndOtherGuards() {
        let l = listing("a", link: "owner-1")
        XCTAssertEqual(SupplyGuards.availability(l, buyerLinkKeys: ["owner-1"], units: 50, today: 10), .linkedAccount)
        XCTAssertEqual(SupplyGuards.availability(l, buyerLinkKeys: ["owner-1"], units: 50, today: 10).message, "Not available: linked account")
        XCTAssertEqual(SupplyGuards.availability(l, buyerLinkKeys: ["other"], units: 50, today: 10), .available)
        XCTAssertEqual(SupplyGuards.availability(l, buyerLinkKeys: [], units: 5, today: 10), .belowMinimum(10))
        var gone = l
        gone.expiresDay = 9
        XCTAssertNotEqual(SupplyGuards.availability(gone, buyerLinkKeys: [], units: 50, today: 10), .available)
        var full = l
        full.committedUnits = 200
        XCTAssertEqual(SupplyGuards.availability(full, buyerLinkKeys: [], units: 50, today: 10), .full)
        var paused = l
        paused.paused = true
        XCTAssertNotEqual(SupplyGuards.availability(paused, buyerLinkKeys: [], units: 50, today: 10), .available)
    }

    func testAccountDeletionWaitsForOpenContracts() {
        XCTAssertFalse(SupplyGuards.accountDeletion(openContracts: 2).allowed)
        XCTAssertNotNil(SupplyGuards.accountDeletion(openContracts: 2).reason)
        XCTAssertTrue(SupplyGuards.accountDeletion(openContracts: 0).allowed)
    }

    func testRandomPoolIsFairAndGivesNewcomersAChance() {
        var all: [SupplyListing] = (0..<8).map { listing("v\($0)") }
        let newcomer = listing("new", record: DeliveryRecord(weeksTrading: 1, ordersTotal: 1, cleanWeeks: 1))
        let pricey = listing("pricey", tier: 2)
        let weak = listing("weak", record: DeliveryRecord(weeksTrading: 20, ordersTotal: 60, ordersOnTime: 30, unitsPromised: 1000, unitsDelivered: 600, complaints: 9, disputes: 3))
        let linked = listing("linked", link: "mine")
        all += [newcomer, pricey, weak, linked]
        let pool = SupplyChoice.randomPool(all, units: 50, buyerLinkKeys: ["mine"], today: 1)
        let ids = Set(pool.map { $0.id })
        XCTAssertTrue(ids.contains("new"))
        XCTAssertFalse(ids.contains("pricey"), "not fairly priced")
        XCTAssertFalse(ids.contains("weak"), "struggling")
        XCTAssertFalse(ids.contains("linked"), "linked account")
        var hits: [String: Int] = [:]
        for n in 0..<2000 { if let d = SupplyChoice.draw(pool, seed: "b:\(n)") { hits[d.id, default: 0] += 1 } }
        XCTAssertEqual(Set(hits.keys), ids)
        let expected = 2000.0 / Double(pool.count)
        XCTAssertGreaterThan(Double(hits["new"] ?? 0), expected * 0.7)
        XCTAssertLessThan(Double(hits.values.max() ?? 0), expected * 1.8)
        XCTAssertEqual(SupplyChoice.draw(pool, seed: "x")?.id, SupplyChoice.draw(pool, seed: "x")?.id)
        let first = SupplyChoice.draw(pool, seed: "x")!
        XCTAssertNotEqual(SupplyChoice.draw(pool, seed: "x", excluding: [first.id])?.id, first.id)
        XCTAssertNil(SupplyChoice.draw([], seed: "x"))
    }

    func testBusyListingsAreDrawnLessOften() {
        var busy = listing("busy")
        busy.committedUnits = 190
        let idle = listing("idle")
        XCTAssertGreaterThan(SupplyChoice.weight(idle), SupplyChoice.weight(busy))
    }

    func testWellKnownPutsProvenRecordsAndVolumeFirst() {
        let big = listing("big", record: DeliveryRecord(weeksTrading: 40, ordersTotal: 200, ordersOnTime: 195, unitsPromised: 5000, unitsDelivered: 4950, lifetimeUnits: 4950))
        let small = listing("small")
        let fresh = listing("fresh", record: DeliveryRecord(weeksTrading: 1))
        let top = SupplyChoice.wellKnown([fresh, small, big], units: 20, buyerLinkKeys: [], today: 1)
        XCTAssertEqual(top.map { $0.id }, ["big", "small", "fresh"])
    }

    func testSupplierStoppingEndsContractsAtOnceAndFallsBack() {
        let c1 = SupplyContract(id: "c1", buyerCompanyID: 1, lineID: "goods", listingID: "L1", supplierOwnerID: "ownerA", supplierName: "Ann Baker", unitsPerWeek: 50, startDay: 0)
        let c2 = SupplyContract(id: "c2", buyerCompanyID: 2, lineID: "pack", listingID: "L2", supplierOwnerID: "ownerB", supplierName: "Bo Pack", unitsPerWeek: 20, startDay: 0)
        let r = SupplyContracts.end([c1, c2], supplierOwnerID: "ownerA", reason: .bankrupt)
        XCTAssertEqual(r.kept, [c2])
        XCTAssertEqual(r.fallbacks.count, 1)
        XCTAssertEqual(r.fallbacks[0].title, "Your supplier stopped supplying")
        XCTAssertTrue(r.fallbacks[0].body.contains("market supplier at market price"))
        XCTAssertTrue(r.fallbacks[0].body.contains("went bankrupt"))
        XCTAssertEqual(SupplyContracts.end([c1, c2], listingID: "L2", reason: .stopped).kept, [c1])
    }

    func testCatalogueOnlyAndTradeRules() {
        XCTAssertFalse(SupplyMarketCatalogue.supplyableLines(tradeID: "bakery").isEmpty)
        XCTAssertTrue(SupplyMarketCatalogue.supplyableLines(tradeID: "hold").isEmpty)
        for (trade, lines) in SupplyMarketCatalogue.supplies {
            for l in lines { XCTAssertNotNil(SupplyMarketCatalogue.line(l), "\(trade) supplies \(l), which is not in the catalogue") }
        }
        XCTAssertGreaterThanOrEqual(SupplyMarketCatalogue.supplierTrades.count, 12)
    }

    func testASaleToAnotherPlayerBooksBalancedAndNeedsCapacity() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 4242)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 160_000_000, why: "Test funds")
            guard case .success(let i) = CompanySetup.create(&s, tradeID: "bakery", cityID: s.player.cityID, data: data, context: ctx) else { return }
            let est = CompanySetup.estimate(tradeID: "bakery", cityID: s.player.cityID, size: 1, state: s, data: data)
            _ = Payments.injectCash(&s, companyID: i, amount: (est?.total ?? 1_000_000) * 1.6 + 3_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: i, data: data)
            id = i
        }
        for _ in 0..<(8 * 7) { e.nextDay() }
        let co = try XCTUnwrap(e.state.company(id))
        let bd = try XCTUnwrap(e.data.catalog[co.type])
        var fresh = co
        fresh.set("lastW", .object([:]))
        XCTAssertEqual(SupplyMarketBooks.capacity(fresh, bd: bd).maxUnits, 0)
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].set("lastW", .object(["rev": 50_000, "cap": 400]))
        }
        let cap = SupplyMarketBooks.capacity(try XCTUnwrap(e.state.company(id)), bd: bd)
        XCTAssertEqual(cap.maxUnits, 200)
        let unit = SupplyMarketBooks.unitValue(try XCTUnwrap(e.state.company(id)))
        XCTAssertEqual(unit, 75, accuracy: 0.01)

        let cash0 = try XCTUnwrap(e.state.company(id)).cash
        var revenue = 0.0
        e.update { s, _, _ in revenue = SupplyMarketBooks.bookSaleToPlayer(&s, supplierCompanyID: id, units: 40, unitPrice: unit, unitCost: unit * 0.6) }
        XCTAssertEqual(revenue, 3000, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).cash - cash0, 3000 - 1800, accuracy: 1.01)
        e.update { s, _, _ in
            SupplyMarketBooks.bookPurchaseDifference(&s, buyerCompanyID: id, saving: 500)
            SupplyMarketBooks.bookPurchaseDifference(&s, buyerCompanyID: id, saving: -200)
        }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")

        let mails = e.state.inbox.count
        let f = SupplyFallback(contract: SupplyContract(id: "c", buyerCompanyID: id, lineID: "goods", listingID: "L", supplierOwnerID: "o", supplierName: "Ann", unitsPerWeek: 10, startDay: 0), reason: .stopped)
        e.update { s, _, _ in SupplyMarketBooks.tellBuyer(&s, fallback: f) }
        XCTAssertEqual(e.state.inbox.count, mails + 1)
        XCTAssertEqual(e.state.inbox.first?.title, "Your supplier stopped supplying")
    }
}
