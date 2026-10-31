import XCTest
import GameCore
import Finance
import Simulation
@testable import Businesses

/// What a bought rival becomes (merge, close, branch, franchise office), a site beside a rival, a purchase with a loan from your own bank
/// and the answers to a rival's price cut (original `rivhow`, `branchgo`, `rivfin27`, `rm27`).
final class RivalAbsorbTests: XCTestCase {
    private func engineWithCafe(weeks: Int = 8, seed: Int = 777) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 400_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: "cafe", cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            _ = Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6 + 3_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        for _ in 0..<(weeks * 7) { e.nextDay() }
        return (e, id)
    }

    private func firstRival(_ e: GameEngine, _ id: Int) throws -> Rivals.Rival {
        try XCTUnwrap(e.rivalRows(try XCTUnwrap(e.state.company(id))).first).rival
    }

    private func price(_ e: GameEngine, _ id: Int, _ r: Rivals.Rival) -> Double { (e.rivalValue(companyID: id, rivalID: r.id) * 1.5 / 1000).rounded() * 1000 }

    func testMergeAndCloseCostThePricePlusTheExtra() throws {
        var (e, id) = try engineWithCafe()
        XCTAssertEqual(e.state.company(id)?.status, .open)
        let r = try firstRival(e, id)
        let p = price(e, id, r)
        let extra = e.absorbRivalExtraCost(how: .merge, price: p)
        XCTAssertGreaterThan(extra, 0)
        XCTAssertEqual(extra, (p * 0.08 / 1000).rounded() * 1000)

        // not enough money: nothing happens
        let cash00 = e.state.cash
        XCTAssertEqual(e.absorbRival(companyID: id, rivalID: r.id, price: 1e13, how: .merge), .notEnoughCash)
        XCTAssertEqual(e.state.cash, cash00)

        let before = e.state.cash, count = Rivals.rivals(e.state, for: try XCTUnwrap(e.state.company(id))).count
        let aware0 = try XCTUnwrap(e.state.company(id)).awareness
        guard case .ok(let text, _, _) = e.absorbRival(companyID: id, rivalID: r.id, price: p, how: .merge) else { return XCTFail("the merge should work") }
        XCTAssertTrue(text.contains(r.name))
        XCTAssertEqual(before - e.state.cash, p + extra, accuracy: 1.01)
        XCTAssertFalse(Rivals.rivals(e.state, for: try XCTUnwrap(e.state.company(id))).contains { $0.id == r.id }, "the rival is gone")
        XCTAssertLessThanOrEqual(Rivals.rivals(e.state, for: try XCTUnwrap(e.state.company(id))).count, count - 1)
        XCTAssertGreaterThan(try XCTUnwrap(e.state.company(id)).awareness, aware0, "their customers come over")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")

        guard let r2 = Rivals.rivals(e.state, for: try XCTUnwrap(e.state.company(id))).first else { return }   // a market with one rival only: done
        let p2 = price(e, id, r2), extra2 = e.absorbRivalExtraCost(how: .shut, price: p2)
        XCTAssertEqual(extra2, (p2 * 0.12 / 1000).rounded() * 1000)
        let before2 = e.state.cash
        guard case .ok(_, _, let fine) = e.absorbRival(companyID: id, rivalID: r2.id, price: p2, how: .shut) else { return XCTFail("closing should work") }
        XCTAssertGreaterThanOrEqual(fine, 0)
        XCTAssertEqual(before2 - e.state.cash, p2 + extra2, accuracy: 1.01)
        XCTAssertFalse(Rivals.rivals(e.state, for: try XCTUnwrap(e.state.company(id))).contains { $0.id == r2.id })
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testBoughtRivalBecomesABranchOrAFranchiseOffice() throws {
        var (e, id) = try engineWithCafe()
        let r = try firstRival(e, id)
        let p = price(e, id, r)
        // a franchise office needs the franchise system
        XCTAssertEqual(e.absorbRival(companyID: id, rivalID: r.id, price: p, how: .franchiseOldOwner), .failed("Franchise offices need your franchise system first."))

        let n0 = e.state.companies.count
        guard case .ok(_, let branchID?, _) = e.absorbRival(companyID: id, rivalID: r.id, price: p, how: .branch) else { return XCTFail("the branch should work") }
        XCTAssertEqual(e.state.companies.count, n0 + 1)
        let b = try XCTUnwrap(e.state.company(branchID))
        XCTAssertEqual(b.value("branch")["of"].int, id)
        XCTAssertEqual(b.name, "\(try XCTUnwrap(e.state.company(id)).name) 2")
        XCTAssertGreaterThanOrEqual(b.reputation, try XCTUnwrap(e.state.company(id)).reputation * 0.95 - 1e-9)

        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].set("fr", .object(["on": true, "units": .array([]), "app": .array([]), "fee": 50_000, "roy": 0.06, "supp": 1, "brand": 50, "term": 10]))
        }
        guard let r2 = Rivals.rivals(e.state, for: try XCTUnwrap(e.state.company(id))).first else { return }
        let p2 = price(e, id, r2)
        let me0 = e.state.cash, co0 = try XCTUnwrap(e.state.company(id)).cash
        guard case .ok = e.absorbRival(companyID: id, rivalID: r2.id, price: p2, how: .franchiseOldOwner) else { return XCTFail("the franchise office should work") }
        let fr = try XCTUnwrap(e.state.company(id)).value("fr")
        XCTAssertEqual(fr["units"].array.count, 1)
        XCTAssertEqual(fr["units"].array[0]["from"].string, r2.name)
        XCTAssertEqual(me0 - e.state.cash, p2, accuracy: 1.01, "the old owner takes over: you pay the whole price and get no part back")
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).cash - co0, 25_000, accuracy: 1.01, "half the entry fee")
        XCTAssertEqual(fr["brand"].double, 52, accuracy: 1e-9)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testANewSiteBesideARivalNeedsTheFranchisePapersAndTakesItsCustomers() throws {
        var (e, id) = try engineWithCafe()
        let r = try firstRival(e, id)
        XCTAssertEqual(e.openBranchNextToRival(companyID: id, rivalID: r.id), .needsFranchisePapers)
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            var docs = s.companies[i].value("docs"); docs["fran"] = .object(["st": "ok"]); s.companies[i].set("docs", docs)
        }
        guard case .ok(let nid) = e.openBranchNextToRival(companyID: id, rivalID: r.id) else { return XCTFail("the site should be registered") }
        let site = try XCTUnwrap(e.state.company(nid))
        XCTAssertEqual(site.status, .setup)
        XCTAssertEqual(site.value("branch")["r"].int, r.id)
        XCTAssertEqual(site.value("docs")["fran"]["st"].string, "ok")
        XCTAssertTrue(site.name.hasPrefix(try XCTUnwrap(e.state.company(id)).name))
        // once it is open it takes 0.006 of the rival's size every week
        e.update { s, _, _ in s.companies[s.companyIndex(nid)!].status = .open }
        let size0 = try XCTUnwrap(Rivals.rivals(e.state, for: site).first { $0.id == r.id }).size
        let aware0 = try XCTUnwrap(e.state.company(nid)).awareness
        e.update { s, _, _ in RivalAbsorb.weekly(&s) }
        let size1 = try XCTUnwrap(Rivals.rivals(e.state, for: site).first { $0.id == r.id }).size
        XCTAssertEqual(size0 - size1, size0 > 0.306 ? 0.006 : size0 - 0.3, accuracy: 1e-9)
        XCTAssertGreaterThan(try XCTUnwrap(e.state.company(nid)).awareness, aware0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testPlayerMainBankIsOwnOnlyWithAnOpenOwnBank() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 92)
        XCTAssertFalse(e.playerMainBankIsOwn)
        e.update { s, _, _ in Ledger.move(&s, .me, 500_000_000, why: "Test funds") }
        guard case .success(let bankID) = e.startCompany(tradeID: "bank", cityID: e.state.player.cityID, form: .limited, fundWith: 330_000_000) else { return XCTFail("a bank") }
        e.update { s, _, _ in s.companies[s.companyIndex(bankID)!].status = .open }
        XCTAssertTrue(e.playerMainBankIsOwn)
        e.update { s, _, _ in s.companies[s.companyIndex(bankID)!].status = .closed }
        XCTAssertFalse(e.playerMainBankIsOwn)
    }

    func testBuyingWithALoanFromYourOwnBank() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 91)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 5_000_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: "cafe", cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            _ = Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6 + 3_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        guard case .success(let bankID) = e.startCompany(tradeID: "bank", cityID: e.state.player.cityID, form: .limited, fundWith: 330_000_000) else { return XCTFail("a bank") }
        for _ in 0..<(8 * 7) { e.nextDay() }
        e.update { s, _, _ in
            let i = s.companyIndex(bankID)!
            s.companies[i].status = .open
            var fm = s.companies[i].value("fm")
            fm["cr"] = 0.9; fm["equity"] = 400_000_000; fm["gb"] = 0
            s.companies[i].set("fm", fm)
            Ledger.move(&s, .company(bankID), 600_000_000)
        }
        let r = try firstRival(e, id)
        let p = price(e, id, r)
        let room = e.ownBankRoom()
        XCTAssertEqual(room, 100_000_000, accuracy: 1.0, "a quarter of its capital")
        // more than it may lend: refused
        XCTAssertEqual(e.buyRivalWithOwnBank(companyID: id, rivalID: r.id, price: p, amount: room + 10_000_000), .bankCannotLend)
        // a rival that is not there: the loan is undone
        let loans0 = e.state.loans.count, cash0 = e.state.cash, bank0 = try XCTUnwrap(e.state.company(bankID)).cash
        XCTAssertEqual(e.buyRivalWithOwnBank(companyID: id, rivalID: -5, price: p, amount: 1_000_000), .ok(.failed("That rival is gone.")))
        XCTAssertEqual(e.state.loans.count, loans0)
        XCTAssertEqual(e.state.cash, cash0)

        let amount = (p * 0.7 / 1000).rounded() * 1000
        let n0 = e.state.companies.count
        guard case .ok(.ok) = e.buyRivalWithOwnBank(companyID: id, rivalID: r.id, price: p, amount: amount) else { return XCTFail("the purchase should work") }
        XCTAssertEqual(e.state.companies.count, n0 + 1)
        let loan = try XCTUnwrap(e.state.loans.last)
        XCTAssertEqual(loan.balance, amount, accuracy: 1e-9)
        XCTAssertEqual(loan.bankCompanyID, bankID)
        XCTAssertEqual(loan.termMonths, 96)
        XCTAssertGreaterThan(loan.monthlyPayment, 0)
        XCTAssertEqual(bank0 - (try XCTUnwrap(e.state.company(bankID)).cash), amount, accuracy: 1.01, "the bank lent the money")
        XCTAssertEqual(try XCTUnwrap(e.state.company(bankID)).value("fm")["gb"].double, amount, accuracy: 1e-9)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    // MARK: Answering a price cut

    /// A running price cut of 15% by the first rival, with the demand effect it puts on the cafe.
    private func withPriceCut(_ e: inout GameEngine, _ id: Int, _ r: Rivals.Rival) {
        e.update { s, _, _ in
            let co = s.company(id)!
            let wk = s.week
            Rivals.mutate(&s, key: Rivals.key(co), id: r.id) { $0["uc27"] = .object(["end": .number(Double(wk + 8)), "pct": 15, "from": 1, "co": .number(Double(id)), "w": .number(Double(wk))]) }
            PriceMoves.addModifier(&s, s.companyIndex(id)!, key: "dem", multiplier: 1 - 15.0 / 300, weeks: 8)
            s.companies[s.companyIndex(id)!].set("lastW", .object(["rev": 50_000]))
            s.companies[s.companyIndex(id)!].priceLevel = 0
        }
    }

    /// True if the company has a demand effect of this size (other events may add their own).
    private func hasDemandMod(_ e: GameEngine, _ id: Int, _ m: Double) -> Bool {
        (e.state.company(id)?.value("mods").array ?? []).contains { $0["k"].string == "dem" && abs($0["m"].double - m) < 1e-9 }
    }

    func testMatchingTheirPriceLowersYoursUntilTheCutEnds() throws {
        var (e, id) = try engineWithCafe()
        let r = try firstRival(e, id)
        XCTAssertNil(e.rivalPriceCut(companyID: id, rivalID: r.id))
        withPriceCut(&e, id, r)
        XCTAssertEqual(e.rivalPriceCut(companyID: id, rivalID: r.id)?.pct, 15)
        XCTAssertTrue(hasDemandMod(e, id, 0.95))
        XCTAssertEqual(e.answerPriceCut(companyID: id, rivalID: r.id, answer: .match), .done("Prices lowered at \(try XCTUnwrap(e.state.company(id)).name) until the cut ends."))
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).priceLevel, -1)
        XCTAssertFalse(hasDemandMod(e, id, 0.95))
        XCTAssertTrue(hasDemandMod(e, id, 1), "your customers stay")
        XCTAssertEqual(e.rivalPriceCut(companyID: id, rivalID: r.id)?.answered, "matched their price")
        XCTAssertEqual(e.answerPriceCut(companyID: id, rivalID: r.id, answer: .quality), .failed("This has passed."), "one answer only")
        // the cut ends: the old price comes back
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            var f = s.companies[i].value("flags"); f["match27"]["end"] = .number(Double(s.week)); s.companies[i].set("flags", f)
            RivalAbsorb.weekly(&s)
        }
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).priceLevel, 0)
        XCTAssertTrue(try XCTUnwrap(e.state.company(id)).value("flags")["match27"].isNull)
    }

    func testHoldingPricesAndSellingQualityCostsACampaign() throws {
        var (e, id) = try engineWithCafe()
        let r = try firstRival(e, id)
        withPriceCut(&e, id, r)
        e.update { s, _, _ in _ = Payments.injectCash(&s, companyID: id, amount: 100_000) }
        let cash0 = try XCTUnwrap(e.state.company(id)).cash, rep0 = try XCTUnwrap(e.state.company(id)).reputation
        XCTAssertEqual(e.answerPriceCut(companyID: id, rivalID: r.id, answer: .quality), .done("Campaign running."))
        XCTAssertEqual(cash0 - (try XCTUnwrap(e.state.company(id)).cash), 9_000, accuracy: 1.01, "3% of a week's sales for the six weeks that matter")
        XCTAssertTrue(hasDemandMod(e, id, 0.975), "half the damage")
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).reputation, min(100, rep0 + 2), accuracy: 1e-9)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testACheapSecondBrandIsANewCompany() throws {
        var (e, id) = try engineWithCafe()
        let r = try firstRival(e, id)
        withPriceCut(&e, id, r)
        let n0 = e.state.companies.count
        guard case .newCompany(let nid) = e.answerPriceCut(companyID: id, rivalID: r.id, answer: .brand) else { return XCTFail("a new company") }
        XCTAssertEqual(e.state.companies.count, n0 + 1)
        let b = try XCTUnwrap(e.state.company(nid))
        XCTAssertTrue(b.name.hasSuffix(" Express"))
        XCTAssertEqual(b.priceLevel, -2)
        XCTAssertEqual(b.value("flags")["brand27"].int, id)
        XCTAssertEqual(e.rivalPriceCut(companyID: id, rivalID: r.id)?.answered, "started a cheap second brand")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }
}
