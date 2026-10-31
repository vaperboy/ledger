import XCTest
import GameCore
import Finance
import Employees
import Businesses
import Simulation

/// Stage 6: the Group screen's "who manages whom" read model.
final class GroupManagementTests: XCTestCase {
    func testOwnerRunsEverythingUntilSomeoneIsAppointed() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 61)
        e.update { s, _, _ in Ledger.move(&s, .me, 90_000_000, why: "Test funds") }
        var ids: [Int] = []
        for _ in 0..<2 {
            guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 20_000_000) else { return XCTFail("start") }
            ids.append(id)
            e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .open } }
        }
        let g0 = e.groupManagement()
        XCTAssertEqual(g0.lines.count, 2)
        XCTAssertEqual(g0.runByYou.count, 2, "with nobody appointed the owner runs both companies")
        XCTAssertEqual(g0.managerCount, 0)
        XCTAssertTrue(g0.lines.allSatisfy { $0.runner == nil && $0.above.isEmpty && $0.firstToDecide == "You" })

        // Appoint a store manager to the first company with authority level 1: the line shows who runs it and what they may decide.
        e.update { s, _, _ in
            guard let i = s.companyIndex(ids[0]) else { return }
            var p = Person(raw: [:]); p.id = s.makeID(); p.name = "Anna Reed"
            s.people[p.id] = p
            s.companies[i].managerID = p.id
            s.companies[i].set("auth", .object(["lvl": 1, "buy": 0]))
        }
        let g1 = e.groupManagement()
        let line = try XCTUnwrap(g1.lines.first { $0.id == ids[0] })
        XCTAssertEqual(line.runner?.name, "Anna Reed")
        XCTAssertEqual(line.runner?.authority, 1)
        XCTAssertEqual(line.runner?.authorityText, "decides within your limits")
        XCTAssertEqual(line.firstToDecide, "Anna Reed")
        XCTAssertTrue(line.above.isEmpty, "no regional manager or group director above her")
        XCTAssertEqual(g1.managerCount, 1)
        XCTAssertEqual(g1.runByYou.map { $0.id }, [ids[1]], "the other company is still run by the owner")
        XCTAssertEqual(g1.delegated.map { $0.id }, [ids[0]])
        XCTAssertFalse(g1.groupOfficeEstablished, "the group office is never created for the owner")
    }
}
