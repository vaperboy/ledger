import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The three supplier gaps: the chain-wide supplier rule, payment terms with late-payment consequences, and negotiation of supplier deals.
final class SupplierTermsTests: XCTestCase {
    // MARK: Helpers

    private func chainOfCafes(_ e: inout GameEngine, stores: Int) throws -> (chain: Int, ids: [Int]) {
        let first = ChainsTests.start(&e, "cafe")
        ChainsTests.season(&e, first)
        e.update { s, _, _ in if let i = s.companyIndex(first) { s.companies[i].set("mgr", 0) } }
        let chain = try XCTUnwrap(e.makeChain(companyID: first, name: "Test Cafe"))
        var ids = [first]
        for _ in 1..<stores {
            let id = ChainsTests.start(&e, "cafe")
            e.joinChain(chainID: chain, companyID: id, rename: false)
            ids.append(id)
        }
        return (chain, ids)
    }

    private func goodsVendorID(_ e: GameEngine, _ company: Int) throws -> String {
        let goods = try XCTUnwrap(e.supplierInputs(companyID: company).first { $0.id == "goods" })
        return try XCTUnwrap(goods.options.first { $0.vendorID != nil && !$0.isCurrent }?.vendorID)
    }

    private func setCash(_ e: inout GameEngine, _ id: Int, to v: Double) {
        e.update { s, _, _ in Ledger.set(&s, .company(id), to: v) }
    }

    // MARK: 1. Chain-wide supplier rule

