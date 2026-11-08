import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
import Simulation

/// What a manager does on their own (price band, stock, marketing ceiling), the owner's five orders, and the end of the hire proposal.
final class ManagerStoreTests: XCTestCase {
    private func managedCafe(seed: Int) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 90_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 30_000_000) else { throw XCTSkip("no company") }
        let cands = try XCTUnwrap(e.searchManagers(companyID: id))
        XCTAssertEqual(e.hireManager(personID: cands[0].id, companyID: id, monthlyWage: cands[0].askingMonthlyWage * 1.2), .ok)
        return (e, id)
    }

    private func ratios(_ e: GameEngine, _ id: Int) -> [Double] {
        SalesItems.rows(e.state, companyID: id, data: e.data).filter { $0.marketPrice > 0 && SalesItems.refusal(e.state, companyID: id, itemID: $0.id, data: e.data) == nil }.map { $0.price / $0.marketPrice }
    }

    private func review(_ e: inout GameEngine, _ id: Int) {
        e.update { s, d, _ in ManagerStore.pricing(&s, s.companyIndex(id)!, by: "", data: d) }
    }

    func testTheFiveOrdersNeedAManager() throws {
        let (e, id) = try managedCafe(seed: 5)
        XCTAssertEqual(e.managerOrders(companyID: id).map(\.key), [.direction, .budget, .headcount, .pay, .replace])
        XCTAssertEqual(e.managerOrders(companyID: id).map(\.title), ["Direction", "Budget", "Headcount", "Pay and bonus", "Replace"])
        var none = e
        none.update { s, _, _ in s.companies[s.companyIndex(id)!].managerID = nil }
        XCTAssertTrue(none.managerOrders(companyID: id).isEmpty)
    }

    func testTheDirectionIsSetAndReadBack() throws {
        var (e, id) = try managedCafe(seed: 5)
        XCTAssertEqual(e.managerOrders(companyID: id)[0].value, "Steady")
        e.setDirection(companyID: id, direction: .quality)
        XCTAssertEqual(ManagerModel.direction(of: try XCTUnwrap(e.state.company(id))), .quality)
        XCTAssertEqual(e.managerOrders(companyID: id)[0].value, "Quality first")
        e.setDirection(companyID: id, direction: nil)
        XCTAssertNil(ManagerModel.direction(of: try XCTUnwrap(e.state.company(id))))
        XCTAssertTrue(ManagerModel.Direction.grow.marketingShare > ManagerModel.Direction.quality.marketingShare)
        XCTAssertTrue(ManagerModel.Direction.lean.marketingShare > ManagerModel.Direction.cash.marketingShare)
        XCTAssertEqual(ManagerModel.Direction.allCases.map(\.priceSteps), [-1, 0, 1, 1])
    }

    func testPricesMoveOneStepAtATimeInsideTheBandTheDirectionPicks() throws {
        var (e, id) = try managedCafe(seed: 6)
        XCTAssertFalse(ratios(e, id).isEmpty)
        e.setDirection(companyID: id, direction: .grow)
        review(&e, id)
        XCTAssertTrue(ratios(e, id).allSatisfy { abs($0 - 0.95) < 1e-6 }, "grow: one step under the market")
        review(&e, id)
        XCTAssertTrue(ratios(e, id).allSatisfy { abs($0 - 0.95) < 1e-6 }, "the band's edge holds")
        e.setDirection(companyID: id, direction: .quality)
        review(&e, id)
        XCTAssertTrue(ratios(e, id).allSatisfy { abs($0 - 1.0) < 1e-6 })
        review(&e, id)
        XCTAssertTrue(ratios(e, id).allSatisfy { abs($0 - 1.05) < 1e-6 }, "quality: one step over")
        e.setDirection(companyID: id, direction: .lean)
        review(&e, id)
        XCTAssertTrue(ratios(e, id).allSatisfy { abs($0 - 1.0) < 1e-6 }, "lean holds the market price")
        XCTAssertFalse((e.state.company(id)?.value("mgrLog").array ?? []).isEmpty, "the move is in the manager's report")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testAManagerOrdersStockOnlyWithinTheBudgetAndPolicy() throws {
        var (e, id) = try managedCafe(seed: 7)
        var cogs = 0.0
        e.update { s, d, _ in
            let ci = s.companyIndex(id)!
            cogs = World(state: s, data: d).currency(s.companies[ci]).scaledPrice(2000)
            var lw = s.companies[ci].value("lastW"); lw["cogs"] = .number(cogs); s.companies[ci].set("lastW", lw)
            s.companies[ci].inventory = 0
        }
        let co = try XCTUnwrap(e.state.company(id)), bd = try XCTUnwrap(e.data.catalog[co.type])
        guard let target = StockHandling.policyTarget(co, bd) else { throw XCTSkip("this trade holds no stock") }
        let n = try XCTUnwrap(e.state.people[try XCTUnwrap(co.managerID)])
        e.setManagerBudget(companyID: id, budget: .tight)
        var ordered: Double?
        e.update { s, d, _ in ordered = StockHandling.managerOrder(&s, s.companyIndex(id)!, bd, manager: n, data: d) }
        XCTAssertNil(ordered, "a tight budget asks first")
        e.setManagerBudget(companyID: id, budget: .free)
        let before = try XCTUnwrap(e.state.company(id)).cash
        e.update { s, d, _ in ordered = StockHandling.managerOrder(&s, s.companyIndex(id)!, bd, manager: n, data: d) }
        let after = try XCTUnwrap(e.state.company(id))
        XCTAssertNotNil(ordered)
        XCTAssertLessThanOrEqual(after.inventory, target * 0.9 + 1)
        XCTAssertEqual(before - after.cash, ordered ?? 0, accuracy: 1e-6)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testOpenHireProposalsOfAnOldSaveAreClosedAndSeasonalOnesToo() throws {
        var (e, id) = try managedCafe(seed: 8)
        e.update { s, _, _ in
            for (act, t) in [("prop", "hire"), ("prop", "seas"), ("mprop", "hire"), ("prop", "eq")] {
                s.addMessage(kind: "ask", from: "M", title: t, body: "", companyID: id, tone: "n", status: "open", options: [.option("Approve")], action: act,
                             data: .object(["t": .string(t), "role": "barista", "cost": 1, "id": ""]), expiresWeek: s.week + 3)
            }
            Budget.migrate(&s)
        }
        let open = e.state.inbox.filter { $0.companyID == id && $0.from == "M" && $0.status == "open" }.map { $0.title }
        XCTAssertEqual(open, ["eq"], "only the equipment question is still open")
    }
}
