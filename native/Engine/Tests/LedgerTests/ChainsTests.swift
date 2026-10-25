import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Chains, franchises (both sides) and supply between your own companies: they run, and the books balance.
final class ChainsTests: XCTestCase {
    static func engine(_ country: String = "NO", seed: Int = 11) throws -> GameEngine {
        var e = try GameEngine.newGame(countryCode: country, playerName: "T", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 20_000_000_000, why: "Test funds") }
        return e
    }
    static func start(_ e: inout GameEngine, _ trade: String, name: String? = nil) -> Int {
        var id = 0
        e.update { s, data, ctx in
            guard case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: .limited, name: name, data: data, context: ctx) else { return }
            id = i
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.5)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        return id
    }
    static func play(_ e: inout GameEngine, days: Int) {
        for _ in 0..<days {
            e.nextDay()
            for m in e.openDecisions where m.actionID.hasPrefix("pay29") || Franchising.handlesAnswer(m.actionID) { e.answer(messageID: m.id, option: 0) }
        }
    }
    /// Make a company look like it has run well for two years.
    static func season(_ e: inout GameEngine, _ id: Int) {
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].openedWeek = s.week - 200
            s.companies[i].reputation = 70
            s.companies[i].monthlyHistory = (0..<12).map { MonthRecord(monthIndex: $0, revenue: 400_000, profit: 90_000, cash: 0) }
            var docs = s.companies[i].value("docs")
            docs["chain"] = .object(["st": "ok", "done": 0, "ok": 0])
            docs["fran"] = .object(["st": "ok", "done": 0, "ok": 0])
            s.companies[i].set("docs", docs)
        }
    }

    func testBrandsAreStableAndTheTalkEndsInAContract() throws {
        var e = try Self.engine()
        let b1 = e.franchiseBrands(country: "NO").map { $0.id }
        XCTAssertEqual(b1, e.franchiseBrands(country: "NO").map { $0.id })
        let brand = try XCTUnwrap(["cafe", "gym", "barber", "bakery", "carclean"].lazy.compactMap { t in
            FranchiseBrands.brands(t, country: "NO", World(state: e.state, data: e.data)).first { $0.openness == "open" }
        }.first)
        XCTAssertEqual(e.applyToFranchiseBrand(brand.id, country: "NO"), .ok)
        for _ in 0..<(4 * 7) { e.nextDay() }
        XCTAssertEqual(e.franchiseApplication(brand.id)["st"].string, "invited")
        let n = try XCTUnwrap(e.negotiateFranchise(brand.id, ask: FranchiseBrands.Ask()))
        XCTAssertEqual(n.kind, .accept)
        e.signFranchiseTerms(brand.id, terms: try XCTUnwrap(n.terms))
        let r = e.startFranchisedCompany(brandID: brand.id, cityID: e.state.player.cityID, form: .limited, name: "Franchised", fundWith: 3_000_000_000)
        guard case .success(let id) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(e.state.company(id)?.value("franchise")["brandId"].string, brand.id)
        Self.play(&e, days: 40 * 7)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        XCTAssertNotNil(e.state.company(id))
    }

    /// A franchised unit can be started with a place of the player's choice: the plan prices the pick (plus the entry fee), and the unit
    /// ends up in exactly that place, bought or rented, still a franchisee of the brand.
    func testFranchisedUnitStartsInTheChosenPremises() throws {
        func prepared() throws -> (GameEngine, FranchiseBrands.Brand) {
            var e = try Self.engine()
            let brand = try XCTUnwrap(["cafe", "gym", "barber", "bakery"].lazy.compactMap { t in
                FranchiseBrands.brands(t, country: "NO", World(state: e.state, data: e.data)).first { $0.openness == "open" }
            }.first { e.data.catalog[$0.tradeID]?.premisesKind.map { $0 != "none" && $0 != "home" } ?? false })
            XCTAssertEqual(e.applyToFranchiseBrand(brand.id, country: "NO"), .ok)
            for _ in 0..<(4 * 7) { e.nextDay() }
            let n = try XCTUnwrap(e.negotiateFranchise(brand.id, ask: FranchiseBrands.Ask()))
            e.signFranchiseTerms(brand.id, terms: try XCTUnwrap(n.terms))
            return (e, brand)
        }
        let (e0, brand) = try prepared()
        let city = e0.state.player.cityID
        let std = try XCTUnwrap(e0.franchiseStartPlan(brandID: brand.id, cityID: city, form: .limited))
        XCTAssertEqual(std.plan.premisesKind, .place)
        XCTAssertGreaterThan(std.plan.options.count, 2)
        XCTAssertGreaterThan(std.fee, 0)
        let other = try XCTUnwrap(std.plan.options.first { $0.index != std.plan.standardIndex })
        let picked = try XCTUnwrap(e0.franchiseStartPlan(brandID: brand.id, cityID: city, form: .limited, pick: .init(listingIndex: other.index, buy: false)))
        XCTAssertEqual(picked.plan.premisesCost, other.rentUpfront, accuracy: 0.5)
        for buy in [false, true] {
            var (e, _) = try prepared()
            let r = e.startFranchisedCompanyChoosingPremises(brandID: brand.id, cityID: city, form: .limited, name: "Unit", pick: .init(listingIndex: other.index, buy: buy), fundWith: 3_000_000_000)
            guard case .success(let out) = r else { return XCTFail("\(r)") }
            XCTAssertEqual(out.premises, .ok)
            let co = try XCTUnwrap(e.state.company(out.companyID))
            XCTAssertEqual(co.value("franchise")["brandId"].string, brand.id)
            XCTAssertEqual(co.value("prem")["owned"].bool, buy)
            XCTAssertEqual(co.value("prem")["m2"].double, other.squareMetres, accuracy: 0.5)
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
        }
        // No pick: the old call and the new one with no pick agree on the standard place.
        var (a, _) = try prepared(), (b, _) = try prepared()
        guard case .success(let ida) = a.startFranchisedCompany(brandID: brand.id, cityID: city, form: .limited, name: "U", fundWith: 3_000_000_000),
              case .success(let outb) = b.startFranchisedCompanyChoosingPremises(brandID: brand.id, cityID: city, form: .limited, name: "U", pick: nil, fundWith: 3_000_000_000) else { return XCTFail("start") }
        XCTAssertEqual(a.state.company(ida)?.value("prem"), b.state.company(outb.companyID)?.value("prem"))
    }

    func testChainOpensStoresAndRunsOnSharedRules() throws {
        var e = try Self.engine()
        let first = Self.start(&e, "cafe")
        XCTAssertFalse(e.chainRequirements(companyID: first).allSatisfy { $0.ok })
        Self.season(&e, first)
        e.update { s, _, _ in if let i = s.companyIndex(first) { s.companies[i].set("mgr", 0) } }   // no manager needed for this check
        let id = try XCTUnwrap(e.makeChain(companyID: first, name: "Test Cafe"))
        e.setChainRule(chainID: id, rule: .price(1))
        guard case .success(let second) = e.openChainStore(chainID: id, cityID: e.state.player.cityID, size: 1) else { return XCTFail("store not opened") }
        XCTAssertEqual(e.state.company(second)?.priceLevel, 1)
        XCTAssertTrue(e.state.company(second)?.name.hasPrefix("Test Cafe") ?? false)
        Self.play(&e, days: 30 * 7)
        let sum = try XCTUnwrap(e.chainSummary(id: id))
        XCTAssertEqual(sum.stores.count, 2)
        XCTAssertGreaterThanOrEqual(sum.reach.outlets, 2)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testFranchisorGetsUnitsAndRoyalties() throws {
        var e = try Self.engine()
        let id = Self.start(&e, "cafe")
        Self.season(&e, id)
        // a franchise system, as if the requirements were met
        e.update { s, _, _ in
            if let i = s.companyIndex(id) {
                s.companies[i].set("fr", .object(["on": 1, "fee": 150_000, "roy": 0.06, "supp": 0, "share": 0.45, "brand": 30, "mkt": 0.02, "units": .array([]), "app": .array([]), "w0": .number(Double(s.week))]))
            }
        }
        var signed = false
        for _ in 0..<(60 * 7) where !signed {
            e.nextDay()
            for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
            if let a = e.franchiseApplicants(companyID: id).first {
                var t = e.standardTalkTerms(companyID: id)
                t.feeFactor = 0.5
                t.help = "l50"
                if let r = e.offerToApplicant(companyID: id, applicantID: a.id, terms: t) { signed = r.signed }
            }
        }
        XCTAssertTrue(signed, "an applicant should sign within a year")
        let cash0 = try XCTUnwrap(e.state.company(id)).cash
        Self.play(&e, days: 30 * 7)
        XCTAssertFalse(e.franchiseSystem(companyID: id)["units"].array.isEmpty)
        XCTAssertGreaterThan(e.franchiseSystem(companyID: id)["income"].double, 0)
        XCTAssertNotEqual(try XCTUnwrap(e.state.company(id)).cash, cash0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testSupplyBetweenYourOwnCompaniesMovesMoneyAndBalances() throws {
        var e = try Self.engine()
        let hotel = Self.start(&e, "hotel")
        let cleaning = Self.start(&e, "cleaning")
        Self.play(&e, days: 10 * 7)
        let k = try XCTUnwrap(e.supplyKinds(companyID: hotel).first { $0.id == "clean" })
        XCTAssertTrue(e.possibleSuppliers(buyer: hotel, kind: k.id).contains { $0.id == cleaning })
        XCTAssertTrue(e.setSupplier(buyer: hotel, kind: k.id, supplier: cleaning, mode: "c10"))
        Self.play(&e, days: 20 * 7)
        let l = try XCTUnwrap(e.supplyLink(buyer: hotel, kind: k.id))
        XCTAssertGreaterThan(l.lastSpend, 0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        e.clearSupplier(buyer: hotel, kind: k.id)
        XCTAssertNil(e.supplyLink(buyer: hotel, kind: k.id))
    }
}
