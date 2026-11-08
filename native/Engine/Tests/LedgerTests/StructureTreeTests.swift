import XCTest
import GameCore
import Businesses
import Simulation

/// The Group Structure model: who hangs under whom, owner lines, chain versus head office, and the health roll-up.
final class StructureTreeTests: XCTestCase {
    private func open(_ e: inout GameEngine, _ id: Int) {
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .open } }
    }

    func testStandaloneCompanyHangsUnderYou() throws {
        var e = try ChainsTests.engine("UK")
        let a = ChainsTests.start(&e, "cafe")
        open(&e, a)
        let tree = e.structureTree()
        XCTAssertEqual(tree.first?.kind, .you)
        let n = try XCTUnwrap(tree.first { $0.companyID == a })
        XCTAssertEqual(n.kind, .company)
        XCTAssertEqual(n.parentID, "you")
        XCTAssertEqual(n.ownerYouPercent, 100, accuracy: 0.001)
        XCTAssertNil(n.holdingPercent)
        XCTAssertNil(n.tierTitle)
    }

    func testHoldingWithASubsidiaryAndADivision() throws {
        var e = try ChainsTests.engine("UK")
        let a = ChainsTests.start(&e, "cafe"), b = ChainsTests.start(&e, "cafe")
        open(&e, a); open(&e, b)
        guard case .success(let hid) = e.createHolding(name: "Alpha Holding", companies: [a, b]) else { throw XCTSkip("holding could not be created") }
        e.update { s, _, _ in if let i = s.companyIndex(b) { s.companies[i].set("div", .number(Double(hid))) } }
        let tree = e.structureTree()
        let h = try XCTUnwrap(tree.first { $0.companyID == hid })
        XCTAssertEqual(h.kind, .holding)
        XCTAssertEqual(h.parentID, "you")
        let sub = try XCTUnwrap(tree.first { $0.companyID == a })
        XCTAssertEqual(sub.parentID, h.id)
        XCTAssertEqual(sub.tierTitle, "100% yours")
        XCTAssertEqual(try XCTUnwrap(sub.holdingPercent), 100, accuracy: 0.001)
        let div = try XCTUnwrap(tree.first { $0.companyID == b })
        XCTAssertEqual(div.kind, .division)
        XCTAssertEqual(div.parentID, h.id)
        XCTAssertEqual(e.ownerLine(companyID: a).holdingID, hid)
    }

    func testChainIsItsOwnNodeAndHeadOfficeIsALocation() throws {
        var e = try ChainsTests.engine()
        let a = ChainsTests.start(&e, "cafe")
        ChainsTests.season(&e, a)
        e.update { s, _, _ in if let i = s.companyIndex(a) { s.companies[i].set("mgr", 0) } }
        let chainID = try XCTUnwrap(e.makeChain(companyID: a, name: "Test Cafe"))
        var ids = [a]
        for _ in 0..<2 {
            guard case .success(let b) = e.openChainStore(chainID: chainID, cityID: e.state.player.cityID, size: 1) else { throw XCTSkip("store not opened") }
            _ = e.openCompany(companyID: b)
            ids.append(b)
        }
        let tree = e.structureTree()
        let chain = try XCTUnwrap(tree.first { $0.kind == .chain })
        XCTAssertEqual(chain.id, "chain:\(chainID)")
        XCTAssertNil(chain.companyID, "the chain is not its head-office store")
        XCTAssertEqual(chain.parentID, "you")
        let places = tree.filter { $0.parentID == chain.id }
        XCTAssertEqual(places.count, 3)
        XCTAssertEqual(places.first?.kind, .headOffice)
        XCTAssertEqual(places.first?.companyID, a)
        XCTAssertEqual(places.filter { $0.kind == .branch }.count, 2)
        XCTAssertEqual(e.branchParent(companyID: ids[1])?.index, 2)
        XCTAssertEqual(e.branchParent(companyID: ids[1])?.count, 3)
        XCTAssertEqual(e.branchParent(companyID: a)?.headOfficeID, a)
    }

    func testOwnerLineAddsUpWithOutsideOwners() throws {
        var e = try ChainsTests.engine("UK")
        let a = ChainsTests.start(&e, "cafe")
        e.update { s, _, _ in
            guard let i = s.companyIndex(a) else { return }
            s.companies[i].ownership = 70
            s.companies[i].set("holders", .array([.object(["hid": 0, "pct": 30, "sh": 30])]))
        }
        let o = e.ownerLine(companyID: a)
        XCTAssertEqual(o.youPercent, 70, accuracy: 0.001)
        XCTAssertEqual(o.othersPercent, 30, accuracy: 0.001)
        XCTAssertNil(o.holdingID)
    }

    func testHealthRollsUpToTheWorstChild() throws {
        var e = try ChainsTests.engine("UK")
        let a = ChainsTests.start(&e, "cafe"), b = ChainsTests.start(&e, "cafe")
        open(&e, a); open(&e, b)
        e.update { s, _, _ in
            if let i = s.companyIndex(b) { s.companies[i].cash = -1_000; s.companies[i].monthlyHistory = (0..<6).map { MonthRecord(monthIndex: $0, revenue: 1_000, profit: -5_000, cash: 0) } }
        }
        let tree = e.structureTree()
        XCTAssertEqual(tree.first { $0.companyID == b }?.health, .struggling)
        XCTAssertEqual(e.structureHealth(companyIDs: [a, b]), .struggling)
        XCTAssertEqual(e.structureHealth(ids: ["co:\(b)"]), .struggling)
        XCTAssertEqual(e.structureHealth(ids: []), .setup)
    }
}
