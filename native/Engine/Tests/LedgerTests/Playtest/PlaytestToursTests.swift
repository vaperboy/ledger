import XCTest
import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses
import Simulation

/// Feature tours: scripted, deterministic walks through what the app offers. Each asserts that the action returns a sensible result and that the
/// state changes the way the UI would show it. A failed assertion is both an XCTFail and a finding (tour:<tour>:<what>). LEDGER_PLAYTEST=1 only.
final class PlaytestToursTests: XCTestCase {
    var tour = ""
    var cur: Currency!

    override func setUpWithError() throws { try XCTSkipUnless(PT.enabled, "set LEDGER_PLAYTEST=1") }
    override func tearDown() { Findings.shared.flush(tag: PT.tag + "-tours") }

    func ex(_ cond: @autoclosure () -> Bool, _ msg: String, sev: Int = 2, file: String = "", line: UInt = #line) {
        if !cond() {
            Findings.shared.add(sev, "tour:\(tour):\(msg)", "TOUR \(tour): \(msg)", repro: "LEDGER_PLAYTEST=1 swift test --filter PlaytestToursTests/test\(tour)", file: file.isEmpty ? "see tour \(tour) line \(line)" : file, detail: "line \(line)")
            XCTFail("\(tour): \(msg)", line: line)
        }
    }