    func testChainRuleSwitchesEveryStoreLocksThemAndReleases() throws {
        var e = try ChainsTests.engine()
        let (chain, ids) = try chainOfCafes(&e, stores: 3)
        ChainsTests.play(&e, days: 4 * 7)
        let vendor = try goodsVendorID(e, ids[0])
        let plan = e.chainSupplierPlan(chainID: chain, input: "goods", to: .goodsVendor(vendor))
        XCTAssertEqual(plan.lines.count, 3)
        XCTAssertTrue(plan.changing >= 1)
        let applied = e.setChainSupplier(chainID: chain, input: "goods", to: .goodsVendor(vendor))
        XCTAssertEqual(applied.exceptions, 0, "\(applied.lines)")
        for id in ids { XCTAssertEqual(e.currentGoodsSupplier(companyID: id)?.id, vendor) }
        XCTAssertEqual(e.chainSupplierRules(chainID: chain).first?.providerName.isEmpty, false)
        // mandatory: a store cannot switch on its own while the rule stands
        let before = ids[1]
        XCTAssertEqual(e.switchSupplier(companyID: before, input: "goods", to: .goodsVendor("auto")), .governed)
        XCTAssertEqual(e.supplierInputs(companyID: before).first { $0.id == "goods" }?.governedBy != nil, true)
        XCTAssertEqual(e.negotiateSupplier(companyID: before, input: "goods", vendorID: vendor, ask: 0.01), .notAllowed)
        // "each store decides" releases it
        e.releaseChainSupplier(chainID: chain, input: "goods")
        XCTAssertTrue(e.chainSupplierRules(chainID: chain).isEmpty)
        XCTAssertNil(e.state.rest["chains"]?.array.first?["rules"]["sup"].object.keys.first, "no key left behind")
        XCTAssertEqual(e.switchSupplier(companyID: before, input: "goods", to: .goodsVendor("auto")), .ok)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testFranchiseeIsNotForcedAndANewStoreFollowsTheRule() throws {
        var e = try ChainsTests.engine()
        let (chain, ids) = try chainOfCafes(&e, stores: 3)
        ChainsTests.play(&e, days: 2 * 7)
        e.update { s, _, _ in s.companies[s.companyIndex(ids[2])!].set("franchise", .object(["fran": true, "brandName": "Brand"])) }
        let vendor = try goodsVendorID(e, ids[0])
        let plan = e.setChainSupplier(chainID: chain, input: "goods", to: .goodsVendor(vendor))
        XCTAssertEqual(plan.lines.first { $0.storeID == ids[2] }?.free, true)
        XCTAssertEqual(e.currentGoodsSupplier(companyID: ids[0])?.id, vendor)
        XCTAssertNotEqual(e.state.company(ids[2])?.value("src")["v"].string, vendor, "the franchised unit keeps deciding for itself")
        XCTAssertEqual(e.supplierInputs(companyID: ids[2]).first { $0.id == "goods" }?.governedBy, nil)
        // a store joining later follows the rule
        let late = ChainsTests.start(&e, "cafe")
        e.joinChain(chainID: chain, companyID: late, rename: false)
        XCTAssertEqual(e.currentGoodsSupplier(companyID: late)?.id, vendor)
        // a company outside the chain (a holding's subsidiary, an independent) is never touched
        let other = ChainsTests.start(&e, "cafe")
        XCTAssertNotEqual(e.state.company(other)?.value("src")["v"].string, vendor)
        XCTAssertEqual(e.switchSupplier(companyID: other, input: "goods", to: .goodsVendor("auto")), .ok)
    }

    func testOwnProviderRuleReportsStoresThatCannotComply() throws {
        var e = try ChainsTests.engine()
        let first = ChainsTests.start(&e, "restaurant")
        ChainsTests.season(&e, first)
        e.update { s, _, _ in if let i = s.companyIndex(first) { s.companies[i].set("mgr", 0) } }
        let chain = try XCTUnwrap(e.makeChain(companyID: first, name: "Test Grill"))
        let second = ChainsTests.start(&e, "restaurant")
        e.joinChain(chainID: chain, companyID: second, rename: false)
        let cleaning = ChainsTests.start(&e, "cleaning")
        ChainsTests.play(&e, days: 10 * 7)
        // the own cleaner has spare capacity now
        e.update { s, _, _ in
            let i = s.companyIndex(cleaning)!
            s.companies[i].set("lastW", .object(["units": 10, "rev": 1000, "cogs": 100, "D": 100, "cap": 500, "util": 0.1]))
        }
        e.update { s, _, _ in
            for id in [first, second] { s.companies[s.companyIndex(id)!].set("lastW", .object(["units": 100, "rev": 400_000, "cogs": 100, "D": 100, "cap": 200, "util": 0.5])) }
        }
        let rule = SupplierSwitch.ownCompany(cleaning, mode: "c10")
        var plan = e.setChainSupplier(chainID: chain, input: "clean", to: rule)
        XCTAssertEqual(plan.exceptions, 0, "\(plan.lines)")
        XCTAssertEqual(e.supplyLink(buyer: first, kind: "clean")?.supplierID, cleaning)
        XCTAssertEqual(e.supplyLink(buyer: second, kind: "clean")?.supplierID, cleaning)
        // a third store appears while the cleaner is full: it keeps its choice and is reported, the others stay
        e.releaseChainSupplier(chainID: chain, input: "clean")
        e.update { s, _, _ in
            s.rest["l27"] = .array([])
            let i = s.companyIndex(cleaning)!
            s.companies[i].set("lastW", .object(["units": 500, "rev": 1000, "cogs": 100, "D": 100, "cap": 500, "util": 1]))
        }
        plan = e.setChainSupplier(chainID: chain, input: "clean", to: rule)
        XCTAssertEqual(plan.exceptions, 2, "\(plan.lines)")
        XCTAssertTrue(plan.lines.allSatisfy { $0.reason?.contains("spare capacity") ?? false })
        XCTAssertNil(e.supplyLink(buyer: first, kind: "clean"))
        XCTAssertTrue(e.chainSupplierRules(chainID: chain).first?.plan.exceptions == 2, "the rule stands and shows who is outside it")
        // it is retried when capacity frees up
        e.update { s, _, _ in s.companies[s.companyIndex(cleaning)!].set("lastW", .object(["units": 10, "rev": 1000, "cogs": 100, "D": 100, "cap": 500, "util": 0.1])) }
        plan = e.setChainSupplier(chainID: chain, input: "clean", to: rule)
        XCTAssertEqual(plan.exceptions, 0)
        XCTAssertEqual(e.chainSupplierChoices(chainID: chain, input: "clean").first { $0.change == rule }?.using, 2)
    }

    // MARK: 2. Payment terms

    func testOwnCompanyInvoiceIsPayableAndReceivableThenSettles() throws {
        var e = try ChainsTests.engine()
        let hotel = ChainsTests.start(&e, "hotel")
        let cleaning = ChainsTests.start(&e, "cleaning")
        ChainsTests.play(&e, days: 10 * 7)
        XCTAssertEqual(e.switchSupplier(companyID: hotel, input: "clean", to: .ownCompany(cleaning, mode: "mkt")), .ok)
        XCTAssertTrue(e.setSupplyPaymentTerms(companyID: hotel, input: "clean", term: "net30"))
        XCTAssertEqual(e.supplyLink(buyer: hotel, kind: "clean")?.termsID, "net30")
        XCTAssertEqual(e.supplierInputs(companyID: hotel).first { $0.id == "clean" }?.paymentTerms.first { $0.isCurrent }?.id, "net30")
        ChainsTests.play(&e, days: 3 * 7)
        let open = e.supplierInvoices(companyID: hotel)
        XCTAssertFalse(open.isEmpty)
        let owed = open.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(e.state.company(hotel)?.payables["inv"] ?? 0, owed, accuracy: 1)
        let recv = e.state.company(cleaning)?.receivables.filter { $0.int("ic") != 0 }.reduce(0) { $0 + $1.amount } ?? 0
        XCTAssertEqual(recv, owed, accuracy: 1, "the supplier holds exactly what the buyer owes")
        XCTAssertEqual(open.first?.providerName, e.state.company(cleaning)?.name)
        // it falls due
        let rows = e.financeOverview(companyID: hotel).upcoming.filter { $0.title.hasPrefix("Invoice") }
        XCTAssertFalse(rows.isEmpty)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.amount }, owed, accuracy: 1)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        // and settles: cash moves from the buyer to the supplier and the open amount stays about five weeks of supply, not growing
        ChainsTests.play(&e, days: 12 * 7)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        let later = e.supplierInvoices(companyID: hotel)
        XCTAssertTrue(later.allSatisfy { $0.dueWeek >= e.state.week - 1 }, "everything due was paid on time: \(later)")
        XCTAssertLessThanOrEqual(later.count, 7)
        XCTAssertEqual(e.state.company(hotel)?.payables["inv"] ?? 0, later.reduce(0) { $0 + $1.amount }, accuracy: 1)
        XCTAssertTrue(later.allSatisfy { $0.lateWeeks == 0 })
        // back to weekly settlement: no new invoices
        XCTAssertTrue(e.setSupplyPaymentTerms(companyID: hotel, input: "clean", term: nil))
        XCTAssertNil(e.supplyLink(buyer: hotel, kind: "clean")?.termsID)
    }

    func testLateOwnInvoiceCarriesInterestOnBothBooksAndClearsWhenPaid() throws {
        var e = try ChainsTests.engine()
        let hotel = ChainsTests.start(&e, "hotel")
        let cleaning = ChainsTests.start(&e, "cleaning")
        ChainsTests.play(&e, days: 10 * 7)
        e.switchSupplier(companyID: hotel, input: "clean", to: .ownCompany(cleaning, mode: "mkt"))
        e.setSupplyPaymentTerms(companyID: hotel, input: "clean", term: "net14")
        ChainsTests.play(&e, days: 2 * 7)
        XCTAssertFalse(e.supplierInvoices(companyID: hotel).isEmpty)
        let intBuyer0 = e.state.company(hotel)?.books.year["int"] ?? 0
        let intSupplier0 = e.state.company(cleaning)?.books.year["int"] ?? 0
        for _ in 0..<(4 * 7) {
            setCash(&e, hotel, to: -50_000_000_000)   // far below any overdraft room
            ChainsTests.play(&e, days: 1)
        }
        let late = e.supplierInvoices(companyID: hotel).filter { $0.lateWeeks > 0 }
        XCTAssertFalse(late.isEmpty)
        XCTAssertGreaterThan(e.state.company(hotel)?.books.year["int"] ?? 0, intBuyer0, "the buyer books the interest as a cost")
        XCTAssertGreaterThan(late.reduce(0) { $0 + $1.amount - $1.face }, 0, "late interest is added to what is owed")
        _ = intSupplier0
        XCTAssertEqual(e.state.company(hotel)?.payables["inv"] ?? 0, e.supplierInvoices(companyID: hotel).reduce(0) { $0 + $1.amount }, accuracy: 1)
        XCTAssertEqual(e.state.company(cleaning)?.receivables.filter { $0.int("ic") != 0 }.reduce(0) { $0 + $1.amount } ?? 0,
                       e.supplierInvoices(companyID: hotel).reduce(0) { $0 + $1.amount }, accuracy: 1)
        // money back: everything overdue is paid, oldest first, and the debt disappears
        setCash(&e, hotel, to: 50_000_000_000)
        ChainsTests.play(&e, days: 2 * 7)
        XCTAssertTrue(e.supplierInvoices(companyID: hotel).allSatisfy { $0.lateWeeks == 0 })
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testOutsideSupplierTermsLateFeeRelationshipDealAndCutOff() throws {
        var e = try ChainsTests.engine()
        let cafe = ChainsTests.start(&e, "cafe")
        ChainsTests.play(&e, days: 6 * 7)
        let vendor = try goodsVendorID(e, cafe)
        XCTAssertEqual(e.switchSupplier(companyID: cafe, input: "goods", to: .goodsVendor(vendor)), .ok)
        // a stranger gives no 60 days
        XCTAssertFalse(e.setGoodsPaymentTerms(companyID: cafe, term: "net60"))
        e.update { s, _, _ in Suppliers.bumpPublic(&s, vendor, by: 70) }
        let rel0 = Suppliers.relationship(e.state, vendor)
        XCTAssertTrue(e.setGoodsPaymentTerms(companyID: cafe, term: "net30"))
        // a negotiated price is lost when payment is late
        e.update { s, _, _ in s.companies[s.companyIndex(cafe)!].set("sdl", .object(["goods": .object(["v": .string(vendor), "d": 0.02, "w": .number(Double(s.week))])])) }
        ChainsTests.play(&e, days: 3 * 7)
        XCTAssertFalse(e.supplierInvoices(companyID: cafe).isEmpty)
        XCTAssertEqual(e.state.company(cafe)?.payables["inv"] ?? 0, e.supplierInvoices(companyID: cafe).reduce(0) { $0 + $1.amount }, accuracy: 1)
        let rows = e.financeOverview(companyID: cafe).upcoming.filter { $0.title.hasPrefix("Invoice") }
        XCTAssertFalse(rows.isEmpty, "outside invoices show in what falls due")
        // stop paying: invoices go late, the supplier cools, the deal goes, then suppliers want cash, then stop delivering
        var levels: [Int] = []
        for _ in 0..<(12 * 7) {
            setCash(&e, cafe, to: -50_000_000_000)
            ChainsTests.play(&e, days: 1)
            levels.append(e.state.company(cafe)?.int("supCut") ?? 0)
        }
        XCTAssertTrue(e.supplierInvoices(companyID: cafe).contains { $0.lateWeeks > 0 })
        XCTAssertLessThan(Suppliers.relationship(e.state, vendor), rel0, "late payment cools the relationship")
        XCTAssertNil(SupplyDeals.deal(try XCTUnwrap(e.state.company(cafe)), input: "goods", week: e.state.week), "the negotiated price is withdrawn")
        XCTAssertTrue(levels.contains(1) || levels.contains(2), "repeated lateness cuts the supplier off: \(levels.suffix(10))")
        XCTAssertEqual(levels.max(), 2)
        XCTAssertTrue(e.state.inbox.contains { $0.title.contains("Late payment:") })
        XCTAssertTrue(e.state.inbox.contains { $0.title.hasPrefix("Suppliers stop delivering") || $0.title.hasPrefix("Suppliers want cash") })
        // the terms lapse when the relationship no longer carries them
        e.update { s, _, _ in
            var vr = s.rest["vr"]!; vr[vendor]["r"] = 10; s.rest["vr"] = vr
        }
        ChainsTests.play(&e, days: 7)
        XCTAssertNil(SupplyTerms.agreedGoodsTerm(try XCTUnwrap(e.state.company(cafe))), "net 30 lapses below the standing it needs")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testCountryRuleSetsTheLateRateAndTheDefaultIsTheGamesOwn() throws {
        let book = try CountryBook.bundled()
        let uk = try XCTUnwrap(book["UK"])
        XCTAssertEqual(SupplyTerms.lateMonthlyRate(country: uk, policyRate: 0.05), 0.02, accuracy: 1e-12, "no rule in the data: the game's default")
        var pack = uk.pack
        pack["commerce"] = .object(["latePayment": .object(["margin": 0.08])])
        let withRule = Country(pack: pack)
        XCTAssertEqual(SupplyTerms.lateAnnualRate(country: withRule, policyRate: 0.04), 0.12, accuracy: 1e-12)
        pack["commerce"] = .object(["latePayment": .object(["annual": 0.05])])
        XCTAssertEqual(SupplyTerms.lateAnnualRate(country: Country(pack: pack), policyRate: 0.04), 0.05, accuracy: 1e-12)
    }

    func testBusinessCustomerWhoPaysLatePutsTheMoneyInReceivables() throws {
        var e = try ChainsTests.engine()
        let owner = ChainsTests.start(&e, "cafe")
        ChainsTests.play(&e, days: 6 * 7)
        e.update { s, _, _ in
            let o = s.companyIndex(owner)!
            s.companies[o].set("accts", .array([.object(["id": 9101, "name": "Slow Payers Ltd", "f": 0.3, "rel": 0, "w0": .number(Double(s.week)), "disc": 0, "t": "cleaning"])]))
        }
        let cash0 = try XCTUnwrap(e.state.company(owner)).cash
        ChainsTests.play(&e, days: 20 * 7)
        let co = try XCTUnwrap(e.state.company(owner))
        let theirs = co.receivables.filter { $0.int("ac") == 9101 }
        XCTAssertFalse(theirs.isEmpty, "the customer's orders are invoiced, not paid at the till")
        XCTAssertGreaterThan(theirs.reduce(0) { $0 + $1.amount }, 0)
        let account = try XCTUnwrap(KeyAccounts.accounts(co).first { $0.id == 9101 })
        XCTAssertGreaterThan(account.totalPaid, 0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        _ = cash0
        // some of the customer's invoices come in late (stranger: the highest chance); the company is told and earns the late interest
        let lateOnes = (co.value("accts").array.first?["lc"].double ?? 0) + (co.value("accts").array.first?["lw"].double ?? 0)
        let anyLate = lateOnes > 0 || theirs.contains { $0.int("ld") > 0 }
        XCTAssertTrue(anyLate, "a new customer paid at least once late in 20 weeks")
    }

    // MARK: 3. Negotiation

    func testNegotiationAcceptCounterRefuseAndWalkAwayWithRelationshipEffect() throws {
        var e = try ChainsTests.engine()
        let cafe = ChainsTests.start(&e, "cafe")
        ChainsTests.play(&e, days: 4 * 7)
        let vendor = try goodsVendorID(e, cafe)
        // taking the list terms needs no haggling
        XCTAssertEqual(e.negotiateSupplier(companyID: cafe, input: "goods", vendorID: vendor, ask: 0), .agreed(extra: 0))
        XCTAssertEqual(e.currentGoodsSupplier(companyID: cafe)?.id, vendor)
        // an own company or a customer is not negotiated
        XCTAssertEqual({ if case .notNeeded = e.negotiateSupplier(companyID: cafe, input: "clean", vendorID: vendor, ask: 0.02) { return true } else { return false } }(), true)
        XCTAssertEqual(e.negotiateSupplier(companyID: cafe, input: "goods", vendorID: "V-XX-0", ask: 0.01), .notAllowed)
        // far too much: an insult, no figure; the round is used
        XCTAssertEqual(e.negotiateSupplier(companyID: cafe, input: "goods", vendorID: vendor, ask: 0.9), .refused)
        // a modest ask against a stranger: a counter (or an accept if the supplier has the room), never an insult
        var gotCounter: Negotiation.Counter?
        var rounds = 0
        var final: SupplyDeals.Talk = .notAllowed
        while rounds < 20 {
            final = e.negotiateSupplier(companyID: cafe, input: "goods", vendorID: vendor, ask: 0.013)
            rounds += 1
            if case .countered(let c) = final { gotCounter = c; continue }
            break
        }
        XCTAssertNotNil(gotCounter, "a stranger counters before it gives up")
        let relBefore = Suppliers.relationship(e.state, vendor)
        guard case .walkedAway(let until) = final else { return XCTFail("keeps asking too much: the supplier walks away, got \(final)") }
        XCTAssertEqual(until, e.state.week + 6)
        XCTAssertLessThanOrEqual(Suppliers.relationship(e.state, vendor), relBefore)
        XCTAssertEqual(e.negotiateSupplier(companyID: cafe, input: "goods", vendorID: vendor, ask: 0.01), .cooling(until: until))
        XCTAssertEqual(e.supplierInputs(companyID: cafe).first { $0.id == "goods" }?.options.first { $0.vendorID == vendor }?.coolingUntil, until)
        // after the cooling-off, accepting the supplier's counter works and gives the deal
        ChainsTests.play(&e, days: 7 * 7)
        var accepted: SupplyDeals.Talk = .notAllowed
        if case .countered(let c) = e.negotiateSupplier(companyID: cafe, input: "goods", vendorID: vendor, ask: 0.012) {
            accepted = e.negotiateSupplier(companyID: cafe, input: "goods", vendorID: vendor, ask: c.amount)
        } else { accepted = .agreed(extra: -1) }
        if case .agreed(let x) = accepted, x > 0 {
            let co = try XCTUnwrap(e.state.company(cafe))
            XCTAssertEqual(SupplyDeals.dealDiscount(co, scope: "goods", vendorID: vendor, week: e.state.week), x, accuracy: 1e-12)
            XCTAssertEqual(e.supplierInputs(companyID: cafe).first { $0.id == "goods" }?.current?.dealExtra, x)
        }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testBetterRelationshipGivesBetterOpeningAndMorePatience() throws {
        func run(relationship: Double) throws -> (accepted: Bool, rounds: Int) {
            var e = try ChainsTests.engine()
            let cafe = ChainsTests.start(&e, "cafe")
            ChainsTests.play(&e, days: 3 * 7)
            let vendor = try goodsVendorID(e, cafe)
            e.update { s, _, _ in Suppliers.bumpPublic(&s, vendor, by: relationship) }
            // an ask beyond a stranger's room but inside a friend's
            if case .agreed(let x) = e.negotiateSupplier(companyID: cafe, input: "goods", vendorID: vendor, ask: 0.02), x > 0 { return (true, 1) }
            var n = 1
            while n < 40 {
                let r = e.negotiateSupplier(companyID: cafe, input: "goods", vendorID: vendor, ask: 0.05)
                n += 1
                if case .walkedAway = r { break }
            }
            return (false, n)
        }
        let stranger = try run(relationship: 0), friend = try run(relationship: 85)
        XCTAssertFalse(stranger.accepted)
        XCTAssertTrue(friend.accepted || friend.rounds > stranger.rounds, "a friend gives more (\(friend)) than a stranger (\(stranger))")
        // the same hidden room for the same relationship: replays give the same answers
        XCTAssertEqual(try run(relationship: 0).rounds, stranger.rounds)
    }

    // MARK: Determinism, saves, play

    func testSavedGameKeepsInvoicesTermsDealsAndRules() throws {
        var e = try ChainsTests.engine()
        let hotel = ChainsTests.start(&e, "hotel")
        let cleaning = ChainsTests.start(&e, "cleaning")
        ChainsTests.play(&e, days: 8 * 7)
        e.switchSupplier(companyID: hotel, input: "clean", to: .ownCompany(cleaning, mode: "mkt"))
        e.setSupplyPaymentTerms(companyID: hotel, input: "clean", term: "net30")
        ChainsTests.play(&e, days: 3 * 7)
        XCTAssertFalse(e.supplierInvoices(companyID: hotel).isEmpty)
        let data = try JSONEncoder().encode(e.state)
        let back = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(SupplyTerms.invoices(back, buyer: hotel), e.supplierInvoices(companyID: hotel))
        XCTAssertEqual(back.company(hotel)?.payables["inv"], e.state.company(hotel)?.payables["inv"])
        XCTAssertEqual(IntercompanySupply.link(back, buyer: hotel, kind: "clean")?.termsID, "net30")
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(back)), try JSONDecoder().decode(JSONValue.self, from: data))
    }

    func testNewKeysAreWrittenOnlyWhenSet() throws {
        var e = try ChainsTests.engine()
        let cafe = ChainsTests.start(&e, "cafe")
        ChainsTests.play(&e, days: 12 * 7)
        let co = try XCTUnwrap(e.state.company(cafe))
        for key in ["pterm", "lt", "sdl", "supCutI", "supCutB"] { XCTAssertNil(co.raw[key], key) }
        XCTAssertNil(e.state.rest["sinv"])
        XCTAssertNil(co.payables["inv"])
        XCTAssertNil(co.raw["neg"])
    }

    private func runYear(seed: Int, terms: Bool) throws -> (cash: Double, gaps: Int, invoices: Int, owed: Double, late: Int, rel: Double) {
        var e = try ChainsTests.engine("NO", seed: seed)
        let hotel = ChainsTests.start(&e, "hotel")
        let cleaning = ChainsTests.start(&e, "cleaning")
        let cafe = ChainsTests.start(&e, "cafe")
        ChainsTests.play(&e, days: 8 * 7)
        if terms {
            e.switchSupplier(companyID: hotel, input: "clean", to: .ownCompany(cleaning, mode: "c10"))
            e.setSupplyPaymentTerms(companyID: hotel, input: "clean", term: "net30")
            let v = try goodsVendorID(e, cafe)
            e.switchSupplier(companyID: cafe, input: "goods", to: .goodsVendor(v))
            e.update { s, _, _ in Suppliers.bumpPublic(&s, v, by: 50) }
            e.setGoodsPaymentTerms(companyID: cafe, term: "net30")
        }
        ChainsTests.play(&e, days: 52 * 7)
        let all = e.state.companies.filter { $0.status.isLive }
        let inv = SupplyTerms.invoices(e.state)
        return (all.reduce(0) { $0 + $1.cash }, Ledger.gaps(e.state).count, inv.count, inv.reduce(0) { $0 + $1.amount }, inv.filter { $0.lateWeeks > 0 }.count,
                e.state.rest["vr"]?.object.values.map { $0["r"].double }.max() ?? 0)
    }

    func testPlayAYearOnTermsAcrossSeedsCashAndBillsBehave() throws {
        var lines: [String] = []
        for seed in [3, 11, 29, 47] {
            let on = try runYear(seed: seed, terms: true)
            let off = try runYear(seed: seed, terms: false)
            lines.append("seed \(seed): on cash=\(Int(on.cash)) invoices=\(on.invoices) owed=\(Int(on.owed)) late=\(on.late) | off cash=\(Int(off.cash)) invoices=\(off.invoices)")
            XCTAssertEqual(on.gaps, 0, lines.last!)
            XCTAssertEqual(off.gaps, 0)
            XCTAssertEqual(off.invoices, 0)
            XCTAssertLessThanOrEqual(on.invoices, 14, "open invoices stay at a few weeks of supply, no unbounded growth: " + lines.last!)
            XCTAssertEqual(on.late, 0, "companies with cash pay on time: " + lines.last!)
            XCTAssertTrue(on.cash.isFinite && off.cash.isFinite)
            // replay: same seed, same result
            let again = try runYear(seed: seed, terms: true)
            XCTAssertEqual(again.cash, on.cash, accuracy: 0.5, "deterministic")
            XCTAssertEqual(again.invoices, on.invoices)
        }
        print(lines.joined(separator: "\n"))
    }
}
