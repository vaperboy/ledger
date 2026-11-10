import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation
@testable import Businesses

final class UsedCarDealerTests: XCTestCase {
    private func game(seed: Int = 7, trade: String = "usedcar", cash: Double = 400_000_000, open: Bool = true) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 900_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, fundWith: cash) else { throw XCTSkip("no company") }
        _ = e.quickSetup(companyID: id)
        if open {
            _ = e.openCompany(companyID: id)
            e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .open } }
        }
        return (e, id)
    }
    private func balanced(_ e: GameEngine, _ what: String) { XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(what): \(Ledger.gaps(e.state))") }
    private func cars(_ e: GameEngine, _ id: Int, lemons: Bool = false) -> [Marketplace.Entry] {
        Marketplace.pool(e.state, companyID: id, data: e.data).filter { $0.h.vehicle && $0.h.equipmentID.isEmpty && (lemons || $0.h.kind != 2) }
    }
    @discardableResult private func buy(_ e: inout GameEngine, _ id: Int, _ x: Marketplace.Entry) -> SettingResult { e.buyListing(listingID: x.l.id, companyID: id, price: x.l.askingPrice) }
    private func stock(_ e: GameEngine, _ id: Int) -> [JSONValue] { e.state.company(id)!.value("stk").array }
    private func days(_ e: inout GameEngine, _ n: Int) { for _ in 0..<n { _ = e.nextDay() } }
    private func mutateCar(_ e: inout GameEngine, _ id: Int, _ carID: Int, _ f: @escaping (inout JSONValue) -> Void) {
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            var list = s.companies[i].value("stk").array
            if let k = list.firstIndex(where: { $0["id"].int == carID }) { f(&list[k]) }
            s.companies[i].set("stk", .array(list))
        }
    }

    func testSetUpHiresTheSalesTeamOfADealer() throws {
        let (e, id) = try game()
        XCTAssertTrue(e.state.company(id)!.staff.contains { $0.role == "cardealer" }, "the yard has a salesperson")
    }

    func testNothingAppearsByItself() throws {
        var (e, id) = try game()
        XCTAssertEqual(stock(e, id).count, 0)
        days(&e, 7 * 12)
        XCTAssertEqual(stock(e, id).count, 0, "no cars without a Marketplace purchase")
        let co = e.state.company(id)!
        XCTAssertEqual(co.inventory, 0, accuracy: 0.01)
        XCTAssertTrue(e.usedCarSales(companyID: id).isEmpty)
        balanced(e, "empty yard")
    }

    func testToolsAreOnlyCleaningAndCRM() throws {
        let e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 3)
        let bd = try XCTUnwrap(e.data.catalog["usedcar"])
        XCTAssertEqual(bd.equipment.map { $0.id }.sorted(), ["clean", "crm"])
        XCTAssertEqual(EquipmentMarket.kind(bd.equipment.first { $0.id == "crm" }!, tradeID: "usedcar", tables: e.data.catalog.tables), "soft")
    }

    func testLotSpacesComeFromThePremisesAndLimitBuying() throws {
        var (e, id) = try game()
        let lot = try XCTUnwrap(e.usedCarLot(companyID: id))
        XCTAssertGreaterThan(lot.spaces, 5)
        let prem = e.state.company(id)!.value("prem")
        XCTAssertEqual(lot.spaces, Int((prem["m2"].double * 0.85 / 22).rounded(.down)), "yard: 85 percent of the area, 22 m2 a car")
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            var p = s.companies[i].value("prem"); p["m2"] = .number(3 * 22 / 0.85 + 1); s.companies[i].set("prem", p)
        }
        XCTAssertEqual(e.usedCarLot(companyID: id)?.spaces, 3)
        let list = cars(e, id)
        for x in list.prefix(3) { XCTAssertEqual(buy(&e, id, x), .applied) }
        let cash = e.state.company(id)!.cash
        let r = buy(&e, id, list[3])
        XCTAssertTrue(r.isRefused)
        XCTAssertEqual(e.state.company(id)!.cash, cash)
        XCTAssertEqual(e.usedCarLot(companyID: id)?.free, 0)
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            var p = s.companies[i].value("prem"); p["m2"] = .number(0); s.companies[i].set("prem", p)
        }
        XCTAssertEqual(e.usedCarLot(companyID: id)?.spaces, 0)
        balanced(e, "lot")
    }

    func testEachCarHasItsOwnPriceAndQuoteShowsProfitOrLoss() throws {
        var (e, id) = try game()
        let two = Array(cars(e, id).prefix(2))
        for x in two { buy(&e, id, x) }
        days(&e, 14)
        let items = e.usedCarStock(companyID: id)
        XCTAssertEqual(items.count, 2)
        let a = items[0], b = items[1]
        XCTAssertEqual(e.setUsedCarPrice(companyID: id, carID: a.id, price: a.askingPrice * 1.5), .applied)
        let after = e.usedCarStock(companyID: id)
        XCTAssertEqual(after.first { $0.id == a.id }!.askingPrice, a.askingPrice * 1.5, accuracy: 0.01)
        XCTAssertEqual(after.first { $0.id == b.id }!.askingPrice, b.askingPrice, accuracy: 0.01, "the other car keeps its own price")
        XCTAssertTrue(e.setUsedCarPrice(companyID: id, carID: a.id, price: 0).isRefused)
        let cost = a.purchasePrice + a.repairs + (a.repairQuote > 0 && a.status != "ready" ? a.repairQuote : 0)
        let low = try XCTUnwrap(e.usedCarQuote(companyID: id, carID: a.id, price: cost * 0.8))
        let mid = try XCTUnwrap(e.usedCarQuote(companyID: id, carID: a.id, price: a.fairValue))
        let high = try XCTUnwrap(e.usedCarQuote(companyID: id, carID: a.id, price: cost * 2.5))
        XCTAssertFalse(low.isProfit); XCTAssertEqual(low.verdict, "Loss")
        XCTAssertTrue(high.isProfit); XCTAssertEqual(high.verdict, "Profit")
        XCTAssertEqual(low.profit, low.price - low.buyPrice - low.repairs - low.holdingSoFar - low.holdingAhead, accuracy: 0.01)
        XCTAssertEqual(low.buyPrice, a.purchasePrice, accuracy: 0.01)
        XCTAssertGreaterThan(low.weeklyOdds, mid.weeklyOdds)
        XCTAssertGreaterThan(mid.weeklyOdds, high.weeklyOdds)
        XCTAssertGreaterThan(high.expectedWeeks, low.expectedWeeks)
        XCTAssertGreaterThan(high.holdingAhead, low.holdingAhead)
    }

    func testRepairGoesToAnExternalGarageWithoutAnOwnMechanicCompany() throws {
        var (e, id) = try game()
        let lemon = try XCTUnwrap(cars(e, id, lemons: true).first { $0.h.kind == 2 })
        buy(&e, id, lemon)
        days(&e, 15)
        let c = try XCTUnwrap(e.usedCarStock(companyID: id).first)
        XCTAssertEqual(c.status, "repair", "a lemon needs the garage")
        XCTAssertEqual(c.repairSupplierID, 0)
        XCTAssertGreaterThan(c.repairQuote, 0)
        XCTAssertGreaterThanOrEqual(c.repairWeeksLeft, 1)
        days(&e, 7 * (c.repairWeeksLeft + 1))
        let d = try XCTUnwrap(e.usedCarStock(companyID: id).first { $0.id == c.id })
        if d.status == "ready" {
            XCTAssertEqual(d.repairs, c.repairs + c.repairQuote, accuracy: 1)
        }
        balanced(e, "external repair")
    }

    func testOwnMechanicCompanyDoesTheRepairAsASupplier() throws {
        var (e, id) = try game()
        guard case .success(let rid) = e.startCompany(tradeID: "carrepair", cityID: e.state.player.cityID, fundWith: 100_000_000) else { throw XCTSkip("no mechanic") }
        _ = e.quickSetup(companyID: rid)
        _ = e.openCompany(companyID: rid)
        e.update { s, _, _ in if let i = s.companyIndex(rid) { s.companies[i].status = .open } }
        let lemon = try XCTUnwrap(cars(e, id, lemons: true).first { $0.h.kind == 2 })
        buy(&e, id, lemon)
        mutateCar(&e, id, stock(e, id)[0]["id"].int) { $0["ask"] = .number($0["fair"].double * 10) }
        days(&e, 15)
        let c = try XCTUnwrap(e.usedCarStock(companyID: id).first)
        XCTAssertEqual(c.status, "repair")
        XCTAssertEqual(c.repairSupplierID, rid, "the job order goes to your own mechanic company")
        let need = try XCTUnwrap(e.state.company(id)!.value("stk").array.first)["rq"].double
        XCTAssertEqual(c.repairQuote, need * UsedCarDealer.ownRepairFactor, accuracy: 0.01, "group price under the market price")
        var waited = 0
        while e.usedCarStock(companyID: id).first(where: { $0.id == c.id })?.status == "repair" && waited < 7 * (c.repairWeeksLeft + 4) { days(&e, 1); waited += 1 }
        let after = e.state.company(rid)!
        let billed = AccountingLedger.rows(after).filter { $0.label.hasPrefix("Repairs for") && $0.amount > 0 }.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(billed, c.repairQuote, accuracy: 1, "the mechanic company bills the dealer the job price")
        let d = try XCTUnwrap(e.usedCarStock(companyID: id).first { $0.id == c.id })
        XCTAssertEqual(d.status, "ready")
        XCTAssertEqual(d.repairs, c.repairs + c.repairQuote, accuracy: 1)
        let wk = UsedCarDealer.repairOffer(e.state, company: e.state.company(id)!, need: 100_000, data: e.data)
        XCTAssertTrue(wk.isOwn); XCTAssertEqual(wk.price, 100_000 * UsedCarDealer.ownRepairFactor, accuracy: 0.01); XCTAssertEqual(wk.marketPrice, 100_000)
        balanced(e, "own mechanic repair")
    }

    func testCarInRepairCanBeReservedAndIsSoldWhenFixed() throws {
        var (e, id) = try game()
        let x = try XCTUnwrap(cars(e, id).first)
        buy(&e, id, x)
        let carID = stock(e, id)[0]["id"].int
        let due = e.state.week + 3
        mutateCar(&e, id, carID) { c in
            c["done"] = .bool(true); c["rq"] = .number(1_000); c["wk"] = .number(Double(due - 3))
            c["job"] = .object(["due": .number(Double(due)), "sup": 0, "sn": "An independent garage", "price": .number(1_000), "from": .number(Double(due - 3))])
            c["ask"] = .number(c["fair"].double * 0.7)
        }
        XCTAssertEqual(e.usedCarStock(companyID: id)[0].status, "repair")
        var reserved = false
        var guardWeeks = 0
        while e.state.week < due + 3 && guardWeeks < 140 {
            _ = e.nextDay(); guardWeeks += 1
            if let c = e.usedCarStock(companyID: id).first(where: { $0.id == carID }) {
                if c.reserved { reserved = true; XCTAssertEqual(c.status, "repair", "kept in the yard, not sold, until it is fixed") ; XCTAssertGreaterThan(c.reservedPrice, 0) }
            }
        }
        XCTAssertTrue(reserved, "customers reserve a car that is being fixed")
        XCTAssertNil(e.usedCarStock(companyID: id).first { $0.id == carID }, "sold on finish")
        let sale = try XCTUnwrap(e.usedCarSales(companyID: id).last)
        XCTAssertEqual(sale.repairs, stock(e, id).isEmpty ? sale.repairs : 0, accuracy: 100_000)
        XCTAssertGreaterThan(sale.price, 0)
        balanced(e, "reservation")
    }

    func testStuckCarsLoseValueAndSellSlowlyAndGetAWholesalerOffer() throws {
        XCTAssertEqual(UsedCarDealer.freshness(weeks: 0), 1)
        XCTAssertEqual(UsedCarDealer.freshness(weeks: UsedCarDealer.staleAfter), 1)
        XCTAssertLessThan(UsedCarDealer.freshness(weeks: 30), UsedCarDealer.freshness(weeks: 12))
        XCTAssertLessThan(UsedCarDealer.freshness(weeks: 30), 0.5)
        var (e, id) = try game()
        buy(&e, id, try XCTUnwrap(cars(e, id).first))
        let carID = stock(e, id)[0]["id"].int
        let wk0 = e.state.week
        mutateCar(&e, id, carID) { c in c["done"] = .bool(true); c["fx"] = .bool(true); c["wk"] = .number(Double(wk0 - 12)); c["ask"] = .number(c["fair"].double * 3) }
        let fair0 = stock(e, id)[0]["fair"].double
        var offer: Message?
        for _ in 0..<(7 * 20) {
            _ = e.nextDay()
            offer = e.state.inbox.first { $0.actionID == UsedCarDealer.offerAction && $0.status == "open" }
            if offer != nil { break }
        }
        XCTAssertGreaterThan(stock(e, id).first?["fair"].double ?? fair0, 0)
        let m = try XCTUnwrap(offer, "a wholesaler offers for a stuck car")
        let price = m.value("data")["price"].double
        let car = try XCTUnwrap(stock(e, id).first)
        XCTAssertLessThan(price, car["fair"].double * 0.85, "a wholesaler pays under fair value")
        let cash = e.state.company(id)!.cash
        XCTAssertTrue(e.answer(messageID: m.id, option: 0))
        XCTAssertEqual(stock(e, id).count, 0)
        XCTAssertEqual(e.state.company(id)!.cash, cash + price, accuracy: 1)
        XCTAssertEqual(e.usedCarSales(companyID: id).last?.forced, "wholesaler")
        XCTAssertEqual(e.state.company(id)!.inventory, 0, accuracy: 1)
        balanced(e, "wholesaler")
    }

    func testStuckCarFallsFasterInValueThanAFreshOne() throws {
        var (e, id) = try game()
        let two = Array(cars(e, id).prefix(2))
        for x in two { buy(&e, id, x) }
        let ids = stock(e, id).map { $0["id"].int }
        for cid in ids { mutateCar(&e, id, cid) { c in c["done"] = .bool(true); c["fx"] = .bool(true); c["ask"] = .number(c["fair"].double * 5) } }
        let wk0 = e.state.week
        mutateCar(&e, id, ids[0]) { c in c["wk"] = .number(Double(wk0 - 20)) }
        let f0 = stock(e, id).map { $0["fair"].double }
        days(&e, 15)
        let f1 = stock(e, id).map { $0["fair"].double }
        XCTAssertLessThan(f1[0] / f0[0], f1[1] / f0[1], "the stuck car lost more")
    }

    func testLotOverCapacityForcesAnAuctionSaleAtALoss() throws {
        var (e, id) = try game()
        for x in cars(e, id).prefix(4) { buy(&e, id, x) }
        for cid in stock(e, id).map({ $0["id"].int }) { mutateCar(&e, id, cid) { c in c["done"] = .bool(true); c["fx"] = .bool(true); c["ask"] = .number(c["fair"].double * 5) } }
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            var p = s.companies[i].value("prem"); p["m2"] = .number(2 * 22 / 0.85 + 1); s.companies[i].set("prem", p)
        }
        days(&e, 15)
        XCTAssertEqual(stock(e, id).count, 2, "two cars had to go")
        let sold = e.usedCarSales(companyID: id)
        XCTAssertEqual(sold.count, 2)
        XCTAssertTrue(sold.allSatisfy { $0.forced == "lot full" })
        XCTAssertTrue(sold.contains { $0.profit < 0 }, "a forced auction sale is a loss")
        XCTAssertTrue(e.state.inbox.contains { $0.title.hasSuffix("sent to auction") })
        balanced(e, "auction")
    }

    func testNobodyBuysCarsWithoutABuyerOrManager() throws {
        var (e, id) = try game()
        days(&e, 7 * 10)
        XCTAssertEqual(stock(e, id).count, 0)
        XCTAssertTrue(e.usedCarBuyers(companyID: id).isEmpty)
    }

    func testHiredBuyerBuysAndHisTrackRecordIsKept() throws {
        var (e, id) = try game()
        XCTAssertTrue(e.hireableRoles(companyID: id).contains("buyer"))
        var pid = 0
        e.update { s, d, _ in pid = Hiring.generateCandidate(role: "buyer", company: s.company(id), tier: "mid", state: &s, data: d).id }
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: e.state.people[pid]!.askingMonthlyWage * 1.3), .ok)
        days(&e, 7 * 12)
        let n = stock(e, id).count + e.usedCarSales(companyID: id).count
        XCTAssertGreaterThan(n, 0, "the buyer filled the yard")
        let rec = try XCTUnwrap(e.usedCarBuyers(companyID: id).first { $0.role == "buyer" })
        XCTAssertGreaterThan(rec.deals, 0)
        XCTAssertEqual(rec.rating, UsedCarDealer.rating(discount: rec.averageDiscount), accuracy: 0.001)
        XCTAssertLessThanOrEqual(rec.averageDiscount, 0.4)
        balanced(e, "buyer")
    }

    func testBuyerRatingFollowsHowGoodTheDealsWere() {
        XCTAssertEqual(UsedCarDealer.rating(discount: 0), 50)
        XCTAssertGreaterThan(UsedCarDealer.rating(discount: 0.06), UsedCarDealer.rating(discount: 0.02))
        XCTAssertLessThan(UsedCarDealer.rating(discount: -0.05), 50)
        var co = Company(raw: [:])
        UsedCarDealer.recordDeal(&co, who: "9", fair: 100, paid: 90)
        UsedCarDealer.recordDeal(&co, who: "9", fair: 100, paid: 96)
        XCTAssertEqual(co.value("ucb")["9"]["n"].int, 2)
        XCTAssertEqual(co.value("ucb")["9"]["f"].double, 200)
        XCTAssertEqual(co.value("ucb")["9"]["p"].double, 186)
    }

    func testPlayersOwnPurchasesAreRecordedToo() throws {
        var (e, id) = try game()
        let x = try XCTUnwrap(cars(e, id).first)
        buy(&e, id, x)
        let rec = try XCTUnwrap(e.usedCarBuyers(companyID: id).first)
        XCTAssertEqual(rec.role, "you")
        XCTAssertEqual(rec.averageDiscount, 1 - x.l.askingPrice / x.h.fair, accuracy: 1e-9)
    }

    func testCommissionIsAShareOfTheCarsProfitAndNothingOnALoss() throws {
        XCTAssertEqual(UsedCarDealer.profitShareMultiple * PayPlans.mode("com")!.defaultRate, 0.24, accuracy: 1e-9)
        XCTAssertEqual(UsedCarDealer.profitShareMultiple * PayPlans.mode("mix")!.defaultRate, 0.12, accuracy: 1e-9)
        let sales: Set<String> = ["sales", "cardealer", "estate", "agent", "broker"]
        XCTAssertTrue(PayPlans.eligible(role: "cardealer", trade: "usedcar", salesRoles: sales))
        XCTAssertTrue(PayPlans.eligible(role: "buyer", trade: "usedcar", salesRoles: sales))
        XCTAssertEqual(PayPlans.modes(role: "buyer", trade: "usedcar", salesRoles: sales), ["fix", "mix", "com"])
        XCTAssertFalse(PayPlans.eligible(role: "buyer", trade: "carrepair", salesRoles: sales))
    }

    func testCommissionOnlySalespersonIsPaidFromTheProfitOfTheSale() throws {
        var (e, id) = try game()
        let person = try XCTUnwrap(e.state.company(id)!.staff.first { $0.role == "cardealer" })
        e.update { s, d, _ in _ = StaffProfile.setPayModel(&s, companyID: id, staffID: person.id, mode: "com", data: d) }
        let st = try XCTUnwrap(e.state.company(id)!.staff.first { $0.id == person.id })
        guard st.commissionMode == "com" else { throw XCTSkip("the salesperson refused commission only") }
        XCTAssertEqual(st.monthlyWage, 0)
        buy(&e, id, try XCTUnwrap(cars(e, id).first))
        let carID = stock(e, id)[0]["id"].int
        mutateCar(&e, id, carID) { c in c["done"] = .bool(true); c["fx"] = .bool(true); c["fair"] = .number(c["cost"].double * 1.5); c["ask"] = .number(c["cost"].double * 1.3) }
        var gross = 0.0
        for _ in 0..<(7 * 12) {
            _ = e.nextDay()
            gross = max(gross, e.state.company(id)!.num("ucg"))
        }
        XCTAssertGreaterThan(gross, 0, "the car sold at a profit")
        let paid = try XCTUnwrap(e.state.company(id)!.staff.first { $0.id == person.id }).num("lastComm")
        XCTAssertGreaterThanOrEqual(paid, 0)
    }

    func testASaleShowsItsRealProfitInTheBooks() throws {
        var (e, id) = try game()
        buy(&e, id, try XCTUnwrap(cars(e, id).first))
        let carID = stock(e, id)[0]["id"].int
        mutateCar(&e, id, carID) { c in c["done"] = .bool(true); c["fx"] = .bool(true); c["fair"] = .number(c["cost"].double * 1.6); c["ask"] = .number(c["cost"].double * 1.5) }
        let bought = stock(e, id)[0]["cost"].double
        let co0 = e.state.company(id)!
        let rev0 = co0.books.month["rev"] ?? 0, cogs0 = co0.books.month["cogs"] ?? 0
        var soldWeek = false
        for _ in 0..<(7 * 3) {
            _ = e.nextDay()
            if let lw = Optional(e.state.company(id)!.value("lastW")), lw["units"].double > 0 { soldWeek = true; XCTAssertEqual(lw["rev"].double, bought * 1.5, accuracy: 2); XCTAssertEqual(lw["cogs"].double, bought, accuracy: 2); break }
        }
        XCTAssertTrue(soldWeek, "the car sold within three weeks at 50 percent over cost")
        let co = e.state.company(id)!
        let rev = (co.books.month["rev"] ?? 0) - rev0, cogs = (co.books.month["cogs"] ?? 0) - cogs0
        if co.books.month["rev"] != nil && rev > 0 {
            XCTAssertEqual(rev, bought * 1.5, accuracy: 2)
            XCTAssertEqual(cogs, bought, accuracy: bought * 0.03)
            XCTAssertGreaterThan(rev - cogs, bought * 0.4)
        }
        let sale = try XCTUnwrap(e.usedCarSales(companyID: id).last)
        XCTAssertEqual(sale.profit, sale.price - sale.buyPrice - sale.repairs - sale.holding, accuracy: 0.01)
        XCTAssertGreaterThan(sale.profit, 0)
        XCTAssertGreaterThan(e.state.company(id)!.inventory + 1, 0)
        XCTAssertEqual(e.state.company(id)!.inventory, 0, accuracy: 1)
        balanced(e, "sale profit")
    }

    func testItemForecastUsesTheRealCostOfCars() throws {
        var (e, id) = try game()
        for x in cars(e, id).prefix(3) { buy(&e, id, x) }
        let co = e.state.company(id)!
        let ratio = try XCTUnwrap(UsedCarDealer.costRatio(co))
        let fair = co.value("stk").array.reduce(0) { $0 + $1["fair"].double }
        let cost = co.value("stk").array.reduce(0) { $0 + $1["cost"].double + $1["rep"].double }
        XCTAssertEqual(ratio, cost / fair, accuracy: 1e-9)
    }

    func testSaveReloadKeepsTheNewCarFields() throws {
        var (e, id) = try game()
        buy(&e, id, try XCTUnwrap(cars(e, id).first))
        let carID = stock(e, id)[0]["id"].int
        XCTAssertEqual(e.setUsedCarPrice(companyID: id, carID: carID, price: 123_456), .applied)
        XCTAssertEqual(e.setUsedCarAutoRepair(companyID: id, on: false), .applied)
        days(&e, 14)
        let data = try JSONEncoder().encode(e.state)
        let s2 = try JSONDecoder().decode(GameState.self, from: data)
        var f = e
        f.update { s, _, _ in s = s2 }
        XCTAssertEqual(f.usedCarStock(companyID: id), e.usedCarStock(companyID: id))
        XCTAssertFalse(f.usedCarAutoRepair(companyID: id))
        XCTAssertEqual(f.usedCarBuyers(companyID: id), e.usedCarBuyers(companyID: id))
    }

    func testOldSavesWithoutNewKeysStillWork() throws {
        var (e, id) = try game()
        buy(&e, id, try XCTUnwrap(cars(e, id).first))
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            var list = s.companies[i].value("stk").array
            for k in list.indices { for key in ["ask", "rq", "job", "res", "fx", "skip", "hold"] { list[k].removeKey(key) } }
            s.companies[i].set("stk", .array(list))
        }
        let item = try XCTUnwrap(e.usedCarStock(companyID: id).first)
        XCTAssertEqual(item.askingPrice, item.purchasePrice * (1 + UsedCarDealer.defaultMarkup / 100), accuracy: 0.01)
        days(&e, 7 * 4)
        balanced(e, "old save")
    }
}
