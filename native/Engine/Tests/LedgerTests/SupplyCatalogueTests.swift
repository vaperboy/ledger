import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// What each trade buys from suppliers, and how the choice of supplier reaches the books.
final class SupplyCatalogueTests: XCTestCase {
    private func open(_ trade: String, seed: Int = 11) throws -> (GameEngine, Int) {
        var e = try ChainsTests.engine("NO", seed: seed)
        let id = ChainsTests.start(&e, trade)
        ChainsTests.season(&e, id)
        // The opening checklist is another subject: open the doors and give the company staff-free trading cash.
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].status = .open
            _ = Payments.injectCash(&s, companyID: id, amount: 2_000_000)
        }
        ChainsTests.play(&e, days: 5 * 7)
        return (e, id)
    }

    private func line(_ e: GameEngine, _ id: Int, _ line: String) throws -> SupplyRow {
        let rows = e.supplyLines(companyID: id).flatMap { $0.rows }
        return try XCTUnwrap(rows.first { $0.id == line }, "no \(line) in \(rows.map { $0.id })")
    }

    // MARK: The lists

    func testEveryTradeHasASensibleList() throws {
        let (e, id) = try open("cafe")
        let base = try XCTUnwrap(e.state.company(id))
        var none: [String] = []
        for bd in e.data.catalog.all {
            var co = base
            co.type = bd.id
            let lines = SupplyCatalogue.lines(co, bd)
            if lines.isEmpty { none.append(bd.id) }
            XCTAssertEqual(Set(lines.map { $0.id }).count, lines.count, "\(bd.id) repeats a line")
            let cogs = lines.filter { $0.isCogs }.reduce(0) { $0 + $1.share }
            XCTAssertTrue(cogs == 0 || abs(cogs - 1) < 0.001 || lines.contains { $0.id == "goods" }, "\(bd.id) cost-of-sales shares add to \(cogs)")
            XCTAssertLessThan(lines.filter { !$0.isCogs }.reduce(0) { $0 + $1.share }, 0.95, "\(bd.id) overhead shares")
        }
        XCTAssertTrue(none.allSatisfy { $0 == "hold" }, "only a holding company buys nothing: \(none)")
        XCTAssertNotNil(e.data.catalog["hold"])
    }

    func testGymBuysCleaningLaundryUtilitiesPartsAndShopStock() throws {
        let (e, id) = try open("gym")
        let titles = e.supplyLines(companyID: id).flatMap { $0.rows }.map { $0.title }
        for want in ["Drinks, snacks and protein stock", "Cleaning and hygiene supplies", "Towels and laundry", "Electricity and water", "Machine servicing and parts", "Booking and access software"] {
            XCTAssertTrue(titles.contains(want), "gym lacks \(want): \(titles)")
        }
        let groups = e.supplyLines(companyID: id).map { $0.name }
        XCTAssertTrue(groups.contains("Linen and laundry") && groups.contains("Utilities"), "\(groups)")
        let laundry = try line(e, id, "laundry")
        XCTAssertGreaterThanOrEqual(laundry.offers.count, 2)
        XCTAssertEqual(laundry.offers.filter { $0.isCurrent }.count, 1)
    }

    func testServiceTradesAndVenuesShowLists() throws {
        for trade in ["barber", "dental", "law", "hotel", "plumber", "taxi", "bank", "resrent"] {
            let (e, id) = try open(trade)
            XCTAssertFalse(e.supplyLines(companyID: id).isEmpty, "\(trade) shows no suppliers")
            XCTAssertTrue(e.hasSupplyLines(companyID: id))
        }
    }

    // MARK: Choice reaches the books

    func testTierPriceAndQualityOfAFactoryAndACafe() throws {
        for trade in ["factory", "cafe"] {
            var (e, id) = try open(trade)
            let pack = try line(e, id, "pack")
            let basic = try XCTUnwrap(pack.offers.first { $0.quality == "Basic" }, "\(trade) has no basic offer")
            let premium = try XCTUnwrap(pack.offers.first { $0.quality == "Top grade" })
            XCTAssertLessThan(basic.weekly ?? 1, premium.weekly ?? 0)
            XCTAssertEqual(e.chooseSupply(companyID: id, change: basic.change), .ok)
            let co = try XCTUnwrap(e.state.company(id)); let bd = try XCTUnwrap(e.data.catalog[co.type])
            let cheap = SupplyCatalogue.cogsEffect(e.state, co, bd, data: e.data)
            XCTAssertLessThan(cheap.m, 1); XCTAssertLessThan(cheap.q, 0)
            XCTAssertEqual(e.chooseSupply(companyID: id, change: premium.change), .ok)
            let dear = SupplyCatalogue.cogsEffect(e.state, try XCTUnwrap(e.state.company(id)), bd, data: e.data)
            XCTAssertGreaterThan(dear.m, 1); XCTAssertGreaterThan(dear.q, 0)
        }
    }

    func testCheaperLaundryCostsLessAWeekAndTheBooksBalance() throws {
        var (a, ida) = try open("gym")
        var (b, idb) = try open("gym")
        let offer = try XCTUnwrap(try line(b, idb, "laundry").offers.first { $0.quality == "Basic" })
        XCTAssertEqual(b.chooseSupply(companyID: idb, change: offer.change), .ok)
        ChainsTests.play(&a, days: 8 * 7); ChainsTests.play(&b, days: 8 * 7)
        let la = try line(a, ida, "laundry"), lb = try line(b, idb, "laundry")
        XCTAssertEqual(lb.current, offer.name)
        XCTAssertLessThan(lb.weekly ?? 1e9, (la.weekly ?? 0) * 0.97)
        XCTAssertTrue(Ledger.gaps(a.state).isEmpty, "\(Ledger.gaps(a.state))")
        XCTAssertTrue(Ledger.gaps(b.state).isEmpty, "\(Ledger.gaps(b.state))")
        ChainsTests.play(&a, days: 0); _ = ida; _ = idb
    }

    func testPayingOnDeliveryCostsCashNowAndAnInvoiceWaits() throws {
        var (market, idm) = try open("gym")
        var (cod, idc) = try open("gym")
        var (inv, idi) = try open("gym")
        let sw = try line(cod, idc, "software")
        let basic = try XCTUnwrap(sw.offers.first { $0.quality == "Basic" })
        let solid = try XCTUnwrap(sw.offers.first { $0.quality == "Solid" && !$0.name.hasPrefix("Market") })
        XCTAssertEqual(basic.terms, "Paid on delivery"); XCTAssertTrue(solid.terms.hasPrefix("Paid after"))
        cod.chooseSupply(companyID: idc, change: basic.change); inv.chooseSupply(companyID: idi, change: solid.change)
        for _ in 0..<7 { ChainsTests.play(&market, days: 1); ChainsTests.play(&cod, days: 1); ChainsTests.play(&inv, days: 1) }
        // paying on delivery moves cash out of the week; on invoice it is owed and booked as an expense
        let owedMarket = market.state.company(idm)?.payables["other"] ?? 0
        let owedInv = inv.state.company(idi)?.payables["other"] ?? 0
        XCTAssertGreaterThanOrEqual(owedInv, owedMarket - 1)
        for e in [market, cod, inv] { XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))") }
        ChainsTests.play(&cod, days: 35); ChainsTests.play(&inv, days: 35)
        for e in [cod, inv] { XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))") }
    }

    func testShortagesOnlyFromChosenSuppliersAndCutSales() throws {
        let (e, id) = try open("boutique")
        var s = e.state
        let co0 = try XCTUnwrap(s.company(id)); let bd = try XCTUnwrap(e.data.catalog[co0.type])
        for w in 0..<300 { XCTAssertEqual(SupplyCatalogue.availability(s, co0, bd, week: w, data: e.data), 1, "the market never misses") }
        // name the least reliable stock supplier
        let worst = try XCTUnwrap(e.supplierCandidates(companyID: id, scope: "goods").min { $0.rating < $1.rating })
        Suppliers.chooseGoodsVendor(&s, companyID: id, vendorID: worst.id)
        let co = try XCTUnwrap(s.company(id))
        let misses = (0..<300).filter { SupplyCatalogue.availability(s, co, bd, week: $0, data: e.data) < 1 }.count
        XCTAssertGreaterThan(misses, 0); XCTAssertLessThan(misses, 120)
        XCTAssertTrue((0..<300).allSatisfy { SupplyCatalogue.availability(s, co, bd, week: $0, data: e.data) >= 0.5 })
    }

    func testRowsCarryCostAgainstLastWeekAndWords() throws {
        let (e, id) = try open("cafe")
        for g in e.supplyLines(companyID: id) {
            for r in g.rows {
                XCTAssertFalse(r.current.isEmpty); XCTAssertFalse(r.quality.isEmpty); XCTAssertFalse(r.reliability.isEmpty)
                XCTAssertTrue(["Patchy", "Steady", "Dependable", "Not yet tested"].contains(r.reliability), r.reliability)
                XCTAssertTrue(["Basic", "Solid", "Top grade"].contains(r.quality), r.quality)
            }
        }
        let goods = try line(e, id, "goods")
        XCTAssertNotNil(goods.weekly); XCTAssertNotNil(goods.weeklyBefore)
    }

    func testOneRetailShopBuysAndBooksBalanceOverAQuarter() throws {
        var (e, id) = try open("boutique")
        let pack = try line(e, id, "pack")
        e.chooseSupply(companyID: id, change: try XCTUnwrap(pack.offers.first { $0.quality == "Top grade" }).change)
        ChainsTests.play(&e, days: 13 * 7)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        XCTAssertNotNil(try line(e, id, "pack").weekly)
    }

    func testGymCafeShopAndFactoryTradeAQuarterOnNamedSuppliersWithBalancedBooks() throws {
        for trade in ["gym", "cafe", "boutique", "factory"] {
            var (e, id) = try open(trade)
            for g in e.supplyLines(companyID: id) {
                for r in g.rows {
                    guard let o = r.offers.first(where: { $0.quality == "Solid" && !$0.isCurrent && $0.blocked == nil && $0.name != "Market supplier" }), case .catalogue = o.change else { continue }
                    XCTAssertEqual(e.chooseSupply(companyID: id, change: o.change), .ok, "\(trade) \(r.id)")
                }
            }
            ChainsTests.play(&e, days: 13 * 7)
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(trade): \(Ledger.gaps(e.state))")
            let co = try XCTUnwrap(e.state.company(id))
            XCTAssertGreaterThan(co.books.month["cogs"] ?? co.books.month["oth"] ?? 0, 0, "\(trade) books costs")
            XCTAssertTrue(e.supplyLines(companyID: id).flatMap { $0.rows }.contains { $0.weekly != nil && $0.weeklyBefore != nil }, trade)
        }
    }
}
