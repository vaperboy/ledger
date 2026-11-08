import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

/// The one budget per manager or executive: three presets scaled to the country, one rule (above the budget the owner is asked), and old saves
/// read as the nearest preset.
final class BudgetTests: XCTestCase {
    private func gameWithManager() throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5)
        e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 30_000_000) else { throw XCTSkip("no company") }
        let cands = try XCTUnwrap(e.searchManagers(companyID: id))
        XCTAssertEqual(e.hireManager(personID: cands[0].id, companyID: id, monthlyWage: cands[0].askingMonthlyWage * 1.2), .ok)
        return (e, id)
    }

    // MARK: Presets

    func testPresetsFollowTheCountryAndGrowFromTightToFree() throws {
        let book = try CountryBook.bundled()
        for c in book.countries {
            let cur = Currency(country: c, rates: ExchangeRates())
            XCTAssertEqual(Budget.tight.spendLimit(cur), 0, c.code)
            XCTAssertEqual(Budget.normal.spendLimit(cur), cur.scaledPrice(25000), accuracy: 1e-6, "\(c.code): normal is the country's base amount")
            XCTAssertEqual(Budget.free.spendLimit(cur), Budget.unlimited, c.code)
            XCTAssertLessThan(Budget.tight.payLimit(cur), Budget.normal.payLimit(cur), c.code)
            XCTAssertLessThan(Budget.normal.payLimit(cur), Budget.normal.spendLimit(cur), c.code)
            // the higher the post, the bigger the normal budget
            XCTAssertLessThan(Budget.normal.spendLimit(cur, kind: "region"), Budget.normal.spendLimit(cur, kind: "chainmgr"), c.code)
            XCTAssertLessThan(Budget.normal.spendLimit(cur, kind: "chainmgr"), Budget.normal.spendLimit(cur, kind: "ceo56"), c.code)
            XCTAssertLessThan(Budget.normal.spendLimit(cur, kind: "ceo56"), Budget.normal.spendLimit(cur, kind: "md"), c.code)
        }
        let ch = Currency(country: book["CH"]!, rates: ExchangeRates()), br = Currency(country: book["BR"]!, rates: ExchangeRates())
        XCTAssertGreaterThan(book["CH"]!.costIndex, book["BR"]!.costIndex)
        XCTAssertGreaterThan(Budget.normal.spendLimit(ch), Budget.normal.spendLimit(br), "a dearer country has a bigger budget in its own money")
    }

    func testAManagersNormalBudgetGrowsWithTheCompanyButNeverBelowTheBase() throws {
        let cur = Currency(country: try CountryBook.bundled()["UK"]!, rates: ExchangeRates())
        let base = Budget.normal.spendLimit(cur)
        XCTAssertEqual(Budget.normal.spendLimit(cur, monthlyRevenue: 1), base)
        XCTAssertGreaterThan(Budget.normal.spendLimit(cur, monthlyRevenue: base * 100), base)
        XCTAssertEqual(Budget.free.spendLimit(cur, monthlyRevenue: base * 100), Budget.unlimited)
    }

    func testTheOneRuleAnythingAboveTheBudgetIsTheOwners() throws {
        let cur = Currency(country: try CountryBook.bundled()["UK"]!, rates: ExchangeRates())
        let limit = Budget.normal.spendLimit(cur)
        XCTAssertTrue(Budget.normal.covers(limit, cur))
        XCTAssertFalse(Budget.normal.covers(limit * 1.01, cur))
        XCTAssertFalse(Budget.tight.covers(1, cur), "a tight budget asks about everything that costs money")
        XCTAssertTrue(Budget.free.covers(limit * 1000, cur))
        let pay = Budget.normal.payLimit(cur)
        XCTAssertTrue(Budget.normal.covers(pay, monthly: true, cur))
        XCTAssertFalse(Budget.normal.covers(pay * 1.01, monthly: true, cur))
    }

    // MARK: Old saves

    func testOldAuthorityReadsAsTheNearestPreset() throws {
        XCTAssertEqual(Budget.of(.object(["lvl": 0, "buy": 25000])), .tight)
        XCTAssertEqual(Budget.of(.object(["lvl": 1, "buy": 25000])), .normal)
        XCTAssertEqual(Budget.of(.object(["lvl": 1, "buy": 0])), .tight, "within limits with no spending limit asks about everything")
        XCTAssertEqual(Budget.of(.object(["lvl": 2, "buy": 1])), .free)
        XCTAssertEqual(Budget.of(.object([:])), .tight)
        XCTAssertEqual(Budget.of(.object(["bud": 2, "lvl": 0])), .free, "a stored budget wins over the old fields")
    }

    func testMigrationRewritesManagersAndExecutivesAndIsRepeatable() throws {
        var (e, id) = try gameWithManager()
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].set("auth", .object(["lvl": 2, "buy": 1000, "hire": 5, "ad": 2, "set22": true]))
            s.rest["group"] = .object(["ceo": .null, "big": 1, "regional": .array([.object(["id": 7, "npc": 9, "lvl": 1, "buy": 5000, "wage": 100])])])
            Budget.migrate(&s)
        }
        let a = try XCTUnwrap(e.state.company(id)).value("auth")
        XCTAssertEqual(a["bud"].int, 2)
        XCTAssertTrue(a["hire"].isNull && a["ad"].isNull && a["set22"].isNull, "the old limits are gone")
        XCTAssertTrue(a["chosen"].bool, "a budget the owner set stays chosen")
        XCTAssertEqual(ManagerModel.budget(of: try XCTUnwrap(e.state.company(id))), .free)
        let rec = e.state.rest["group"]?["regional"][0] ?? .null
        XCTAssertEqual(rec["bud"].int, 1)
        XCTAssertTrue(rec["lvl"].isNull && rec["buy"].isNull)
        XCTAssertEqual(rec["wage"].int, 100, "nothing else on the record changes")
        let once = e.state.rest["group"]
        e.update { s, _, _ in Budget.migrate(&s) }
        XCTAssertEqual(e.state.rest["group"], once)
        XCTAssertEqual(try XCTUnwrap(e.state.company(id)).value("auth"), a)
    }

    func testAppointedManagersStartOnNormalUnlessTheOwnerChose() throws {
        var (e, id) = try gameWithManager()
        XCTAssertEqual(ManagerModel.budget(of: try XCTUnwrap(e.state.company(id))), .normal)
        XCTAssertFalse(Budget.isChosen(try XCTUnwrap(e.state.company(id)).value("auth")))
        e.setManagerBudget(companyID: id, budget: .tight)
        XCTAssertEqual(ManagerModel.budget(of: try XCTUnwrap(e.state.company(id))), .tight)
        XCTAssertTrue(Budget.isChosen(try XCTUnwrap(e.state.company(id)).value("auth")))
    }

    func testTheOldAuthorityCallStillSetsThePreset() throws {
        var (e, id) = try gameWithManager()
        e.setManagerAuthority(companyID: id, level: 2, buy: 1, pay: 1, ad: 1)
        XCTAssertEqual(ManagerModel.budget(of: try XCTUnwrap(e.state.company(id))), .free)
        e.setManagerAuthority(companyID: id, level: 0)
        XCTAssertEqual(ManagerModel.budget(of: try XCTUnwrap(e.state.company(id))), .tight)
    }

    // MARK: The ask

    func testAProposalAboveTheBudgetComesToTheOwnerAndOneBelowDoesNot() throws {
        var (e, id) = try gameWithManager()
        let co = try XCTUnwrap(e.state.company(id)), mid = try XCTUnwrap(co.managerID)
        let limit = ManagerModel.spendLimit(of: co, e.state, data: e.data)
        XCTAssertGreaterThan(limit, 0)
        XCTAssertTrue(ManagerModel.withinBudget(co, amount: limit, e.state, data: e.data))
        XCTAssertFalse(ManagerModel.withinBudget(co, amount: limit * 1.5, e.state, data: e.data))
        // premises space that costs twice the budget is the owner's to approve
        let manager = try XCTUnwrap(e.state.people[mid])
        e.update { s, d, _ in
            let ci = s.companyIndex(id)!
            ManagerModel.propose(&s, ci, ManagerModel.Proposal(kind: "space", cost: limit * 2), manager, 0.5, data: d)
        }
        XCTAssertNotNil(e.state.inbox.first { $0.companyID == id && $0.actionID == "prop" && $0.status == "open" }, "above the budget: the owner is asked")
        // on a free budget nothing is above it
        e.setManagerBudget(companyID: id, budget: .free)
        let free = try XCTUnwrap(e.state.company(id))
        XCTAssertTrue(ManagerModel.withinBudget(free, amount: limit * 1000, e.state, data: e.data))
        // on a tight budget even a small amount is asked
        e.setManagerBudget(companyID: id, budget: .tight)
        XCTAssertFalse(ManagerModel.withinBudget(try XCTUnwrap(e.state.company(id)), amount: 1, e.state, data: e.data))
        // no manager: everything is the owner's
        var noManager = free
        noManager.managerID = nil
        XCTAssertFalse(ManagerModel.withinBudget(noManager, amount: 0, e.state, data: e.data))
    }

    func testABossAboveReadsItsBudgetFromTheSamePresets() throws {
        let cur = Currency(country: try CountryBook.bundled()["UK"]!, rates: ExchangeRates())
        var boss = ManagerModel.Boss(kind: "chainmgr", personID: 1, level: Budget.normal.rawValue, buy: Budget.normal.spendLimit(cur, kind: "chainmgr"), regionalID: nil, name: "A")
        XCTAssertTrue(boss.decides(boss.buy))
        XCTAssertFalse(boss.decides(boss.buy * 2), "above the budget it goes up")
        boss.level = Budget.tight.rawValue; boss.buy = 0
        XCTAssertFalse(boss.decides(1))
        boss.level = Budget.free.rawValue; boss.buy = Budget.unlimited
        XCTAssertTrue(boss.decides(1e9))
    }
}
