import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Events
import Simulation

final class ChainBranchesTests: XCTestCase {
    private func chain() throws -> (e: GameEngine, chainID: Int, a: Int, b: Int) {
        var e = try ChainsTests.engine()
        let a = ChainsTests.start(&e, "cafe")
        ChainsTests.season(&e, a)
        e.update { s, _, _ in if let i = s.companyIndex(a) { s.companies[i].set("mgr", 0) } }
        let id = try XCTUnwrap(e.makeChain(companyID: a, name: "Test Cafe"))
        XCTAssertFalse(e.isBranch(companyID: a), "a chain of one store is just the company")
        guard case .success(let b) = e.openLocation(chainID: id, cityID: e.state.player.cityID) else { throw XCTSkip("store not opened") }
        _ = e.openCompany(companyID: b)
        XCTAssertTrue(e.isBranch(companyID: a) && e.isBranch(companyID: b))
        return (e, id, a, b)
    }
    private func balanced(_ e: GameEngine, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(what): \(Ledger.gaps(e.state))", file: file, line: line)
    }

    func testClosingABranchWindsItDownIntoTheChain() throws {
        var (e, chainID, a, b) = try chain()
        e.update { s, _, _ in Payments.injectCash(&s, companyID: b, amount: 5_000_000) }
        let gone = try XCTUnwrap(e.state.company(a)?.staff.first(where: { m in e.state.company(b)?.staff.contains { $0.role == m.role } ?? false }))
        e.update { s, _, _ in
            if let i = s.companyIndex(a) { s.companies[i].staff = s.companies[i].staff.filter { $0.id != gone.id } }
            if var p = s.people[gone.id] { p.employerID = 0; s.people[gone.id] = p }
        }
        let plan = try XCTUnwrap(e.branchClosurePlan(storeID: b))
        XCTAssertEqual(plan.receiverID, a)
        XCTAssertTrue(plan.transfers.contains { $0.role == gone.role && $0.toStoreID == a })
        let bStaff = e.state.company(b)!.staff.map { $0.id }
        let inv0 = e.state.company(a)!.inventory, me0 = e.state.cash
        guard case .success = e.closeBranch(storeID: b) else { return XCTFail("not closed") }
        XCTAssertEqual(e.state.company(b)?.status, .sold)
        XCTAssertEqual(e.state.company(b).flatMap { ChainBranches.ending($0) }, "closed")
        XCTAssertEqual(e.state.company(b)?.cash, 0)
        for t in plan.transfers { XCTAssertEqual(e.state.people[t.staffID]?.employerID, a) }
        for id in bStaff where !plan.transfers.contains(where: { $0.staffID == id }) { XCTAssertEqual(e.state.people[id]?.employerID, 0, "made redundant") }
        XCTAssertEqual(e.state.company(a)!.inventory, inv0 + plan.stockMoved, accuracy: 1)
        XCTAssertEqual(e.state.cash, me0, "closing a branch pays the chain, not the owner")
        XCTAssertFalse(e.isBranch(companyID: a), "one store left: the chain is a single company again")
        XCTAssertEqual(Chains.stores(e.state, Chains.chain(e.state, id: chainID)!).map { $0.id }, [a])
        balanced(e, "branch closed")
        ChainsTests.play(&e, days: 14)
        balanced(e, "two weeks after the closure")
    }

    func testSellingABranchAsAGoingConcern() throws {
        var (e, _, a, b) = try chain()
        ChainsTests.season(&e, b)
        let q = try XCTUnwrap(e.branchSaleQuote(storeID: b))
        XCTAssertGreaterThan(q.price, 0)
        XCTAssertGreaterThan(q.yearlyRevenue, 0)
        let staff = e.state.company(b)!.staff.map { $0.id }
        let me0 = e.state.cash
        guard case .success(let done) = e.sellBranch(storeID: b) else { return XCTFail("not sold") }
        XCTAssertEqual(done.price, q.price)
        XCTAssertEqual(e.state.company(b).flatMap { ChainBranches.ending($0) }, "sold")
        for id in staff { XCTAssertEqual(e.state.people[id]?.employerID, 0, "the staff go with the business") }
        XCTAssertTrue(e.state.company(a)!.transactions.contains { $0["l"].string.hasPrefix("Sale of") && abs($0["a"].double - q.price) < 1 }, "the price goes to the chain")
        XCTAssertEqual(e.state.cash, me0)
        XCTAssertEqual(e.closeBranch(storeID: a).failureValue, .notABranch, "the last store is the company itself")
        balanced(e, "branch sold")
    }

    func testABranchHasNoSharesOfItsOwn() throws {
        var (e, _, _, b) = try chain()
        XCTAssertEqual(SaleListings.routeProblem(e.state, companyID: b, route: "private", pct: 10), SaleListings.branchNote)
        XCTAssertEqual(e.saleQuote(companyID: b, percent: 10, method: .ipo)?.problem, SaleListings.branchNote)
        XCTAssertFalse(Funding.canRaise(e.state, companyID: b))
        var issued = -1
        e.update { s, _, _ in issued = CapTable.issue(&s, s.companyIndex(b)!, newShares: 10, to: "X", paid: 0) }
        XCTAssertEqual(issued, 0)
        XCTAssertTrue(e.state.company(b)!.value("holders").array.isEmpty)
    }

    func testAStoreBoardJoinsTheChainBoardAndNewKeysSurviveASave() throws {
        var (e, chainID, _, b) = try chain()
        e.update { s, d, _ in
            if let i = s.companyIndex(b) { s.companies[i].set("brd", .object(["seats": .array([.object(["id": 424242, "r": "director"])])])) }
            ChainBranches.weekly(&s, data: d)
        }
        XCTAssertTrue(e.state.company(b)!.value("brd").isNull)
        XCTAssertTrue(ManagerModel.board(e.state, key: "ch:\(chainID)")["seats"].array.contains { $0["id"].int == 424242 })
        e.update { s, _, _ in var ch = Chains.chain(s, id: chainID)!; ch["neg"] = 3; Chains.save(&s, ch) }
        let again = try JSONDecoder().decode(GameState.self, from: try JSONEncoder().encode(e.state))
        XCTAssertEqual(Chains.chain(again, id: chainID)?["neg"].int, 3)
    }
}

private extension Result {
    var failureValue: Failure? { if case .failure(let f) = self { return f }; return nil }
}
