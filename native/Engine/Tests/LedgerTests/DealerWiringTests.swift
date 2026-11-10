import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation
@testable import Businesses

final class DealerWiringTests: XCTestCase {
    private func game(trade: String, seed: Int = 7, cash: Double = 900_000_000) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 2_000_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID) else { throw XCTSkip("no company") }
        _ = e.quickSetup(companyID: id)
        _ = e.openCompany(companyID: id)
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .open } }
        return (e, id)
    }
    private func balanced(_ e: GameEngine, _ what: String) { XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(what): \(Ledger.gaps(e.state))") }
    private func days(_ e: inout GameEngine, _ n: Int) { for _ in 0..<n { _ = e.nextDay() } }
    private func ready(_ e: inout GameEngine, _ id: Int) {
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].openedWeek = s.week - 30; s.companies[i].reputation = 70 } }
        for a in DealerAddon.allCases { XCTAssertEqual(e.startDealerAddonSetup(companyID: id, addon: a), .applied) }
        days(&e, 7 * 8)
        for a in DealerAddon.allCases { XCTAssertEqual(e.setDealerAddonEnabled(companyID: id, addon: a, on: true), .applied) }
    }

    func testWarrantyReserveIsADebtAndNeverPaidAsABill() throws {
        var (e, id) = try game(trade: "usedcar")
        let before = CompanyFigures.billsOwed(e.state.company(id)!)
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].payables["warr"] = 50_000 } }
        XCTAssertEqual(CompanyFigures.billsOwed(e.state.company(id)!) - before, 50_000, accuracy: 0.01)
        days(&e, 70)
        XCTAssertEqual(e.state.company(id)!.payables["warr"] ?? 0, 50_000, accuracy: 0.01, "paydays and month ends never pay the reserve")
    }

    func testUsedCarSalesRunTheAddOnsAndTheBooksBalance() throws {
        var (e, id) = try game(trade: "usedcar")
        ready(&e, id)
        for x in Marketplace.pool(e.state, companyID: id, data: e.data).filter({ $0.h.vehicle && $0.h.equipmentID.isEmpty && $0.h.kind != 2 }).prefix(6) {
            _ = e.buyListing(listingID: x.l.id, companyID: id, price: x.l.askingPrice)
        }
        _ = e.setUsedCarMarkup(companyID: id, percent: 0)
        days(&e, 7 * 30)
        let t = try XCTUnwrap(e.dealerAddonTotals(companyID: id))
        let sold = e.usedCarSales(companyID: id).count
        XCTAssertGreaterThan(sold, 0)
        XCTAssertGreaterThan(t.warrantiesSold + t.financedSales + t.policies + t.financeDeclined, 0, "add-ons were offered on the sales (\(sold) sold)")
        balanced(e, "used car add-ons")
    }

    func testNewCarSalesRunTheAddOnsAndTheBooksBalance() throws {
        var (e, id) = try game(trade: "cardealer", cash: 1_500_000_000)
        ready(&e, id)
        let offers = e.carDealerOffers(companyID: id)
        for k in 0..<4 { let o = offers[(k * 7) % offers.count]; _ = e.carDealerOrder(companyID: id, brandID: o.brandID, modelID: o.modelID) }
        days(&e, 7 * 30)
        let t = try XCTUnwrap(e.dealerAddonTotals(companyID: id))
        XCTAssertGreaterThan(t.warrantiesSold + t.financedSales + t.policies + t.financeDeclined, 0, "add-ons were offered on the sales")
        balanced(e, "new car add-ons")
    }

    func testOwnGarageBillCarriesVatInTheSameCountry() throws {
        var (e, id) = try game(trade: "usedcar")
        guard case .success(let rid) = e.startCompany(tradeID: "carrepair", cityID: e.state.player.cityID) else { throw XCTSkip("no mechanic") }
        _ = e.quickSetup(companyID: rid)
        _ = e.openCompany(companyID: rid)
        e.update { s, _, _ in if let i = s.companyIndex(rid) { s.companies[i].status = .open } }
        e.update { s, _, _ in
            for cid in [rid, id] {
                let i = s.companyIndex(cid)!
                s.companies[i].monthlyHistory = (0..<12).map { MonthRecord(monthIndex: $0, revenue: 2_000_000_000, profit: 0, cash: 0) }
                var lw = s.companies[i].value("lastW"); lw["rev"] = .number(5_000_000); s.companies[i].set("lastW", lw)
            }
        }
        let lemon = try XCTUnwrap(Marketplace.pool(e.state, companyID: id, data: e.data).first { $0.h.vehicle && $0.h.equipmentID.isEmpty && $0.h.kind == 2 })
        _ = e.buyListing(listingID: lemon.l.id, companyID: id, price: lemon.l.askingPrice)
        days(&e, 15)
        let c = try XCTUnwrap(e.usedCarStock(companyID: id).first)
        XCTAssertEqual(c.repairSupplierID, rid)
        let vat0 = e.state.company(rid)!.vatBalance
        let dealerVat0 = e.state.company(id)!.vatBalance
        var billed = false
        e.update { s, d, _ in
            let i = s.companyIndex(id)!
            guard let k = s.companies[i].value("stk").array.firstIndex(where: { $0["id"].int == c.id }) else { return }
            var car = s.companies[i].value("stk").array[k]
            billed = UsedCarDealer.finishJob(&s, i, &car, data: d)
        }
        XCTAssertTrue(billed, "the dealer can pay the garage")
        XCTAssertGreaterThan(e.state.company(rid)!.vatBalance - vat0, 0, "the garage owes VAT on its bill to the dealer")
        XCTAssertLessThan(e.state.company(id)!.vatBalance - dealerVat0, 0.001, "the dealer reclaims it")
        balanced(e, "own garage VAT")
    }

    func testLoansAreApprovedAndDeclinedInTheirOdds() throws {
        var (e, id) = try game(trade: "cardealer", cash: 1_500_000_000)
        ready(&e, id)
        var approved = 0, declined = 0
        for k in 0..<400 {
            e.update { s, d, _ in
                let t = DealerAddons.typicalSale(company: s.company(id)!, state: s, data: d)
                let r = DealerAddons.apply(&s, companyID: id, sale: DealerSale(key: "x\(k)", price: t.price, car: t.car), data: d)
                if r.financedAmount > 0 { approved += 1 }
                if r.financeDeclined { declined += 1 }
            }
        }
        XCTAssertGreaterThan(Double(approved) / Double(max(1, approved + declined)), 0.6, "approval at the typical price is about 0.8: \(approved) approved, \(declined) declined")
    }

    func testCardealerToolsAreCleaningAndCrmOnly() throws {
        let d = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 1).data
        XCTAssertEqual(d.catalog["cardealer"]?.equipment.map { $0.id }.sorted(), ["clean", "crm"])
    }

    func testTwoYearProbe() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_PROBE"] != nil else { throw XCTSkip("probe: set LEDGER_PROBE=1") }
        var report = ""
        for trade in ["usedcar", "cardealer"] {
            for addons in [false, true] {
                var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 12)
                var id = 0, est = 0.0
                e.update { s, data, ctx in
                    Ledger.move(&s, .me, 20_000_000_000, why: "Test funds")
                    guard case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, data: data, context: ctx) else { return }
                    id = i
                    est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, size: 1, state: s, data: data)?.total ?? 0
                    Payments.injectCash(&s, companyID: id, amount: est * 1.3 + (trade == "usedcar" ? 6_000_000 : 40_000_000))
                    _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
                    if let bd = data.catalog[trade] {
                        for _ in 0..<6 {
                            let c = ManagerModel.generateCandidate(company: s.company(id), type: bd.managerType, state: &s, data: data)
                            if ManagerModel.hire(&s, personID: c.id, companyID: id, monthlyWage: c.askingMonthlyWage * 1.2, data: data) == .ok { break }
                        }
                    }
                    if let i = s.companyIndex(id) {
                        var m = StaffMember(raw: [:]); m.set("id", 9100); m.set("role", "buyer"); m.set("wage", 4000)
                        var co = s.companies[i]; var st = co.staff; st.append(m); co.staff = st; s.companies[i] = co
                    }
                }
                let cash0 = e.state.company(id)!.cash
                _ = e.openCompany(companyID: id)
                e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .open } }
                for (k, n) in [("google", 1), ("meta", 1), ("seo", 1)] {
                    if let ch = e.marketing.channels[k], ch.budgetOptions.count > n { _ = e.setCampaign(companyID: id, channel: k, weeklyBudget: ch.budgetOptions[n]) }
                }
                if addons { ready(&e, id) }
                var injected = 0.0
                for _ in 0..<104 {
                    if trade == "usedcar" {
                        var n = 0
                        while e.usedCarStock(companyID: id).count < 20 && n < 4 {
                            let list = Marketplace.pool(e.state, companyID: id, data: e.data).filter { $0.h.vehicle && $0.h.equipmentID.isEmpty && !$0.h.noTalk }
                            guard let x = list.min(by: { $0.l.askingPrice / $0.h.fair < $1.l.askingPrice / $1.h.fair }), x.l.askingPrice / x.h.fair < 0.98 else { break }
                            guard e.state.company(id)!.cash > x.l.askingPrice * 1.1, e.buyListing(listingID: x.l.id, companyID: id, price: x.l.askingPrice) == .applied else { break }
                            n += 1
                        }
                    }
                    for _ in 0..<7 {
                        _ = e.nextDay()
                        for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
                        if let co = e.state.company(id), co.cash < -50_000 { let top = -co.cash + 100_000; e.update { s, _, _ in Payments.injectCash(&s, companyID: id, amount: top) }; injected += top }
                    }
                }
                let co = e.state.company(id)!, h = co.monthlyHistory
                let profit = h.suffix(24).reduce(0) { $0 + $1.profit }, invested = cash0 + injected
                let t = e.dealerAddonTotals(companyID: id)
                report += "PROBE \(trade) addons=\(addons): invested \(invested) profit 2y \(profit) (\(profit / invested * 100)%) rev \(co.books.total["rev"] ?? 0) addon: wty \(t?.warrantiesSold ?? 0) loans \(t?.financedSales ?? 0) declined \(t?.financeDeclined ?? 0) pol \(t?.policies ?? 0) reserve \(co.payables["warr"] ?? 0) gaps \(Ledger.gaps(e.state).count)\n"
            }
        }
        print(report)
    }
}
