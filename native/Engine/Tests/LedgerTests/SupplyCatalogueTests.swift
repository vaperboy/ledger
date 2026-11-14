import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

final class SupplyCatalogueTests: XCTestCase {
    private func open(_ trade: String, seed: Int = 11) throws -> (GameEngine, Int) {
        var e = try ChainsTests.engine("NO", seed: seed)
        let id = ChainsTests.start(&e, trade)
        ChainsTests.season(&e, id)
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
            XCTAssertLessThanOrEqual(lines.filter { $0.isStock }.count, 1, "\(bd.id) has one stock line at most")
            let cogs = lines.filter { $0.isCogs }.reduce(0) { $0 + $1.share }
            XCTAssertTrue(cogs == 0 || abs(cogs - 1) < 0.001 || lines.contains { $0.isStock }, "\(bd.id) cost-of-sales shares add to \(cogs)")
            XCTAssertLessThan(lines.filter { !$0.isCogs }.reduce(0) { $0 + $1.share }, 0.95, "\(bd.id) overhead shares")
            for l in lines where !l.automatic { XCTAssertTrue(SupplyCatalogue.groups.contains(l.group), "\(bd.id) \(l.id) sits outside the four groups") }
        }
        XCTAssertTrue(none.isEmpty, "every trade buys something: \(none)")
        XCTAssertEqual(SupplyCatalogue.groups, ["Stock", "Upkeep", "Transport", "Services"])
    }

    func testGymBuysStockMachineServicingCleaningAndLaundry() throws {
        let (e, id) = try open("gym")
        let rows = e.supplyLines(companyID: id).flatMap { $0.rows }
        for want in ["food", "machines", "clean", "laundry"] { XCTAssertTrue(rows.contains { $0.id == want }, "gym lacks \(want): \(rows.map { $0.id })") }
        XCTAssertEqual(try line(e, id, "food").title, "Food and drink", "rows carry the short line name")
        XCTAssertEqual(try line(e, id, "food").kind, "Drinks, snacks and protein stock", "and the trade's own wording as the detail")
        let groups = e.supplyLines(companyID: id).map { $0.name }
        XCTAssertTrue(Set(groups).isSubset(of: ["Stock", "Upkeep", "Transport", "Services"]), "\(groups)")
        let laundry = try line(e, id, "laundry")
        XCTAssertGreaterThanOrEqual(laundry.offers.count, 2)
        XCTAssertEqual(laundry.offers.filter { $0.isCurrent }.count, 1)
        XCTAssertTrue(laundry.offers.allSatisfy { !$0.owner.isEmpty && !$0.ownerCode.isEmpty && $0.tradeID == "laundry" }, "every laundry supplier is a laundry company with an owner")
    }

    func testUtilitiesAndSoftwareAreNeverASupplierChoice() throws {
        var (e, id) = try open("gym")
        let ids = e.supplyLines(companyID: id).flatMap { $0.rows }.map { $0.id }
        XCTAssertFalse(ids.contains("power") || ids.contains("software") || ids.contains("web"), "\(ids)")
        XCTAssertEqual(e.chooseSupply(companyID: id, change: .catalogue(line: "power", offer: "x")), .notAllowed)
        XCTAssertEqual(e.chooseSupply(companyID: id, change: .catalogue(line: "software", offer: "x")), .notAllowed)
        let co = try XCTUnwrap(e.state.company(id)); let bd = try XCTUnwrap(e.data.catalog[co.type])
        for l in SupplyCatalogue.lines(co, bd) where l.automatic {
            XCTAssertTrue(SupplyCatalogue.offers(e.state, co, bd, line: l, data: e.data).isEmpty, l.id)
        }
        XCTAssertTrue(SupplyCatalogue.lines(co, bd).contains { $0.id == "power" && $0.automatic })
        ChainsTests.play(&e, days: 14)
        XCTAssertNotNil(SupplyCatalogue.weeklySpend(try XCTUnwrap(e.state.company(id)), line: "power"))
        for kind in IntercompanySupply.automaticKinds {
            XCTAssertFalse(IntercompanySupply.kindsFor(co).contains { $0.id == kind }, kind)
            XCTAssertFalse(e.supplierInputs(companyID: id).contains { $0.id == kind }, kind)
        }
    }

    func testNothingIsAskedBeforeTheFirstItemIsChosen() throws {
        var (e, id) = try open("cafe")
        e.update { s, _, _ in if let i = s.companyIndex(id) { SalesItems.markFirstChoicePending(&s, i) } }
        XCTAssertTrue(e.supplyLines(companyID: id).isEmpty)
        let pick = try XCTUnwrap(e.firstItemChoices(companyID: id).first)
        XCTAssertFalse(e.chooseFirstItem(companyID: id, itemID: pick.id).isRefused)
        XCTAssertFalse(e.supplyLines(companyID: id).isEmpty)
    }

    func testServiceTradesAndVenuesShowLists() throws {
        for trade in ["barber", "dental", "law", "hotel", "plumber", "taxi", "bank", "resrent"] {
            let (e, id) = try open(trade)
            XCTAssertFalse(e.supplyLines(companyID: id).isEmpty, "\(trade) shows no suppliers")
        }
    }

    func testOfficesSeeNoMaterialsOrPackagingLines() throws {
        let (e, id) = try open("law")
        let ids = e.supplyLines(companyID: id).flatMap { $0.rows }.map { $0.id }
        XCTAssertEqual(ids, ["clean"], "a law firm only buys cleaning; fees and office supplies are bills")
    }

    func testTierPriceAndQualityOfAFactoryAndACafe() throws {
        for (trade, lineID) in [("factory", "freight"), ("cafe", "bread")] {
            var (e, id) = try open(trade)
            let row = try line(e, id, lineID)
            let basic = try XCTUnwrap(row.offers.first { $0.quality == "Basic" }, "\(trade) has no basic offer")
            let premium = try XCTUnwrap(row.offers.first { $0.quality == "Top grade" })
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
    }

    func testPayingOnDeliveryCostsCashNowAndAnInvoiceWaits() throws {
        var (usual, idu) = try open("gym")
        var (cod, idc) = try open("gym")
        var (inv, idi) = try open("gym")
        let sw = try line(cod, idc, "laundry")
        let basic = try XCTUnwrap(sw.offers.first { $0.quality == "Basic" })
        let top = try XCTUnwrap(sw.offers.first { $0.quality == "Top grade" })
        XCTAssertEqual(cod.chooseSupply(companyID: idc, change: basic.change), .ok)
        XCTAssertEqual(inv.chooseSupply(companyID: idi, change: top.change), .ok)
        for _ in 0..<7 { ChainsTests.play(&usual, days: 1); ChainsTests.play(&cod, days: 1); ChainsTests.play(&inv, days: 1) }
        let owedUsual = usual.state.company(idu)?.payables["other"] ?? 0
        let owedInv = inv.state.company(idi)?.payables["other"] ?? 0
        XCTAssertGreaterThanOrEqual(owedInv, owedUsual - 1)
        for e in [usual, cod, inv] { XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))") }
        ChainsTests.play(&cod, days: 35); ChainsTests.play(&inv, days: 35)
        for e in [cod, inv] { XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))") }
    }

    func testShortagesOnlyFromPickedSuppliersAndCutSales() throws {
        let (e, id) = try open("boutique")
        var s = e.state
        let co0 = try XCTUnwrap(s.company(id)); let bd = try XCTUnwrap(e.data.catalog[co0.type])
        for w in 0..<300 { XCTAssertEqual(SupplyCatalogue.availability(s, co0, bd, week: w, data: e.data), 1, "the standard supplier never misses") }
        let worst = try XCTUnwrap(e.supplierCandidates(companyID: id, scope: "goods").min { $0.reliability < $1.reliability })
        XCTAssertFalse(worst.isStandard)
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
                XCTAssertGreaterThan(r.need, 0)
            }
        }
        let stock = try line(e, id, "food")
        XCTAssertEqual(stock.input, "goods")
        XCTAssertNotNil(stock.weekly); XCTAssertNotNil(stock.weeklyBefore)
    }

    func testOneRetailShopBuysAndBooksBalanceOverAQuarter() throws {
        var (e, id) = try open("boutique")
        let parcel = try line(e, id, "parcel")
        XCTAssertEqual(e.chooseSupply(companyID: id, change: try XCTUnwrap(parcel.offers.first { $0.quality == "Top grade" }).change), .ok)
        ChainsTests.play(&e, days: 13 * 7)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        XCTAssertNotNil(try line(e, id, "parcel").weekly)
    }

    func testGymCafeShopAndFactoryTradeAQuarterOnNamedSuppliersWithBalancedBooks() throws {
        for trade in ["gym", "cafe", "boutique", "factory"] {
            var (e, id) = try open(trade)
            var picked = 0
            for g in e.supplyLines(companyID: id) {
                for r in g.rows {
                    guard let o = r.offers.first(where: { !$0.isCurrent && $0.blocked == nil && !$0.isOwn }), case .catalogue = o.change else { continue }
                    XCTAssertEqual(e.chooseSupply(companyID: id, change: o.change), .ok, "\(trade) \(r.id)")
                    picked += 1
                }
            }
            XCTAssertGreaterThan(picked, 0, trade)
            ChainsTests.play(&e, days: 13 * 7)
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(trade): \(Ledger.gaps(e.state))")
            let co = try XCTUnwrap(e.state.company(id))
            XCTAssertGreaterThan(co.books.month["cogs"] ?? co.books.month["oth"] ?? 0, 0, "\(trade) books costs")
            XCTAssertTrue(e.supplyLines(companyID: id).flatMap { $0.rows }.contains { $0.weekly != nil && $0.weeklyBefore != nil }, trade)
        }
    }

    func testAServiceTradeSeesItsMaterialsNotPackaging() throws {
        let (e, id) = try open("barber")
        let rows = e.supplyLines(companyID: id).flatMap { $0.rows }.map { $0.id }
        XCTAssertTrue(rows.contains("care"), "\(rows)")
        XCTAssertTrue(rows.contains("upkeep"), "\(rows)")
        XCTAssertFalse(rows.contains("pack") || rows.contains("mat") || rows.contains("supplies"), "\(rows)")
        let care = try line(e, id, "care")
        XCTAssertTrue(care.offers.allSatisfy { $0.tradeID == "wholesale" }, "a salon's products come from wholesalers")
    }
}