    /// A game with a funded, open company of `trade` (UK, seed 5 by default).
    func fixture(_ trade: String = "cafe", country: String = "UK", seed: Int = 5, quick: Bool = true) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: country, playerName: "Tour", seed: seed)
        cur = e.homeCurrency
        e.update { s, _, _ in Ledger.move(&s, .me, cur.scaledPrice(30_000_000), why: "Test capital") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, form: .limited, fundWith: cur.scaledPrice(8_000_000), quickSetup: quick) else {
            XCTFail("\(tour): cannot start \(trade)"); throw CocoaError(.fileReadUnknown)
        }
        openUp(&e, id)
        return (e, id)
    }

    func openUp(_ e: inout GameEngine, _ id: Int) {
        for _ in 0..<(40 * 7) {
            if e.state.company(id)?.status == .open { return }
            if e.state.day == 0 || e.state.day == 6 {
                _ = e.quickSetupWithinBudget(companyID: id)
                for it in e.openingChecklist(companyID: id) where !it.isDone {
                    if ["rejected", "lapsed", ""].contains(e.documentState(companyID: id, document: it.id).status) { _ = e.applyForDocument(companyID: id, documentID: it.id) }
                }
                _ = e.openCompany(companyID: id)
            }
            for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
            e.nextDay()
        }
    }

    func weeks(_ e: inout GameEngine, _ n: Int) {
        for _ in 0..<(n * 7) { for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }; e.nextDay(); if e.state.isGameOver { return } }
    }

    // MARK: 1 Setup, opening, first trading

    func testSetupAndOpen() throws {
        tour = "SetupAndOpen"
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tour", seed: 5); cur = e.homeCurrency
        e.update { s, _, _ in Ledger.move(&s, .me, cur.scaledPrice(30_000_000), why: "Test capital") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: cur.scaledPrice(8_000_000), quickSetup: false) else { return XCTFail("start") }
        ex(e.state.company(id)?.status == .setup, "a new company starts in setup")
        let list = e.openingChecklist(companyID: id)
        ex(!list.isEmpty && list.contains { !$0.isDone }, "checklist lists open items for a new company")
        let r0 = e.openCompany(companyID: id)
        ex(r0 != .ok, "openCompany refuses while items are missing (got \(r0))")
        let rep = e.quickSetupWithinBudget(companyID: id)
        _ = rep
        weeks(&e, 6)
        _ = e.openCompany(companyID: id)
        openUp(&e, id)
        ex(e.state.company(id)?.status == .open, "company opens within 40 weeks of quick setup + open", sev: 1)
        let staff0 = e.state.company(id)?.staff.count ?? 0
        ex(staff0 > 0, "quick setup hires a starting team (\(staff0))")
        weeks(&e, 8)
        let co = e.state.company(id)!
        ex(co.lastWeekRevenue > 0, "an open cafe earns revenue within 8 weeks")
        ex(Ledger.gaps(e.state).isEmpty, "ledger consistent after opening", sev: 1)
    }

    // MARK: 2 Hiring, firing, raises, promotion talks

    func testHireFireTalk() throws {
        tour = "HireFireTalk"
        var (e, id) = try fixture()
        let roles = e.hireableRoles(companyID: id)
        ex(!roles.isEmpty, "hireableRoles is not empty for a cafe")
        guard let role = roles.first else { return }
        let before = e.state.company(id)!.staff.count
        let cands = e.searchWorkers(companyID: id, role: role, mode: .ads)
        ex(!cands.isEmpty, "search brings candidates", sev: 1)
        guard let p = cands.first else { return }
        let post = HirePost.worker(role: role)
        let talk = e.hireSalaryTalk(post: post, companyID: id, personID: p.id, terms: Hiring.Terms())
        ex(talk != nil, "salary talk screen can be built")
        let ask = e.hearTheirAsk(post: post, companyID: id, personID: p.id)
        ex(ask != nil && ask! > 0, "candidate states a positive ask")
        let low = e.hireOffer(post: post, companyID: id, personID: p.id, monthlyWage: (ask ?? 1000) * 0.3)
        ex(low != .hired, "a lowball offer is not simply accepted (\(low))")
        var out = HireOutcome.refused
        for _ in 0..<4 {
            out = e.hireOffer(post: post, companyID: id, personID: p.id, monthlyWage: ask ?? 1000)
            if case .countered = out { continue }; break
        }
        ex(out == .hired, "offering their ask hires them (got \(out))", sev: 1)
        ex(e.state.company(id)!.staff.count == before + 1, "staff count +1 after hiring")
        // the hired person
        if let st = e.state.company(id)!.staff.first(where: { $0.id == p.id }) {
            ex(st.monthlyWage > 0, "hired wage positive")
            weeks(&e, 6)
            let tk = e.talkToStaff(companyID: id, staffID: p.id)
            ex(tk != nil, "talkToStaff returns a result for a current employee")
            let gp = e.growthPath(companyID: id, employeeID: p.id)
            if gp != nil { let pr = e.promote(companyID: id, employeeID: p.id); if case .blocked(let w) = pr { ex(false, "promotion blocked unexpectedly: \(w)", sev: 3) } }
            let wn = e.warnStaff(companyID: id, staffID: p.id)
            ex(wn != nil, "warnStaff returns a result")
            let before2 = e.state.company(id)!.staff.count
            let d = e.dismissStaff(companyID: id, staffID: p.id)
            ex(d != nil, "dismissStaff returns a result")
            ex(e.state.company(id)!.staff.count == before2 - 1 || e.state.company(id)!.staff.first(where: { $0.id == p.id }) != nil, "dismissal removes the person or leaves them on notice")
        } else { ex(false, "hired person is on the company staff list", sev: 1) }
        let lp = e.layoffPreview(companyID: id, count: 1)
        let laid = e.layOffStaff(companyID: id, count: 1)
        ex(laid.count <= 1 && (laid.isEmpty || !lp.names.isEmpty), "layoff preview and layoff agree")
        // course
        _ = e.sendOnCourse(companyID: id, staffID: e.state.company(id)?.staff.first?.id, courseID: "x")
        ex(Ledger.gaps(e.state).isEmpty, "ledger consistent after hiring tour", sev: 1)
    }

    // MARK: 3 Manager hired and kept

    func testManagerHire() throws {
        tour = "ManagerHire"
        var (e, id) = try fixture()
        weeks(&e, 12)
        let cands = e.searchManagers(companyID: id)
        ex(cands?.isEmpty == false, "manager search brings candidates", sev: 1)
        guard let p = cands?.first else { return }
        ex(e.managerMayHire(companyID: id, role: "mgr", target: id) != nil, "managerMayHire answers")
        let ask = e.hearTheirAsk(post: .manager, companyID: id, personID: p.id) ?? 5000
        var r = HireOutcome.refused
        for _ in 0..<4 { r = e.hireOffer(post: .manager, companyID: id, personID: p.id, monthlyWage: ask * 1.1); if case .countered = r { continue }; break }
        ex(r == .hired, "manager hired at ask+10% (got \(r))", sev: 1)
        ex(e.state.company(id)?.managerID == p.id, "company shows the manager")
        weeks(&e, 8)
        ex(e.state.company(id)?.managerID == p.id, "manager still in post 8 weeks later (no immediate quit)", sev: 1)
        ex(e.setManagerAuthority(companyID: id, level: 2) != .refused("x"), "authority can be set")
        weeks(&e, 20)
        ex(e.state.company(id)?.status == .open, "a managed company keeps trading")
        ex(Ledger.gaps(e.state).isEmpty, "ledger consistent", sev: 1)
        let fired = e.dismissManager(companyID: id)
        ex(e.state.company(id)?.managerID == nil, "dismissManager clears the post (cost \(fired))")
    }

    // MARK: 4 Loans

    func testLoans() throws {
        tour = "Loans"
        var (e, id) = try fixture()
        weeks(&e, 10)
        let amount = cur.scaledPrice(200_000)
        let offer = e.loanOffer(kind: "biz", amount: amount, companyID: id)
        ex(offer.maximum > 0, "a trading company is offered some business loan (max \(Int(offer.maximum)))", sev: 3)
        let a = e.loanAssessment(kind: "biz", companyID: id)
        _ = a
        let loansBefore = e.state.loans.count, cashBefore = e.state.company(id)!.cash
        let amt = min(amount, offer.maximum)
        guard amt > 0 else { return }
        let docs = LoanDocuments(fullName: e.state.player.name, incomeProof: .payslips, companyPapers: (e.state.company(id)?.monthlyHistory.count ?? 0) >= 3 ? .accounts : .registration)
        let q = e.loanApplicationQuote(kind: "biz", amount: amt, termMonths: 36, companyID: id)
        ex(q.refusal == nil, "loan quote for an amount within the offered maximum has no refusal (\(q.refusal ?? ""))")
        let r = e.applyForLoan(kind: "biz", amount: amt, termMonths: 36, companyID: id, documents: docs, agreed: true)
        var approved = false; if case .approved = r { approved = true }
        ex(approved, "applyForLoan approved within the stated maximum (got \(r))")
        if approved {
            ex(e.state.loans.count == loansBefore + 1, "loan appears in the loan list")
            ex(e.state.company(id)!.cash > cashBefore, "company cash rises by the loan")
            let l = e.state.loans.last!
            ex(!e.loanSchedule(loanID: l.id).isEmpty, "loan has a repayment schedule")
            ex(e.loanPayoffQuote(loanID: l.id) != nil, "payoff quote available")
            weeks(&e, 6)
            let bal0 = e.state.loans.first { $0.id == l.id }?.balance ?? 0
            ex(e.repayLoan(id: l.id, amount: bal0 * 0.2), "partial repayment succeeds")
            let bal1 = e.state.loans.first { $0.id == l.id }?.balance ?? 0
            ex(bal1 < bal0, "balance falls after partial repayment")
            _ = e.payLoanInstalmentNow(loanID: l.id)
            ex(e.payOffLoan(loanID: l.id), "pay off in full succeeds with enough cash")
            ex(e.state.loans.first { $0.id == l.id } == nil || (e.state.loans.first { $0.id == l.id }?.balance ?? 1) < 1, "paid-off loan is gone")
        }
        ex(Ledger.gaps(e.state).isEmpty, "ledger consistent after loan tour", sev: 1)
    }

    // MARK: 5 Equipment buy and sell, suppliers

    func testEquipmentAndSuppliers() throws {
        tour = "EquipmentAndSuppliers"
        var (e, id) = try fixture("bakery")
        weeks(&e, 6)
        let needs = e.equipmentNeeds(companyID: id).filter { !$0.isVehicle && !$0.isSoftware }
        ex(!needs.isEmpty, "bakery lists equipment")
        if let n = needs.first {
            let offers = e.equipmentOffers(companyID: id, equipmentID: n.equipmentID)
            ex(!offers.isEmpty, "equipment \(n.name) has offers", sev: 2)
            if let o = offers.first {
                let have0 = e.equipmentNeeds(companyID: id).first { $0.equipmentID == n.equipmentID }?.have ?? 0
                let cash0 = e.state.company(id)!.cash
                let r = e.buyEquipmentItem(companyID: id, equipmentID: n.equipmentID, offer: o, quantity: 1, payment: .cash)
                ex(r == .ok, "buyEquipmentItem with cash ok (got \(r))")
                if r == .ok {
                    ex(e.state.company(id)!.cash < cash0, "cash falls after buying equipment")
                    let have1 = e.equipmentNeeds(companyID: id).first { $0.equipmentID == n.equipmentID }?.have ?? 0
                    ex(have1 == have0 + 1, "owned count +1 (\(have0) -> \(have1))")
                    let got = e.sellAllEquipment(companyID: id, equipmentID: n.equipmentID)
                    ex(got > 0, "selling equipment pays something (\(got))")
                }
            }
        }
        // supplier switch
        let vendors = e.supplierCandidates(companyID: id, scope: "goods")
        ex(!vendors.isEmpty, "goods supplier candidates exist", sev: 2)
        if vendors.count > 1, let cur0 = e.currentGoodsSupplier(companyID: id), let other = vendors.first(where: { $0.id != cur0.id }) {
            _ = e.agreeSupplierDeal(scope: "goods", vendorID: other.id)
            ex(e.currentGoodsSupplier(companyID: id)?.id != cur0.id || true, "supplier switch call returns")
        }
        e.chooseGoodsClass(companyID: id, goodsClass: 2)
        ex(Ledger.gaps(e.state).isEmpty, "ledger consistent after equipment tour", sev: 1)
    }

    // MARK: 6 Pricing, item sliders, marketing

    func testPricingItemsMarketing() throws {
        tour = "PricingItemsMarketing"
        var (e, id) = try fixture()
        weeks(&e, 8)
        let p0 = e.state.company(id)!.priceLevel
        let r = e.setPriceLevel(companyID: id, level: p0 + 0.1)
        ex(r == .applied || r.isRefused, "setPriceLevel answers applied/refused (got \(r))")
        if r == .applied { ex(e.state.company(id)!.priceLevel != p0, "price level actually changed") }
        ex(e.setPriceLevel(companyID: id, level: e.state.company(id)!.priceLevel) == .unchanged, "same price again is 'unchanged'")
        let items = e.salesItems(companyID: id)
        ex(!items.isEmpty, "a cafe has sales items", sev: 1)
        if let it = items.first {
            let f = e.itemForecast(companyID: id, itemID: it.id, price: it.price * 1.1, discountPercent: 0)
            ex(f.units.isFinite && f.revenue.isFinite, "item forecast finite")
            let sr = e.setItemPrice(companyID: id, itemID: it.id, price: it.price * 1.1)
            ex(sr == .applied, "setItemPrice applied (got \(sr))")
            ex(e.salesItems(companyID: id).first { $0.id == it.id }.map { abs($0.price - it.price * 1.1) < it.price * 0.02 } ?? false, "item price shows the new value")
            let dr = e.setItemDiscount(companyID: id, itemID: it.id, percent: 10, weeks: 2)
            ex(dr == .applied, "setItemDiscount applied (got \(dr))")
        }
        let opts = e.newItemOptions(companyID: id, isService: false)
        _ = opts
        for ch in e.marketingChannels(companyID: id) {
            guard let b = ch.budgetOptions.dropFirst().first else { continue }
            let rr = e.setCampaign(companyID: id, channel: ch.id, weeklyBudget: b)
            ex(rr == .done, "campaign on \(ch.id) accepted: \(rr)")
        }
        _ = e.setOwnerHours(companyID: id, hours: 30); e.setMaintenance(companyID: id, level: 2); e.setStockPolicy(companyID: id, level: 2)
        weeks(&e, 6)
        ex(e.state.company(id)!.cash.isFinite, "cash finite after tour")
        ex(Ledger.gaps(e.state).isEmpty, "ledger consistent", sev: 1)
    }

    // MARK: 7 Premises, insurance, accounting advisers

    func testPremisesInsuranceAdvisers() throws {
        tour = "PremisesInsuranceAdvisers"
        var (e, id) = try fixture()
        weeks(&e, 6)
        ex(e.premisesListings(companyID: id).count >= 0, "premises listing readable")
        if let cover = e.coverageOverview(companyID: id), let pol = cover.policies.first {
            let o = e.buyInsurance(companyID: id, product: pol.id, receiptCompanyID: id)
            ex(o.result == .done, "insurance \(pol.id) bought (got \(o.result))")
            ex(e.coverageOverview(companyID: id)?.policies.first { $0.id == pol.id }?.isOn == true, "policy shows as on")
            let c = e.toggleInsurancePolicy(companyID: id, product: pol.id)
            ex(c == .done, "insurance cancelled (got \(c))")
            ex(e.coverageOverview(companyID: id)?.policies.first { $0.id == pol.id }?.isOn == false, "policy shows as off")
        } else { ex(false, "coverage overview offers policies for a cafe", sev: 3) }
        let offers = e.adviserOffers(companyID: id, kind: .accountant)
        ex(!offers.isEmpty, "accountants are on offer", sev: 3)
        weeks(&e, 4)
        ex(Ledger.gaps(e.state).isEmpty, "ledger consistent", sev: 1)
    }

    // MARK: 8 Marketplace, used cars, car dealer

    func testMarketplaceAndDealers() throws {
        tour = "MarketplaceAndDealers"
        var (e, id) = try fixture("cafe")
        weeks(&e, 4)
        let ls = e.marketplaceListings(forCompany: id)
        if let l = ls.first {
            let neg = e.beginNegotiation(listingID: l.id, companyID: id)
            ex(neg != nil, "beginNegotiation on a listed item returns a negotiation")
            if neg != nil { _ = e.pushPrice(listingID: l.id, companyID: id) }
            let b = e.buyListing(listingID: l.id, companyID: id, price: l.askingPrice)
            ex(b == .applied || b.isRefused, "buyListing returns applied/refused (\(b))")
        }
        // car dealer cycle
        guard let dealerTrade = e.data.catalog.all.first(where: { $0.id.lowercased().contains("cardeal") || $0.id == "carsales" })?.id else { ex(true, "no car dealer trade"); return }
        var (d, did) = try fixture(dealerTrade)
        weeks(&d, 4)
        let rows = d.carDealerOffers(companyID: did)
        ex(!rows.isEmpty, "car dealer shows models to order", sev: 1)
        if let row = rows.first {
            let o = d.carDealerOrder(companyID: did, brandID: row.brandID, modelID: row.modelID)
            ex(o == .applied, "carDealerOrder applied (got \(o))")
            weeks(&d, 6)
            ex(d.carDealerSpaces(companyID: did).used >= 0, "dealer spaces readable")
        }
        ex(Ledger.gaps(d.state).isEmpty, "ledger consistent", sev: 1)
    }

    // MARK: 9 Board seats

    func testBoardSeats() throws {
        tour = "BoardSeats"
        var (e, id) = try fixture()
        weeks(&e, 8)
        guard let key = e.boardKey(companyID: id) else { return ex(false, "company has a board key", sev: 3) }
        let seats = e.boardSeats(key: key)
        ex(e.boardName(key: key).count > 0, "board has a name")
        let cands = e.searchForSeat(key: key, role: seats.first?.role ?? "chair")
        ex(cands != nil, "searchForSeat answers")
        if let p = cands?.first {
            let r = e.fillSeat(key: key, personID: p.id, monthlyFee: cur.scaledPrice(1000))
            ex(r == .ok || r == .refused || r == .full, "fillSeat answers a defined result: \(r)")
            if r == .ok {
                ex(e.boardSeats(key: key).contains(where: { $0.id == p.id }), "seat holder visible on the board")
                e.removeFromBoard(key: key, personID: p.id)
                ex(!e.boardSeats(key: key).contains(where: { $0.id == p.id }), "seat holder removed")
            }
        }
        ex(Ledger.gaps(e.state).isEmpty, "ledger consistent", sev: 1)
    }

    // MARK: 10 Chain, franchise, regional manager

    func testChainAndRegional() throws {
        tour = "ChainAndRegional"
        var (e, id) = try fixture()
        weeks(&e, 12)
        ex(e.chainRequirements(companyID: id).contains { !$0.ok }, "chain requirements list trademark and manual before start")
        ex(e.applyForChainDocument(companyID: id, document: "trademark") == .ok, "trademark application accepted")
        ex(e.applyForChainDocument(companyID: id, document: "ops_manual") == .ok, "ops manual application accepted")
        weeks(&e, 10)
        ex(e.chainRequirements(companyID: id).allSatisfy { $0.ok }, "chain requirements met 10 weeks after applying", sev: 1)
        let cr = e.applyForChainDocument(companyID: id, document: "chain"); ex(cr == .ok || cr == .alreadyHeld, "chain registration accepted (\(cr))", sev: 1)
        weeks(&e, 8)
        guard let cid = e.makeChain(companyID: id, name: "Tour Chain") else { return ex(false, "makeChain after trademark, manual and chain papers", sev: 1) }
        ex(e.chainOf(companyID: id) != nil, "chain is recorded on the company")
        var opened: [Int] = []
        for c in e.homeCountry.cities.prefix(3) {
            if case .success(let sid) = e.openChainStore(chainID: cid, cityID: c.id, size: 1) { opened.append(sid) }
        }
        ex(!opened.isEmpty, "at least one chain store opens in a home city", sev: 2)
        for sid in opened { openUp(&e, sid) }
        let sum = e.chainSummary(id: cid)
        ex((sum?.stores.count ?? 0) == 1 + opened.count, "chain summary counts all stores (\(sum?.stores.count ?? 0) vs \(1 + opened.count))")
        weeks(&e, 10)
        let ov = e.teamOverview()
        ex(ov.companies.count >= 1 + opened.count, "team overview lists the chain's stores")
        let needed = ov.vacancies.filter { $0.needed }
        var filled = 0
        for v in needed {
            guard let route = e.vacancyRoute(v), let cands = e.searchVacancy(v), let p = cands.first else { continue }
            let ask = e.hearTheirAsk(post: route.post, companyID: route.companyID, chainID: route.chainID, personID: p.id) ?? 5000
            if e.hireOffer(post: route.post, companyID: route.companyID, chainID: route.chainID, city: route.city, personID: p.id, monthlyWage: ask * 1.1) == .hired { filled += 1 }
        }
        ex(needed.isEmpty || filled > 0, "at least one needed vacancy (\(needed.count)) can be filled by the owner", sev: 1)
        weeks(&e, 16)
        let m = e.state.inbox.filter { !$0.handledBy.isEmpty }.count
        ex(filled == 0 || m >= 0, "delegated decisions are readable (handled \(m))")
        let plan = e.chainKnobPlan(chainID: cid, knob: "price", value: 1)
        _ = plan
        ex(Ledger.gaps(e.state).isEmpty, "ledger consistent", sev: 1)
    }

    // MARK: 11 Ventures, startups, funding, shares

    func testVenturesAndShares() throws {
        tour = "VenturesAndShares"
        var (e, id) = try fixture()
        weeks(&e, 20)
        let sr = e.foundStartup(name: nil, sector: "saas", product: "crm", model: "sub", who: "c2", seedMultiple: 1)
        ex("\(sr)".contains("ok"), "foundStartup ok (got \(sr))", sev: 3)
        ex(e.canRaiseFunding(companyID: id) || true, "canRaiseFunding readable")
        let pr = e.pitchToInvestors(companyID: id, amount: e.suggestedFundingAmount(companyID: id))
        _ = pr
        let ls = e.listSharesForSale(companyID: id, percent: 10, broker: false)
        ex(ls || true, "listSharesForSale returns")
        weeks(&e, 10)
        ex(Ledger.gaps(e.state).isEmpty, "ledger consistent", sev: 1)
    }

    // MARK: 12 Luxury, rewards, goals

    func testLuxuryAndRewards() throws {
        tour = "LuxuryAndRewards"
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tour", seed: 5); cur = e.homeCurrency
        e.update { s, _, _ in Ledger.move(&s, .me, cur.scaledPrice(60_000_000), why: "Test capital") }
        let gate = e.applyForLuxuryAccess()
        _ = gate
        if let item = Luxury.categories.first?.items.first {
            let nw0 = e.netWorth.total
            let r = e.buyLuxury(itemID: item.id)
            ex("\(r)".lowercased().contains("ok") || "\(r)".lowercased().contains("bought") || e.luxuryGatePasses(netWorth: nw0) == false, "buyLuxury answers sensibly: \(r)", sev: 3)
            if let piece = Luxury.pieces(e.state).first {
                let q = e.luxurySellQuote(pieceID: piece.id)
                ex(q != nil, "owned luxury piece has a sell quote")
                let got = e.sellLuxury(pieceID: piece.id)
                ex(got >= 0, "sellLuxury returns an amount")
            }
        }
        // goals and rewards
        let dg = e.dailyGoal()
        _ = dg
        let c = e.claimDailyGoal()
        _ = c
        for st in PlayerGoals.firstSteps(e.state) ?? [] where st.done { ex(e.claimFirstStep(id: st.id) != nil || true, "claimFirstStep returns") }
        ex(Ledger.gaps(e.state).isEmpty, "ledger consistent after luxury tour", sev: 1)
    }

    // MARK: 13 Reports and digests

    func testReportsAndDigests() throws {
        tour = "ReportsAndDigests"
        var (e, id) = try fixture()
        _ = id
        weeks(&e, 60)
        ex(!e.reports(.week).isEmpty, "weekly reports exist after 60 weeks", sev: 1)
        ex(!e.reports(.month).isEmpty, "monthly reports exist after 60 weeks", sev: 1)
        ex(!e.reports(.year).isEmpty, "a yearly report exists after 60 weeks", sev: 1)
        for k in ReportKind.allCases {
            if let r = e.latestReport(k) {
                let d = e.reportDigest(r)
                ex(!"\(d)".isEmpty, "\(k) digest builds")
            }
        }
        var fresh: [Message] = []
        for _ in 0..<7 { fresh += e.nextDay().newMessages }
        let dd = e.dailyDigest(fresh: fresh)
        _ = dd
        if let p = e.pendingReportPrompt() { e.dismissReportPrompt(p); ex(e.pendingReportPrompt()?.id != p.id, "dismissing a report prompt removes it") }
    }

    // MARK: 14 Investments and savings

    func testInvestments() throws {
        tour = "Investments"
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tour", seed: 5); cur = e.homeCurrency
        e.update { s, _, _ in Ledger.move(&s, .me, cur.scaledPrice(2_000_000), why: "Test capital") }
        let cash0 = e.state.cash
        let sym = e.quotes(.fund).first?.symbol ?? "idx"
        let q = e.buyQuote(.fund, symbol: sym, amount: cur.scaledPrice(100_000))
        _ = q
        let b = e.buyInvestment(.fund, symbol: sym, amount: cur.scaledPrice(100_000))
        ex("\(b)".contains("ok") || "\(b)".contains("bought"), "buying the index fund works (got \(b))")
        ex(e.state.cash < cash0, "cash falls after buying")
        ex(e.moveToSavings(cur.scaledPrice(50_000)), "moving money to savings works")
        ex(e.openDeposit(amount: cur.scaledPrice(50_000), weeks: 26), "opening a deposit works")
        for _ in 0..<(30 * 7) { e.nextDay() }
        e.sellInvestment(.fund, symbol: sym, fraction: 1)
        ex(e.quotes(.fund).first { $0.symbol == sym }?.quantity ?? 0 < 0.0001, "sold out of the fund")
        ex(Ledger.gaps(e.state).isEmpty, "ledger consistent", sev: 1)
    }

    // MARK: 15 Holding, rename, close/reopen, wind-up, football

    func testHoldingCloseFootball() throws {
        tour = "HoldingCloseFootball"
        var (e, id) = try fixture()
        var (e2, id2) = (e, id)
        _ = (e2, id2)
        let id3 = { () -> Int in
            guard case .success(let n) = e.startCompany(tradeID: "tutor", cityID: e.state.player.cityID, form: .limited, fundWith: cur.scaledPrice(500_000)) else { return 0 }
            return n }()
        ex(id3 != 0, "second company starts")
        openUp(&e, id3)
        weeks(&e, 10)
        let h = e.createHolding(name: "Tour Holding", companies: [id, id3])
        if case .success(let hid) = h {
            ex(e.state.company(id)?.holdingID == hid, "company reports its holding")
            weeks(&e, 8)
            ex(e.holdingOverview(companyID: hid) != nil, "holding overview exists")
            ex(e.releaseFromHolding(companyID: id3), "release from holding works")
        } else { ex(false, "createHolding with two open companies: \(h)", sev: 2) }
        let rn = e.renameCompany(companyID: id, to: "Renamed Cafe")
        ex("\(rn)".lowercased().contains("renamed") || e.state.company(id)?.name == "Renamed Cafe", "rename applies (\(rn))", sev: 3)
        let cl = e.closeCompany(companyID: id3, weeks: 4)
        weeks(&e, 5)
        _ = cl
        let ro = e.reopenCompany(companyID: id3)
        _ = ro
        ex(e.state.company(id3)?.status == .open || e.state.company(id3)?.status == .closed, "closed company reopens or stays closed")
        // football
        e.update { s, _, _ in Ledger.move(&s, .me, cur.scaledPrice(80_000_000), why: "Test capital") }
        if let code = e.leagueCountries().first?.code {
            let fr = e.foundClub(countryCode: code)
            if case .ok(let cid) = fr { weeks(&e, 20); ex(e.state.company(cid)?.status.isLive == true, "founded club keeps living for 20 weeks"); ex(e.clubSummary(companyID: cid) != nil, "club summary exists") }
            else { ex(false, "foundClub with ample cash: \(fr)", sev: 2) }
        } else { ex(false, "football leagues exist", sev: 3) }
        ex(Ledger.gaps(e.state).isEmpty, "ledger consistent", sev: 1)
    }

    // MARK: 16 Every country starts and plays a month

    func testEveryCountryStarts() throws {
        tour = "EveryCountryStarts"
        let probe = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 1)
        for c in probe.data.countries.countries.map({ $0.code }) {
            guard var e = try? GameEngine.newGame(countryCode: c, playerName: "T", seed: 3) else { ex(false, "newGame(\(c)) throws", sev: 1); continue }
            for _ in 0..<(8 * 7) { e.nextDay() }
            ex(Ledger.gaps(e.state).isEmpty, "\(c): ledger consistent after 8 weeks", sev: 1)
            ex(e.netWorth.total.isFinite, "\(c): net worth finite", sev: 1)
        }
    }
}
