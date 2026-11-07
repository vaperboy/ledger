import XCTest
import GameCore
import Finance
import Businesses
@testable import Events
@testable import Simulation

/// Old startup blobs become companies, the club purchase plan shows the money, the explicit quick set-up stays inside the cash.
final class StakesAndSetupTests: XCTestCase {
    func testLegacyStartupBlobBecomesARealCompanyWithoutLosingMoneyOrShare() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 4)
        e.update { s, _, _ in
            Ledger.move(&s, .me, 2_000_000_000, why: "funds")
            let f: JSONValue = .object(["id": 777, "name": "Oldco", "sec": "saas", "secn": "CRM", "ck": 1, "stage": 0, "pct": 60, "val": 3_000_000, "cash": 4_000_000, "burn": 20_000,
                                         "in": 4_000_000, "q": 0.5, "tr": 0.1, "w0": 0, "st": "live",
                                         "sw16": .object(["cat": "saas", "prod": "crm", "model": "sub", "devs": 2, "selfH": 0, "prog": 0.3, "phase": "build", "cust": 0, "revW": 0, "int": 0, "use": .array([]), "deals": .array([]), "price": 1300])])
            s.rest["founded"] = .array([f])
        }
        for _ in 0..<7 { _ = e.nextDay() }
        let f = try XCTUnwrap(e.foundedStartups.first)
        XCTAssertNotEqual(f.companyID, 0)
        let co = try XCTUnwrap(e.state.company(f.companyID))
        XCTAssertEqual(co.ownership, 60, accuracy: 0.01)
        XCTAssertEqual(co.value("holders").array.reduce(0) { $0 + $1["pct"].double } + co.ownership, 100, accuracy: 1e-6)
        XCTAssertGreaterThan(co.cash, 3_000_000)
        XCTAssertGreaterThan(co.staff.count, 0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testQuickSetupWithinBudgetNeverHiresPastTheCash() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 9)
        var id = 0
        e.update { s, d, c in
            Ledger.move(&s, .me, 500_000_000, why: "funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "restaurant", cityID: s.player.cityID, form: .limited, data: d, context: c) { id = i }
            _ = Payments.injectCash(&s, companyID: id, amount: 2_500_000)
        }
        let rep = e.quickSetupWithinBudget(companyID: id)
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertFalse(rep.skipped.isEmpty, "what was left out is listed with its cost")
        XCTAssertTrue(rep.skipped.allSatisfy { $0.cost > 0 })
        XCTAssertGreaterThanOrEqual(co.cash, -1)
    }

    func testClubPurchasePlanShowsDebtAndCashLeft() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 2)
        guard let country = e.leagueCountries().first else { return }
        e.update { s, d, _ in FootballModel.ensureClubs(&s, country) }
        guard let club = e.clubsForSale(countryCode: country.code).first(where: { $0.owner != "you" }) else { return }
        let plan = try XCTUnwrap(e.clubPurchasePlan(clubID: club.id, price: club.value))
        XCTAssertEqual(plan.liquidAfter, plan.liquidBefore - club.value, accuracy: 1)
        XCTAssertGreaterThan(plan.clubCash, 0)
        XCTAssertEqual(plan.affordable, plan.liquidAfter >= 0)
    }

    private func holderGame() throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 6)
        var id = 0
        e.update { s, d, c in
            Ledger.move(&s, .me, 900_000_000, why: "funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, form: .limited, data: d, context: c) { id = i }
            _ = Payments.injectCash(&s, companyID: id, amount: 30_000_000)
            let i = s.companyIndex(id)!
            CapTable.issue(&s, i, newShares: CapTable.sharesForPercent(20, total: CapTable.table(s.companies[i]).total), to: "Old Holder", paid: 1)
        }
        return (e, id)
    }

    func testRightOfFirstRefusalLetsYouBuyTheStakeFirst() throws {
        var (e, id) = try holderGame()
        let cash0 = e.state.cash + e.state.savings
        e.update { s, d, c in
            let i = s.companyIndex(id)!
            let data: JSONValue = .object(["co": .number(Double(id)), "kind": "rofr", "amt": 1_000_000, "hn": "Old Holder", "buyer": "Rival Capital", "g": .null, "gn": ""])
            Shareholders.resolve(&s, i, data, 0, data: d, context: c)
        }
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(co.ownership, 100, accuracy: 1e-9)
        XCTAssertTrue(co.value("holders").array.isEmpty)
        XCTAssertEqual(cash0 - (e.state.cash + e.state.savings), 1_000_000, accuracy: 1)
    }

    func testLettingThemSellMovesTheSharesToTheBuyerAndPaysNobody() throws {
        var (e, id) = try holderGame()
        let cash0 = e.state.cash + e.state.savings
        let before = CapTable.table(try XCTUnwrap(e.state.company(id)))
        e.update { s, d, c in
            let i = s.companyIndex(id)!
            let data: JSONValue = .object(["co": .number(Double(id)), "kind": "rofr", "amt": 1_000_000, "hn": "Old Holder", "buyer": "Rival Capital", "g": .null, "gn": ""])
            Shareholders.resolve(&s, i, data, 1, data: d, context: c)
        }
        let co = try XCTUnwrap(e.state.company(id))
        let after = CapTable.table(co)
        XCTAssertEqual(after.total, before.total)
        XCTAssertEqual(after.holders.map { $0.name }, ["Rival Capital"])
        XCTAssertEqual(after.holders.first?.shares, before.holders.first?.shares)
        XCTAssertEqual(e.state.cash + e.state.savings, cash0, accuracy: 0.5, "neither you nor the company is paid")
    }

    func testFoundedStartupIsRegisteredHasAnAccountantAndASupportHire() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 3)
        e.update { s, _, _ in Ledger.move(&s, .me, 5_000_000_000, why: "funds") }
        let cash0 = e.state.cash + e.state.savings
        guard case .ok(let sid) = e.foundStartup(name: "Regco", sector: "saas", product: "crm", model: "sub", who: "c2", seedMultiple: 4) else { return XCTFail("found") }
        let co = try XCTUnwrap(e.state.company(sid))
        XCTAssertFalse(co.value("acc").isNull, "an accountant is appointed")
        XCTAssertTrue(co.staff.contains { $0.role == "ittech" }, "the first support hire is part of the founding team")
        let fee = e.homeCountry.registrationFee
        XCTAssertGreaterThan(fee, 0)
        let seed = e.homeCurrency.scaledPrice(StartupProducts.sector("saas")!.seed) * 4
        XCTAssertLessThanOrEqual(e.state.cash + e.state.savings, cash0 - fee - seed + 1)
    }
}
