import XCTest
import GameCore
import Countries
import Finance
import Simulation
@testable import Businesses
@testable import Events

private extension GameEngine {
    mutating func week() { for _ in 0..<7 { _ = nextDay() } }
}

final class IntegrationBalanceTests: XCTestCase {
    func engine(_ trade: String = "bakery", weeks: Int = 3, seed: Int = 7) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 200_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, quickSetup: false) else { throw XCTSkip("could not start") }
        e.update { s, d, _ in _ = CompanySetup.quickSetupReport(&s, companyID: id, data: d, options: CompanySetup.SetupOptions(optionalEquipment: true)) }
        for _ in 0..<weeks { e.week() }
        var extra = 0
        while e.state.company(id)?.status != .open, extra < 40 { e.week(); extra += 1 }
        return (e, id)
    }

    func cafe(weeks: Int = 6) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 777)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 400_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: "cafe", cityID: s.player.cityID, size: 1, state: s, data: data)
            _ = Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6 + 3_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        for _ in 0..<(weeks * 7) { _ = e.nextDay() }
        return (e, id)
    }

    func giveAdvisorDuty(_ e: inout GameEngine, _ id: Int) throws {
        e.update { s, _, _ in
            guard let i = s.companyIndex(id), !s.companies[i].staff.isEmpty else { return }
            s.companies[i].staff[0].set("duty", NewItemOptions.advisorRole)
        }
        guard e.hasMarketAdvisor(companyID: id) else { throw XCTSkip("no staff to give the duty") }
    }

    func testEightWeekRunAfterAddingAnItemMatchesTheEstimate() throws {
        var (e, id) = try engine(weeks: 70)
        try giveAdvisorDuty(&e, id)
        let opt = try XCTUnwrap(e.newItemOptions(companyID: id, isService: false).options.first)
        let estimate = try XCTUnwrap(opt.profitChange)
        XCTAssertEqual(e.addNewItem(companyID: id, optionID: opt.id), .applied)
        var deltas: [Double] = []
        for wk in 1...8 {
            e.week()
            guard wk >= 5 else { continue }
            var s = e.state
            let d = e.data
            let i = s.companyIndex(id)!
            let co = s.companies[i], bd = d.catalog[co.type]!
            let w = World(state: s, data: d)
            let with = DemandModel.compute(co, bd, w).customers
            s.companies[i].set("lift27", .null)
            let without = DemandModel.compute(s.companies[i], bd, World(state: s, data: d)).customers
            let cap = CapacityModel.compute(co, bd, w).capacity
            deltas.append((min(with, cap) - min(without, cap)) * SalesItems.marketTicket(co, bd, w) * (1 - bd.costOfSales))
        }
        let avg = deltas.reduce(0, +) / Double(deltas.count)
        XCTAssertGreaterThan(avg, 0)
        XCTAssertEqual(avg, estimate, accuracy: estimate * 0.3, "8-week run \(avg) vs estimate \(estimate)")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testRivalGroupEntryAddsCountryPressure() throws {
        var (e, id) = try engine()
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            MarketPressure.add(&s, i, kind: .country, amount: 0.03, weeks: 26)
        }
        let co = e.state.company(id)!
        XCTAssertEqual(MarketPressure.demandMultiplier(co, week: e.state.week), 0.97, accuracy: 1e-9)
        XCTAssertEqual(MarketPressure.demandMultiplier(co, week: e.state.week + 13), 0.985, accuracy: 1e-9)
        XCTAssertEqual(MarketPressure.demandMultiplier(co, week: e.state.week + 26), 1, accuracy: 1e-9)
    }

    func testEventsAreCappedAndDeduped() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5)
        e.update { s, _, _ in
            s.week = 20
            for n in 0..<6 { MarketEvents.log(&s, .competitorLaunch, title: "Rival \(n) launches", detail: "d", companyID: 1) }
            for n in 0..<6 { MarketEvents.log(&s, .recognition, title: "Person \(n)", detail: "d", companyID: 1, employeeID: n) }
        }
        XCTAssertEqual(e.marketEvents(limit: 50).filter { $0.kind == .competitorLaunch }.count, 1, "one market-wide event a week")
        XCTAssertEqual(e.marketEvents(limit: 50).count, 3, "at most 3 a week")
        e.update { s, _, _ in
            s.week = 21
            XCTAssertTrue(MarketEvents.log(&s, .competitorLaunch, title: "Rival 0 launches", detail: "d", companyID: 1) == false, "the same fact is not written again within 4 weeks")
            XCTAssertTrue(MarketEvents.log(&s, .competitorLaunch, title: "Rival 0 launches", detail: "d", companyID: 2), "another company is another fact")
            s.week = 25
            XCTAssertTrue(MarketEvents.log(&s, .competitorLaunch, title: "Rival 0 launches", detail: "d", companyID: 1), "after 4 weeks it may be news again")
        }
        XCTAssertEqual(e.marketEvents(limit: 50).count, 5)
    }

    func testSupplierEventCarriesTheCostFigure() throws {
        var (e, id) = try engine(weeks: 4)
        e.update { s, data, _ in
            var mv = s.rest["mev"] ?? .object([:]); mv["seen"]["eco"] = .null; s.rest["mev"] = mv
            MarketEvents.weekly(&s, data: data)
            s.week += 1
            s.economy.materials *= 1.10
            MarketEvents.weekly(&s, data: data)
        }
        let ev = try XCTUnwrap(e.marketEvents(limit: 20).first { $0.kind == .supplierPriceChange })
        XCTAssertEqual(ev.amount ?? 0, 0.10, accuracy: 0.011)
        XCTAssertFalse(ev.consequence.isEmpty)
        XCTAssertTrue(ev.consequence.contains("a week") || ev.consequence.contains("%"), ev.consequence)
        _ = id
    }

    func testMajorContractOfferIsReallyThere() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5)
        e.update { s, _, _ in
            var co = Company(raw: [:]); co.set("rv26", .array([.number(1000), .number(1000)])); co.set("id", 9); co.set("name", "Test Co")
            MarketEvents.noteContractOffer(&s, company: co, customer: "Acme", worth: 3000)
            s.week += 1
            MarketEvents.noteContractOffer(&s, company: co, customer: "Beta", worth: 3000, outcome: "Sam signed it.")
        }
        let ev = e.marketEvents(limit: 5)
        XCTAssertEqual(ev.first?.consequence, "Sam signed it.")
        XCTAssertTrue(ev.last?.consequence.contains("inbox") ?? false)
    }

    func testBrandValueGrowsWithEachPartAndIsUsedInPrices() throws {
        var (e, id) = try engine()
        let base = e.brandValue(companyID: id)
        XCTAssertTrue((0...100).contains(base))
        e.update { s, _, _ in let i = s.companyIndex(id)!; s.companies[i].reputation = 90; s.companies[i].awareness = 80 }
        let rep = e.brandValue(companyID: id)
        XCTAssertGreaterThan(rep, base)
        e.update { s, _, _ in s.week += 52 * 6 }
        let years = e.brandValue(companyID: id)
        XCTAssertGreaterThan(years, rep)
        e.update { s, _, _ in s.rest["aw56"] = .object(["won": .array((0..<5).map { _ in .object(["k": "boty"]) })]) }
        let awards = e.brandValue(companyID: id)
        XCTAssertGreaterThan(awards, years)
        e.update { s, _, _ in
            var fr = s.company(id)!.value("fr"); fr = .object(["on": 1, "units": .array((0..<12).map { _ in .object([:]) }), "masters": .array([])])
            s.companies[s.companyIndex(id)!].set("fr", fr)
        }
        let reach = e.brandValue(companyID: id)
        XCTAssertGreaterThan(reach, awards)
        let g = e.groupBrandValue()
        XCTAssertEqual(g.score, g.reputation + g.yearsTrading + g.reach + g.awards, accuracy: 1e-9)
        XCTAssertTrue((0...100).contains(g.score))
        XCTAssertGreaterThan(BrandValues.salePremium(80), BrandValues.salePremium(20))
        XCTAssertEqual(BrandValues.salePremium(0), 1)
        XCTAssertLessThanOrEqual(BrandValues.salePremium(100), 1.1 + 1e-12)
        XCTAssertGreaterThan(BrandValues.feeFactor(100), 1)
        XCTAssertGreaterThan(BrandValues.openingAwareness(flagshipAwareness: 80, score: 70), BrandValues.openingAwareness(flagshipAwareness: 20, score: 10))
        XCTAssertGreaterThanOrEqual(BrandValues.openingAwareness(flagshipAwareness: 0, score: 0), 10)
    }

    func testSaleOffersAndLicenceFeesPayForTheBrand() throws {
        var (e, id) = try engine(weeks: 6)
        e.update { s, _, _ in
            s.companies[s.companyIndex(id)!].foundedWeek = s.week - 60
            Ledger.set(&s, to: 0)
            _ = CompanySale.startListing(&s, companyID: id)
        }
        var plain = e
        var famous = e
        famous.update { s, _, _ in s.rest["aw56"] = .object(["won": .array((0..<10).map { _ in .object(["k": "boty"]) })]) }
        func firstOffer(_ g: inout GameEngine) -> Double? {
            for _ in 0..<400 {
                g.update { s, d, ctx in s.week += 1; CompanySale.weekly(&s, data: d, context: ctx) }
                if let o = CompanySale.listing(g.state, companyID: id)?.offers.first { return o.price }
            }
            return nil
        }
        guard let p = firstOffer(&plain), let f = firstOffer(&famous) else { throw XCTSkip("no offer came") }
        let score = BrandValues.company(famous.state, famous.state.company(id)!).score
        let ratio = BrandValues.salePremium(score) / BrandValues.salePremium(BrandValues.company(plain.state, plain.state.company(id)!).score)
        XCTAssertGreaterThan(f, p)
        XCTAssertEqual(f / p, ratio, accuracy: 0.01 + 2000 / p)

        func masterFee(awards: Int) throws -> Double {
            var g = e
            g.update { s, d, _ in
                s.rest["aw56"] = .object(["won": .array((0..<awards).map { _ in .object(["k": "boty"]) })])
                let i = s.companyIndex(id)!
                s.companies[i].set("fr", .object(["on": 1, "fee": .number(1_000_000), "roy": 0.06, "supp": 1, "brand": 15, "units": .array([]), "app": .array([]), "masters": .array([])]))
                Ledger.set(&s, to: 900_000_000)
            }
            var gained = 0.0
            g.update { s, d, _ in
                let before = s.company(id)!.cash
                XCTAssertEqual(Franchising.sellMaster(&s, companyID: id, country: "DE", data: d), .ok)
                gained = s.company(id)!.cash - before
            }
            return gained
        }
        XCTAssertGreaterThan(try masterFee(awards: 12), try masterFee(awards: 0))
    }

    func testNewStoresOfAKnownBrandOpenWithAHeadStart() throws {
        var (e, id) = try cafe()
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].awareness = 90; s.companies[i].reputation = 90
            s.rest["aw56"] = .object(["won": .array((0..<10).map { _ in .object(["k": "boty"]) })])
        }
        var newID: Int?
        e.update { s, d, ctx in
            var docs = s.companies[s.companyIndex(id)!].value("docs"); docs["chain"] = .object(["st": "ok"]); s.companies[s.companyIndex(id)!].set("docs", docs)
            guard let chainID = Chains.make(&s, companyID: id, name: "Test Chain") else { return }
            if case .success(let n) = Chains.openStore(&s, chainID: chainID, cityID: s.company(id)!.cityID, size: 1, data: d, context: ctx) { newID = n }
        }
        guard let n = newID else { throw XCTSkip("could not open a store") }
        XCTAssertGreaterThan(e.state.company(n)!.awareness, 10, "a brand-new name starts at 10; a known brand's store starts higher")
        XCTAssertLessThanOrEqual(e.state.company(n)!.awareness, 45)
    }

    func testResearchIsBoughtDeliveredAndHalvedByAnAdvisor() throws {
        var (e, id) = try engine()
        let opts = e.researchOptions(companyID: id)
        XCTAssertEqual(Set(opts.map { $0.id }), ["forecast", "rivals", "benchmark", "product"])
        XCTAssertTrue(opts.allSatisfy { $0.cost > 0 && $0.weeks >= 1 })
        let forecast = try XCTUnwrap(opts.first { $0.id == "forecast" })
        let cash = e.state.company(id)!.cash
        XCTAssertEqual(e.buyResearch(companyID: id, optionID: "forecast"), .applied)
        XCTAssertEqual(e.state.company(id)!.cash, cash - forecast.cost, accuracy: 0.5)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        if case .refused = e.buyResearch(companyID: id, optionID: "forecast") {} else { XCTFail("already on its way") }
        if case .refused = e.buyResearch(companyID: id, optionID: "nope") {} else { XCTFail("unknown report") }
        XCTAssertTrue(e.research(companyID: id).isEmpty, "not yet")
        let inbox = e.state.inbox.count
        for _ in 0..<(forecast.weeks + 1) { e.week() }
        let reports = e.research(companyID: id)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports[0].optionID, "forecast")
        XCTAssertTrue(reports[0].findings.count >= 2 && reports[0].findings.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(reports[0].findings[0].contains("%"))
        XCTAssertGreaterThan(e.state.inbox.count, inbox, "an inbox message tells you")
        for o in ["rivals", "benchmark", "product"] {
            XCTAssertEqual(e.buyResearch(companyID: id, optionID: o), .applied)
        }
        for _ in 0..<5 { e.week() }
        let all = e.research(companyID: id)
        XCTAssertEqual(all.count, 4)
        XCTAssertTrue(all.allSatisfy { !$0.findings.isEmpty })
        XCTAssertTrue(all.first { $0.optionID == "product" }!.findings[0].hasPrefix("Best next product"))
        try giveAdvisorDuty(&e, id)
        let cheap = e.researchOptions(companyID: id)
        for (a, b) in zip(opts, cheap) {
            XCTAssertEqual(b.cost, (a.cost / 2).rounded(), accuracy: 1.5)
            XCTAssertEqual(b.weeks, max(1, (a.weeks + 1) / 2))
        }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testSellerCanOnlySupplyWhatItsCapacityAllows() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 7)
        e.update { s, _, _ in Ledger.move(&s, .me, 90_000_000, why: "Test funds") }
        let city = e.state.player.cityID
        guard case .success(let seller) = e.startCompany(tradeID: "webdev", cityID: city),
              case .success(let buyer) = e.startCompany(tradeID: "cons", cityID: city) else { throw XCTSkip("could not start") }
        for _ in 0..<14 { _ = e.nextDay() }
        let item = e.salesItems(companyID: seller)[0]
        XCTAssertEqual(e.setItemListedForGroup(companyID: seller, itemID: item.id, listed: true), .applied)
        e.update { s, _, _ in let i = s.companyIndex(seller)!; var lw = s.companies[i].value("lastW"); lw["cap"] = 10; lw["units"] = 10; s.companies[i].set("lastW", lw) }
        XCTAssertEqual(e.ownCompanyListings(forBuyer: buyer).first?.available, 0)
        if case .refused(let why) = e.buyFromOwnCompany(buyer: buyer, seller: seller, itemID: item.id, quantity: 1) { XCTAssertTrue(why.contains("capacity")) } else { XCTFail("no capacity, no sale") }
        e.update { s, d, _ in
            let i = s.companyIndex(seller)!
            let co = s.companies[i], bd = d.catalog[co.type]!
            let w = World(state: s, data: d)
            let per = OwnListings.slotsPerUnit(price: item.price, seller: co, bd, w)
            var lw = co.value("lastW"); lw["cap"] = .number(10 + per * 1.5); lw["units"] = 10; s.companies[i].set("lastW", lw)
        }
        let listing = try XCTUnwrap(e.ownCompanyListings(forBuyer: buyer).first)
        XCTAssertEqual(listing.available, 1)
        let sellerRev = e.state.company(seller)!.books.month["rev"] ?? 0
        let sellerCogs = e.state.company(seller)!.books.month["cogs"] ?? 0
        XCTAssertEqual(e.buyFromOwnCompany(buyer: buyer, seller: seller, itemID: item.id, quantity: 3), .applied)
        let sold = (e.state.company(seller)!.books.month["rev"] ?? 0) - sellerRev
        XCTAssertEqual(sold, listing.price.rounded(), accuracy: 1, "one unit supplied, not three")
        let cogs = (e.state.company(seller)!.books.month["cogs"] ?? 0) - sellerCogs
        XCTAssertEqual(cogs, sold * IntercompanySupply.varRatio(e.state.company(seller)!, data: e.data), accuracy: 1, "cost of sales on what was supplied")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        XCTAssertEqual(e.ownCompanyListings(forBuyer: buyer).first?.available ?? 0, 0)
        e.update { s, _, _ in s.week += 1 }
        XCTAssertEqual(e.ownCompanyListings(forBuyer: buyer).first?.available, 1)
    }

    func testPressureLiftAndResearchSurviveSaveAndStayDeterministic() throws {
        var (a, id) = try engine()
        a.addSalesItem(companyID: id, name: "Test special", isService: false)
        a.buyResearch(companyID: id, optionID: "benchmark")
        a.update { s, _, _ in MarketPressure.add(&s, s.companyIndex(id)!, kind: .launch, amount: 0.05, weeks: 6, rivalID: 1) }
        var b = a
        let loaded = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(a.state))
        XCTAssertTrue(loaded == a.state)
        let (data, events, marketing) = try GameEngine.loadResources()
        var c = GameEngine(state: loaded, data: data, events: events, marketing: marketing)
        for _ in 0..<4 { a.week(); b.week(); c.week() }
        XCTAssertTrue(a.state == b.state, "same inputs, same game")
        XCTAssertTrue(a.state == c.state, "a reloaded game plays on the same")
        XCTAssertEqual(a.research(companyID: id), c.research(companyID: id))
        XCTAssertEqual(a.research(companyID: id).count, 1)
        XCTAssertEqual(a.marketEvents(limit: 60), c.marketEvents(limit: 60))
        XCTAssertTrue(Ledger.gaps(a.state).isEmpty)
    }
}
