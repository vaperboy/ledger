import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

final class FinanceItemsTests: XCTestCase {
    static let all = ["insco", "bank", "fund", "power", "oilgas"]

    struct Run { var e: GameEngine; var id: Int; var invested: Double }

    static func start(_ trade: String, seed: Int = 11) throws -> Run {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
        var id = 0, invested = 0.0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 20_000_000_000, why: "Test funds")
            guard case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, data: data, context: ctx) else { return }
            id = i
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, size: 1, state: s, data: data)
            invested = (est?.total ?? 1_000_000) * 1.3
            Payments.injectCash(&s, companyID: id, amount: invested)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
            if let co = s.company(id), let bd = data.catalog[co.type], (bd.ownerFTE == 0 || bd.standardStaff.reduce(0, { $0 + $1.count }) >= 4), !bd.hasTrait("noStaff"), co.managerID == nil {
                for _ in 0..<6 {
                    let c = ManagerModel.generateCandidate(company: s.company(id), type: bd.managerType, state: &s, data: data)
                    if ManagerModel.hire(&s, personID: c.id, companyID: id, monthlyWage: c.askingMonthlyWage * 1.2, data: data) == .ok { break }
                }
            }
        }
        var r = Run(e: e, id: id, invested: invested)
        for _ in 0..<110 where r.e.state.company(id)?.status != .open { week(&r, withItems: false) }
        let rid = r.id
        r.e.update { s, data, _ in
            guard let i = s.companyIndex(rid), s.companies[i].type == "oilgas", s.companies[i].status == .open else { return }
            Payments.injectCash(&s, companyID: rid, amount: 6_000_000_000)
            _ = EnergyModel.acquire(&s, i, kbbl: 2000, data: data)
            _ = EnergyModel.acquire(&s, i, kbbl: 1000, data: data)
        }
        return r
    }

    static func week(_ r: inout Run, withItems: Bool) {
        for _ in 0..<7 {
            r.e.nextDay()
            for m in r.e.openDecisions where m.actionID.hasPrefix("pay29") { r.e.answer(messageID: m.id, option: 0) }
        }
        let id = r.id
        if let co = r.e.state.company(id), co.status.isLive, co.cash < -50_000 {
            let top = -co.cash + 100_000
            r.e.update { s, _, _ in Payments.injectCash(&s, companyID: id, amount: top) }
            r.invested += top
        }
        if withItems { r.e.update { s, d, _ in for i in s.companies.indices { FinanceItems.weekly(&s, i, data: d) } } }
    }

    func testRegistryHoldsTheSixTradesAndNothingElse() {
        XCTAssertEqual(ItemTradeGroups.finance, Set(Self.all))
        XCTAssertTrue(ItemTradeGroups.finance.isDisjoint(with: ItemTradeGroups.brokered.union(ItemTradeGroups.retail).union(ItemTradeGroups.food).union(ItemTradeGroups.rentals)))
    }

    func testEveryTradeSellsRealProductsWithEconomics() throws {
        for t in Self.all {
            var r = try Self.start(t)
            guard r.id != 0 else { throw XCTSkip("could not start \(t)") }
            for _ in 0..<8 { Self.week(&r, withItems: true) }
            let co = r.e.state.company(r.id)!, bd = r.e.data.catalog[t]!
            XCTAssertFalse(co.value("w11").isNull, t)
            let eco = FinanceItems.allEconomics(r.e.state, companyID: r.id, data: r.e.data)
            XCTAssertFalse(eco.isEmpty, "\(t) has no product lines as items")
            let items = SalesItems.items(co, bd)
            XCTAssertFalse(items.contains { $0.id.hasPrefix("d") }, "\(t): the title-only defaults are replaced")
            XCTAssertEqual(items.reduce(0.0) { $0 + $1.unitShare }, 1, accuracy: 1e-9, t)
            XCTAssertEqual(items.reduce(0.0) { $0 + $1.unitShare * $1.ratio }, 1, accuracy: 1e-9, "\(t) revenue weights")
            XCTAssertEqual(SalesItems.demandFactor(co), 1, accuracy: 1e-12, t)
            XCTAssertEqual(SalesItems.ticketFactor(co), 1, accuracy: 1e-12, t)
            for e in eco {
                let rec = ItemModels.record(co, itemID: e.itemID)
                XCTAssertNotNil(rec, "\(t) \(e.name)")
                XCTAssertGreaterThan(e.marketPrice, 0, "\(t) \(e.name) has a price")
                XCTAssertFalse(e.parts.isEmpty && e.overheadPerUnit == 0 && e.volume > 0, "\(t) \(e.name) has a cost")
                let list = SalesItems.rows(r.e.state, companyID: r.id, data: r.e.data).first { $0.id == e.itemID }!
                if let rec, e.costPerUnit > 0, e.marketPrice > 0 {
                    XCTAssertEqual(rec.cost / list.marketPrice, e.costPerUnit / e.marketPrice, accuracy: 1e-9, "\(t) \(e.name) record cost keeps its share of the price")
                    XCTAssertEqual(ItemModels.liveProfit(price: rec.cost * 1.2, cost: ItemModels.unitCost(rec)).outcome, .profit)
                    XCTAssertEqual(ItemModels.liveProfit(price: rec.cost * 0.8, cost: ItemModels.unitCost(rec)).outcome, .loss)
                    XCTAssertEqual(ItemModels.liveProfit(price: rec.cost, cost: ItemModels.unitCost(rec)).outcome, .breakEven)
                }
            }
            XCTAssertTrue(Ledger.gaps(r.e.state).isEmpty, "\(t): \(Ledger.gaps(r.e.state))")
        }
    }

    func testInsuranceCoversAddUpToThePremiumBook() throws {
        var r = try Self.start("insco")
        for _ in 0..<30 { Self.week(&r, withItems: true) }
        let co = r.e.state.company(r.id)!
        let fm = co.value("fm")
        let eco = FinanceItems.allEconomics(r.e.state, companyID: r.id, data: r.e.data)
        XCTAssertEqual(eco.count, 6)
        guard fm["pol"].double > 0 else { throw XCTSkip("no policies sold yet") }
        XCTAssertEqual(eco.reduce(0.0) { $0 + $1.units }, fm["pol"].double, accuracy: 1e-6 * fm["pol"].double)
        XCTAssertEqual(eco.reduce(0.0) { $0 + $1.volume * $1.price }, fm["premW"].double, accuracy: 1e-6 * fm["premW"].double, "item premiums are the premium the model books")
        let claims = eco.reduce(0.0) { $0 + $1.volume * ($1.parts.first { $0.label == "Expected claims" }?.perUnit ?? 0) }
        XCTAssertEqual(claims / fm["premW"].double, fm["lossR"].double, accuracy: 1e-6, "item claims are the loss ratio of the book")
        XCTAssertTrue(eco.filter { $0.units > 0 }.allSatisfy { $0.reserve > 0 && $0.risk > 0 })
    }

    func testBankLoansCarryFundingCostAndCreditLoss() throws {
        var r = try Self.start("bank")
        for _ in 0..<20 { Self.week(&r, withItems: true) }
        let eco = FinanceItems.allEconomics(r.e.state, companyID: r.id, data: r.e.data)
        XCTAssertEqual(eco.filter { $0.kindLabel == "Loan" }.count, 4)
        XCTAssertEqual(eco.filter { $0.kindLabel == "Deposit account" }.count, 2)
        let card = eco.first { $0.itemID == "w11:card" }!, mort = eco.first { $0.itemID == "w11:mort" }!
        XCTAssertGreaterThan(card.risk / card.marketPrice, mort.risk / mort.marketPrice, "a card loses more of what it earns than a mortgage")
        XCTAssertTrue(eco.filter { $0.kindLabel == "Loan" }.allSatisfy { $0.parts.contains { $0.label == "Expected credit loss" } && $0.reserve >= 0 })
    }

    func testOilFieldsAreItemsAndTheOilPriceExposureShows() throws {
        var r = try Self.start("oilgas")
        for _ in 0..<6 { Self.week(&r, withItems: true) }
        let fields = r.e.state.company(r.id)!.value("fm")["fields"].array
        let eco = FinanceItems.allEconomics(r.e.state, companyID: r.id, data: r.e.data)
        XCTAssertEqual(eco.count, fields.filter { $0["st"].string != "depleted" }.count)
        XCTAssertGreaterThan(eco.count, 0)
        for e in eco {
            XCTAssertTrue(e.parts.contains { $0.label == "Lifting cost" && $0.perUnit > 0 })
            XCTAssertGreaterThan(e.risk, 0, "spot sales are exposed to the oil price")
            XCTAssertEqual(ItemModels.record(r.e.state.company(r.id)!, itemID: e.itemID)?.model, .proj)
        }
        r.e.update { s, d, _ in
            guard let i = s.companyIndex(r.id) else { return }
            var k = s.companies[i].value("knob"); k["sell"] = 1; s.companies[i].set("knob", k)
        }
        let after = FinanceItems.allEconomics(r.e.state, companyID: r.id, data: r.e.data)
        XCTAssertLessThan(after[0].risk / after[0].price, eco[0].risk / eco[0].price)
    }

    func testPowerTariffsShareTheOutputAndTheHedgeMovesThem() throws {
        var r = try Self.start("power")
        for _ in 0..<10 { Self.week(&r, withItems: true) }
        let out = r.e.state.company(r.id)!.value("lastW")["units"].double
        let spotMix = FinanceItems.allEconomics(r.e.state, companyID: r.id, data: r.e.data)
        XCTAssertEqual(spotMix.count, 3)
        XCTAssertEqual(spotMix.reduce(0.0) { $0 + $1.volume }, out, accuracy: 1e-6 * max(1, out))
        XCTAssertEqual(spotMix.first { $0.itemID == "w11:green" }!.volume, out, accuracy: 1e-6 * max(1, out), "all spot when the price strategy is spot")
        r.e.update { s, _, _ in
            guard let i = s.companyIndex(r.id) else { return }
            var k = s.companies[i].value("knob"); k["hedge"] = 2; s.companies[i].set("knob", k)
        }
        let hedged = FinanceItems.allEconomics(r.e.state, companyID: r.id, data: r.e.data)
        XCTAssertEqual(hedged.first { $0.itemID == "w11:green" }!.volume, out * 0.1, accuracy: 1e-6 * max(1, out))
        XCTAssertEqual(hedged.reduce(0.0) { $0 + $1.volume }, out, accuracy: 1e-6 * max(1, out))
    }

    func testFundFeeClassesAddUpToTheManagementFee() throws {
        var r = try Self.start("fund")
        for _ in 0..<30 { Self.week(&r, withItems: true) }
        let co = r.e.state.company(r.id)!
        let eco = FinanceItems.allEconomics(r.e.state, companyID: r.id, data: r.e.data)
        XCTAssertEqual(eco.count, 6)
        let aum = co.value("fm")["aum"].double
        XCTAssertEqual(eco.reduce(0.0) { $0 + $1.size }, aum, accuracy: 1e-6 * max(1, aum))
        let fee = eco.reduce(0.0) { $0 + $1.volume * $1.price }
        let model = aum * 0.015 / 52 * Knobs.effect(co, r.e.data.catalog["fund"]!, "t", World(state: r.e.state, data: r.e.data))
        XCTAssertEqual(fee, model, accuracy: 1e-6 * max(1, model), "item fees are the fee the model books")
        XCTAssertLessThan(eco.first { $0.itemID == "w11:idx" }!.price / eco.first { $0.itemID == "w11:prop" }!.price, 0.5, "an index class is cheaper than a property fund")
    }

    func testOldSavesAndOtherTradesAreUntouched() throws {
        var r = try Self.start("insco")
        for _ in 0..<3 { Self.week(&r, withItems: false) }
        let co = r.e.state.company(r.id)!
        XCTAssertFalse(co.value("w11").isNull)
        var other = try Self.start("bakery")
        for _ in 0..<2 { Self.week(&other, withItems: true) }
        XCTAssertTrue(other.e.state.company(other.id)!.value("w11").isNull)
    }

    func testSecondSyncChangesNothingAndKeepsOwnerPrices() throws {
        var r = try Self.start("bank")
        for _ in 0..<4 { Self.week(&r, withItems: true) }
        let item = "w11:mort"
        let market = SalesItems.rows(r.e.state, companyID: r.id, data: r.e.data).first { $0.id == item }!.marketPrice
        r.e.update { s, d, _ in SalesItems.setPrice(&s, companyID: r.id, itemID: item, price: market * 1.2, data: d) }
        r.e.update { s, d, _ in FinanceItems.sync(&s, companyID: r.id, data: d) }
        XCTAssertEqual(SalesItems.items(r.e.state.company(r.id)!, r.e.data.catalog["bank"]!).first { $0.id == item }!.priceMultiplier, 1.2, accuracy: 1e-9)
        let e = FinanceItems.economics(r.e.state, companyID: r.id, itemID: item, data: r.e.data)!
        XCTAssertEqual(e.price / e.marketPrice, 1.2, accuracy: 1e-9, "the slider moves the price the economics are shown at")
    }

    func testTwoYearProbePerTrade() throws {
        for t in Self.all {
            var base = try Self.start(t), withItems = try Self.start(t)
            guard base.id != 0 else { throw XCTSkip("could not start \(t)") }
            for _ in 0..<104 { Self.week(&base, withItems: false); Self.week(&withItems, withItems: true) }
            func profit(_ r: Run) -> (Double, Double, Double) {
                let h = r.e.state.company(r.id)!.monthlyHistory
                return (h.prefix(12).reduce(0) { $0 + $1.profit }, h.suffix(12).reduce(0) { $0 + $1.profit }, r.e.state.company(r.id)!.cash)
            }
            let b = profit(base), w = profit(withItems)
            let itemProfit = FinanceItems.allEconomics(withItems.e.state, companyID: withItems.id, data: withItems.e.data).reduce(0.0) { $0 + $1.weeklyProfit }
            print(String(format: "FINANCEPROBE %@ | before y1 %.0f y2 %.0f cash %.0f | after y1 %.0f y2 %.0f cash %.0f | invested %.0f | items weekly %.0f", t, b.0 / 1000, b.1 / 1000, b.2 / 1000, w.0 / 1000, w.1 / 1000, w.2 / 1000, withItems.invested / 1000, itemProfit / 1000))
            XCTAssertEqual(w.1, b.1, accuracy: max(1, abs(b.1) * 0.02), "\(t): the withItems must not change what the trade earns at default prices")
            XCTAssertTrue(Ledger.gaps(withItems.e.state).isEmpty, "\(t)")
        }
    }
}
