import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation
@testable import Businesses

final class MarketplaceTests: XCTestCase {
    private func game(seed: Int = 7, trade: String = "usedcar", cash: Double = 400_000_000, open: Bool = true) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 900_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, form: .limited, fundWith: cash) else { throw XCTSkip("no company") }
        _ = e.quickSetup(companyID: id)
        if open { _ = e.openCompany(companyID: id) }
        return (e, id)
    }
    private func balanced(_ e: GameEngine, _ what: String) { XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(what): \(Ledger.gaps(e.state))") }
    private func hidden(_ e: GameEngine, _ id: Int) -> [String: Marketplace.Entry] {
        Dictionary(uniqueKeysWithValues: Marketplace.pool(e.state, companyID: id, data: e.data).map { ($0.l.id, $0) })
    }

    func testPoolIsDeterministicAndRefreshedWeekly() throws {
        let (a, ia) = try game(), (b, ib) = try game()
        let la = a.marketplaceListings(forCompany: ia), lb = b.marketplaceListings(forCompany: ib)
        XCTAssertEqual(la, lb)
        XCTAssertTrue((25...70).contains(la.count), "live listings: \(la.count)")
        XCTAssertEqual(la.count, Set(la.map { $0.id }).count)
        XCTAssertTrue(la.allSatisfy { $0.askingPrice > 0 && !$0.title.isEmpty && !$0.blurb.isEmpty && !$0.sellerName.isEmpty })
        // The same engine reads the same pool twice; a week later part of it has expired and new listings are in.
        XCTAssertEqual(a.marketplaceListings(forCompany: ia), la)
        var c = a
        for _ in 0..<7 { _ = c.nextDay() }
        let lc = c.marketplaceListings(forCompany: ia)
        XCTAssertTrue((25...70).contains(lc.count))
        let ids = Set(la.map { $0.id }), idc = Set(lc.map { $0.id })
        XCTAssertGreaterThan(idc.subtracting(ids).count, 3)
        XCTAssertGreaterThan(ids.subtracting(idc).count, 3)
        XCTAssertGreaterThan(idc.intersection(ids).count, 3)
        // Cars and vans are on offer to a dealer.
        XCTAssertTrue(la.filter { $0.family.hasPrefix("car") || $0.family.hasPrefix("van") }.count > 8)
    }

    func testBargainAndLemonRates() throws {
        var (e, id) = try game(open: false)
        var n = 0, bargains = 0, lemons = 0, noTalk = 0
        var ratios: [Double] = []
        for week in stride(from: 10, to: 700, by: 6) {
            e.update { s, _, _ in s.week = week }
            for x in Marketplace.pool(e.state, companyID: id, data: e.data) {
                n += 1
                if x.h.kind == 1 { bargains += 1; XCTAssertLessThan(x.l.askingPrice / x.h.fair, 0.81) }
                if x.h.kind == 2 { lemons += 1; XCTAssertGreaterThan(x.h.wear, 0.55) }
                if x.h.noTalk { noTalk += 1 }
                if x.h.kind == 0 { ratios.append(x.l.askingPrice / x.h.fair) }
            }
        }
        let b = Double(bargains) / Double(n), l = Double(lemons) / Double(n), t = Double(noTalk) / Double(n)
        print("MARKET rates n=\(n) bargain=\(b) lemon=\(l) noTalk=\(t) normal ratio min/max=\(ratios.min()!)/\(ratios.max()!)")
        XCTAssertTrue((0.015...0.08).contains(b), "bargains \(b)")
        XCTAssertTrue((0.08...0.17).contains(l), "lemons \(l)")
        XCTAssertTrue((0.09...0.22).contains(t), "no talk \(t)")
        XCTAssertGreaterThan(ratios.min()!, 0.87); XCTAssertLessThan(ratios.max()!, 1.13)
    }

    /// A listing the seller will talk about.
    private func talkable(_ e: GameEngine, _ id: Int, minWear: Double = 0, vehicle: Bool = true) -> Marketplace.Entry {
        Marketplace.pool(e.state, companyID: id, data: e.data).first { !$0.h.noTalk && $0.h.kind != 1 && $0.h.wear >= minWear && ($0.h.vehicle == vehicle) && $0.h.equipmentID.isEmpty == vehicle }!
    }

    func testNegotiationLowersThePriceAndSpendsPatience() throws {
        var (e, id) = try game()
        let x = talkable(e, id, minWear: 0.3)
        var n = try XCTUnwrap(e.beginNegotiation(listingID: x.l.id, companyID: id))
        XCTAssertTrue(n.canDiscuss); XCTAssertEqual(n.mood, .open); XCTAssertEqual(n.price, x.l.askingPrice)
        XCTAssertGreaterThanOrEqual(n.patienceLeft, 2)
        var last = n.price, left = n.patienceLeft, dropped = 0
        while n.canDiscuss {
            n = e.pushPrice(listingID: x.l.id, companyID: id)
            XCTAssertEqual(n.patienceLeft, left - 1)
            XCTAssertLessThanOrEqual(n.price, last)
            XCTAssertGreaterThan(n.price, last * 0.85, "a push moves the price a few percent")
            if n.price < last { dropped += 1 }
            last = n.price; left = n.patienceLeft
            XCTAssertFalse(n.lastMessage.isEmpty)
        }
        XCTAssertGreaterThan(dropped, 0)
        XCTAssertEqual(n.mood, .refusing); XCTAssertEqual(n.patienceLeft, 0)
        XCTAssertLessThan(n.price, x.l.askingPrice)
        // Frozen: the listing is still there at the frozen price until the player pushes again.
        XCTAssertTrue(e.marketplaceListings(forCompany: id).contains { $0.id == x.l.id })
        let again = e.beginNegotiation(listingID: x.l.id, companyID: id)
        XCTAssertEqual(again?.price, n.price)
        let after = e.pushPrice(listingID: x.l.id, companyID: id)
        XCTAssertFalse(after.canDiscuss); XCTAssertEqual(after.price, n.price)
        XCTAssertFalse(e.marketplaceListings(forCompany: id).contains { $0.id == x.l.id }, "the seller will not sell again")
        XCTAssertNil(e.beginNegotiation(listingID: x.l.id, companyID: id))
        XCTAssertTrue(e.buyListing(listingID: x.l.id, companyID: id, price: n.price).isRefused)
    }

    func testSomeSellersRefuseToDiscussAtOnce() throws {
        let (e, id) = try game()
        let x = try XCTUnwrap(Marketplace.pool(e.state, companyID: id, data: e.data).first { $0.h.noTalk })
        var f = e
        let n = try XCTUnwrap(f.beginNegotiation(listingID: x.l.id, companyID: id))
        XCTAssertFalse(n.canDiscuss); XCTAssertEqual(n.mood, .refusing); XCTAssertEqual(n.price, x.l.askingPrice)
    }

    func testWornItemsGiveMoreThanBargains() throws {
        let (e0, id) = try game()
        let pool = Marketplace.pool(e0.state, companyID: id, data: e0.data).filter { !$0.h.noTalk }
        var worn = 0.0, wornN = 0.0, bargain = 0.0, bargainN = 0.0
        for x in pool where x.h.kind != 1 && x.h.wear > 0.5 || x.h.kind == 1 {
            var e = e0
            _ = e.beginNegotiation(listingID: x.l.id, companyID: id)
            let n = e.pushPrice(listingID: x.l.id, companyID: id)
            let cut = 1 - n.price / x.l.askingPrice
            if x.h.kind == 1 { bargain += cut; bargainN += 1 } else { worn += cut; wornN += 1 }
        }
        XCTAssertGreaterThan(wornN, 2)
        print("MARKET first push: worn \(worn / wornN) bargain \(bargain / max(1, bargainN))")
        if bargainN > 0 { XCTAssertGreaterThan(worn / wornN, bargain / bargainN) }
    }

    func testBuyingAnItemBooksCashAndCreatesIt() throws {
        var (e, id) = try game(trade: "cafe")
        let cafePool = Marketplace.pool(e.state, companyID: id, data: e.data)
        let x = try XCTUnwrap(cafePool.first { !$0.h.vehicle && !$0.h.noTalk })
        let cash0 = e.state.company(id)!.cash
        let before = e.state.company(id)!.value("eq")[x.h.equipmentID]["n"].double
        let r = e.buyListing(listingID: x.l.id, companyID: id, price: x.l.askingPrice)
        XCTAssertEqual(r, .applied)
        let co = e.state.company(id)!
        XCTAssertEqual(co.cash, cash0 - x.l.askingPrice, accuracy: 1)
        XCTAssertEqual(co.value("eq")[x.h.equipmentID]["n"].double, before + 1)
        XCTAssertEqual(co.value("eq")[x.h.equipmentID]["used"].int, 1)
        XCTAssertFalse(e.marketplaceListings(forCompany: id).contains { $0.id == x.l.id })
        XCTAssertNotNil(e.listingReveal(listingID: x.l.id, companyID: id))
        XCTAssertTrue(e.state.inbox.contains { $0.companyID == id && $0.title.hasPrefix("About the") })
        XCTAssertTrue(e.buyListing(listingID: x.l.id, companyID: id, price: x.l.askingPrice).isRefused)
        balanced(e, "after buying equipment")
        // Not enough cash.
        e.update { s, _, _ in if let i = s.companyIndex(id) { Ledger.moveRaw(&s, .company(id), -s.companies[i].cash + 1) } }
        let y = try XCTUnwrap(Marketplace.pool(e.state, companyID: id, data: e.data).first { !$0.h.vehicle })
        XCTAssertTrue(e.buyListing(listingID: y.l.id, companyID: id, price: y.l.askingPrice).isRefused)
        XCTAssertNil(e.listingReveal(listingID: y.l.id, companyID: id))
    }

    func testLemonsHideWearAndTheRevealSaysSo() throws {
        var (e, id) = try game(trade: "cafe")
        e.update { s, _, _ in s.week = 40 }
        var found: Marketplace.Entry?
        for week in 40..<400 where found == nil {
            e.update { s, _, _ in s.week = week }
            found = Marketplace.pool(e.state, companyID: id, data: e.data).first { $0.h.kind == 2 && !$0.h.vehicle }
        }
        let x = try XCTUnwrap(found)
        XCTAssertEqual(e.buyListing(listingID: x.l.id, companyID: id, price: x.l.askingPrice), .applied)
        let text = try XCTUnwrap(e.listingReveal(listingID: x.l.id, companyID: id))
        XCTAssertTrue(text.contains("did not mention"), text)
        XCTAssertEqual(e.state.company(id)!.value("eq")[x.h.equipmentID]["cond"].double, 1 - x.h.wear, accuracy: 0.3)
    }

    func testDealerBuysStockAndSellsWithMargin() throws {
        var (e, id) = try game()
        let cars = Marketplace.pool(e.state, companyID: id, data: e.data).filter { $0.h.vehicle && $0.h.equipmentID.isEmpty && $0.h.kind != 2 }.prefix(5)
        XCTAssertEqual(cars.count, 5)
        let cash0 = e.state.company(id)!.cash
        var paid = 0.0
        for x in cars { XCTAssertEqual(e.buyListing(listingID: x.l.id, companyID: id, price: x.l.askingPrice), .applied); paid += x.l.askingPrice }
        var co = e.state.company(id)!
        XCTAssertEqual(co.cash, cash0 - paid, accuracy: 5)
        XCTAssertEqual(co.inventory, paid, accuracy: 5)
        XCTAssertEqual(e.usedCarStock(companyID: id).count, 5)
        balanced(e, "after stocking")
        XCTAssertEqual(e.setUsedCarMarkup(companyID: id, percent: 8), .applied)
        XCTAssertEqual(e.usedCarMarkup(companyID: id), 8)
        XCTAssertTrue(e.setUsedCarMarkup(companyID: id, percent: 900).isRefused)
        var sold = 0.0, revenue = 0.0
        for _ in 0..<(7 * 16) {
            _ = e.nextDay()
            co = e.state.company(id)!
            if let lw = Optional(co.value("lastW")), lw["units"].double > 0, e.state.day % 7 == 0 { sold += lw["units"].double; revenue += lw["rev"].double }
        }
        balanced(e, "after selling")
        let left = e.usedCarStock(companyID: id)
        XCTAssertLessThan(left.count, 5, "some cars sold")
        XCTAssertGreaterThan(sold, 0)
        XCTAssertTrue(left.allSatisfy { $0.inspected && $0.repairs > 0 })
        XCTAssertGreaterThan(revenue, 0)
        co = e.state.company(id)!
        XCTAssertEqual(co.inventory, left.reduce(0) { $0 + $1.purchasePrice + $1.repairs }, accuracy: 5)
    }

    func testSaveReloadKeepsTheMarketplace() throws {
        var (e, id) = try game()
        let x = talkable(e, id)
        _ = e.beginNegotiation(listingID: x.l.id, companyID: id)
        let n = e.pushPrice(listingID: x.l.id, companyID: id)
        let car = try XCTUnwrap(Marketplace.pool(e.state, companyID: id, data: e.data).first { $0.h.vehicle && $0.h.equipmentID.isEmpty && $0.l.id != x.l.id })
        XCTAssertEqual(e.buyListing(listingID: car.l.id, companyID: id, price: car.l.askingPrice), .applied)
        let data = try JSONEncoder().encode(e.state)
        let s2 = try JSONDecoder().decode(GameState.self, from: data)
        var f = e
        f.update { s, _, _ in s = s2 }
        XCTAssertEqual(f.marketplaceListings(forCompany: id), e.marketplaceListings(forCompany: id))
        XCTAssertEqual(Marketplace.read(s2, Marketplace.negKey(id, x.l.id)), n)
        XCTAssertEqual(f.usedCarStock(companyID: id), e.usedCarStock(companyID: id))
        XCTAssertEqual(f.listingReveal(listingID: car.l.id, companyID: id), e.listingReveal(listingID: car.l.id, companyID: id))
        XCTAssertNotNil(f.listingReveal(listingID: car.l.id, companyID: id))
    }

    func testDealerWeekIsDeterministic() throws {
        func run() throws -> (Double, Double, [UsedCarStockItem]) {
            var (e, id) = try game(seed: 11)
            for x in Marketplace.pool(e.state, companyID: id, data: e.data).filter({ $0.h.vehicle && $0.h.equipmentID.isEmpty }).prefix(6) {
                _ = e.buyListing(listingID: x.l.id, companyID: id, price: x.l.askingPrice)
            }
            for _ in 0..<(7 * 10) { _ = e.nextDay() }
            let co = e.state.company(id)!
            return (co.cash, co.inventory, e.usedCarStock(companyID: id))
        }
        let a = try run(), b = try run()
        XCTAssertEqual(a.0, b.0); XCTAssertEqual(a.1, b.1); XCTAssertEqual(a.2, b.2)
    }

    /// Money probe: a competent dealer (knows what cars are worth, haggles twice, keeps the yard stocked, a sensible marketing plan) for three years.
    /// Set LEDGER_PROBE=1; LEDGER_MARKUP (percent), LEDGER_STOCK (cars) and LEDGER_BUYS (cars a week at most) change the policy.
    func testCompetentDealerProbe() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["LEDGER_PROBE"] != nil else { throw XCTSkip("probe: set LEDGER_PROBE=1") }
        let markup = Double(env["LEDGER_MARKUP"] ?? "12") ?? 12, target = Int(env["LEDGER_STOCK"] ?? "20") ?? 20, buys = Int(env["LEDGER_BUYS"] ?? "4") ?? 4
        let ratioMax = Double(env["LEDGER_RATIO"] ?? "0.98") ?? 0.98, pushes = Int(env["LEDGER_PUSH"] ?? "2") ?? 2
        var report = ""
        for seed in [11, 12, 13] {
            var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
            var id = 0, est = 0.0
            e.update { s, data, ctx in
                Ledger.move(&s, .me, 20_000_000_000, why: "Test funds")
                guard case .success(let i) = CompanySetup.create(&s, tradeID: "usedcar", cityID: s.player.cityID, form: .limited, data: data, context: ctx) else { return }
                id = i
                est = CompanySetup.estimate(tradeID: "usedcar", cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)?.total ?? 0
                Payments.injectCash(&s, companyID: id, amount: est * 1.3 + Double(env["LEDGER_STOCKCASH"] ?? "6000000")!)
                _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
                if env["LEDGER_NOMANAGER"] == nil, let bd = data.catalog["usedcar"] {
                    for _ in 0..<6 {
                        let c = ManagerModel.generateCandidate(company: s.company(id), type: bd.managerType, state: &s, data: data)
                        if ManagerModel.hire(&s, personID: c.id, companyID: id, monthlyWage: c.askingMonthlyWage * 1.2, data: data) == .ok { break }
                    }
                }
            }
            XCTAssertNotEqual(id, 0)
            let cash0 = e.state.company(id)!.cash
            _ = e.openCompany(companyID: id)
            _ = e.setUsedCarMarkup(companyID: id, percent: markup)
            for (k, n) in [("google", 1), ("meta", 1), ("seo", 1)] {
                if let ch = e.marketing.channels[k], ch.budgetOptions.count > n { _ = e.setCampaign(companyID: id, channel: k, weeklyBudget: ch.budgetOptions[n]) }
            }
            var sold = 0.0, bought = 0, stockSum = 0.0, weeks = 0, lemons = 0, injected = 0.0
            for week in 0..<156 {
                var n = 0
                while e.usedCarStock(companyID: id).count < target && n < buys {
                    let list = Marketplace.pool(e.state, companyID: id, data: e.data).filter { $0.h.vehicle && $0.h.equipmentID.isEmpty && !$0.h.noTalk }
                    guard let x = list.min(by: { $0.l.askingPrice / $0.h.fair < $1.l.askingPrice / $1.h.fair }), x.l.askingPrice / x.h.fair < ratioMax else { break }
                    _ = e.beginNegotiation(listingID: x.l.id, companyID: id)
                    var neg = pushes > 0 ? e.pushPrice(listingID: x.l.id, companyID: id) : MarketNegotiation(listingID: x.l.id, price: x.l.askingPrice, canDiscuss: false, patienceLeft: 0, mood: .open, lastMessage: "")
                    if pushes > 1, neg.canDiscuss { neg = e.pushPrice(listingID: x.l.id, companyID: id) }
                    guard e.state.company(id)!.cash > neg.price * 1.1, e.buyListing(listingID: x.l.id, companyID: id, price: neg.price) == .applied else { break }
                    bought += 1; n += 1; if x.h.kind == 2 { lemons += 1 }
                }
                for _ in 0..<7 {
                    _ = e.nextDay()
                    for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
                    if let co = e.state.company(id), co.cash < -50_000 { let top = -co.cash + 100_000; e.update { s, _, _ in Payments.injectCash(&s, companyID: id, amount: top) }; injected += top }
                }
                let co = e.state.company(id)!
                if week >= 104 { sold += co.value("lastW")["units"].double; stockSum += co.inventory; weeks += 1 }
            }
            let co = e.state.company(id)!
            let h = co.monthlyHistory
            let y3 = h.suffix(12).reduce(0) { $0 + $1.profit }, y2 = h.dropLast(12).suffix(12).reduce(0) { $0 + $1.profit }
            let invested = cash0 + injected
            let dm = DemandModel.compute(co, e.data.catalog["usedcar"]!, World(state: e.state, data: e.data)); let cm = CapacityModel.compute(co, e.data.catalog["usedcar"]!, World(state: e.state, data: e.data))
            report += "demand \(dm.parts.map { "\($0.name)=\(($0.value * 1000).rounded() / 1000)" }) cap \(cm.capacity) \(cm.parts.map { "\($0.key)=\($0.have)" }) rep \(co.reputation) aware \(co.awareness)\n"
            report += "PROBE seed \(seed): setup \(est) invested \(invested) bought \(bought) lemons \(lemons) | year 3: sold \(sold) avg stock \(stockSum / Double(weeks)) profit y2 \(y2) y3 \(y3) -> return y3 \(y3 / invested * 100)% (y2 \(y2 / invested * 100)%) cars in yard \(e.usedCarStock(companyID: id).count) staff \(co.staff.count)\n"
        }
        print(report)
    }
}
