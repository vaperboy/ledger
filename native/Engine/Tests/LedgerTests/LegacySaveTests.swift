import XCTest
import GameCore
import Finance
@testable import Simulation

final class LegacySaveTests: XCTestCase {
    private func oldSave(_ e: GameEngine, edit: (inout [String: JSONValue]) -> Void) throws -> GameState {
        var o = try JSONDecoder().decode([String: JSONValue].self, from: JSONEncoder().encode(e.state))
        o.removeValue(forKey: "pool")
        edit(&o)
        return try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(o))
    }

    private func editCompany(_ o: inout [String: JSONValue], at k: Int, _ change: (inout [String: JSONValue]) -> Void) {
        var cos = o["cos"]?.array ?? []
        var c = cos[k].object
        change(&c)
        cos[k] = .object(c)
        o["cos"] = .array(cos)
    }

    func testCompanyMoneyInAnOldSaveJoinsYourAccountOnce() throws {
        var e = try ChainsTests.engine("UK")
        let id = ChainsTests.start(&e, "cafe")
        let own = e.state.cash
        let loaded = try oldSave(e) { o in editCompany(&o, at: 0) { $0["cash"] = .number(7_000) } }
        XCTAssertEqual(loaded.cash, own + 7_000, accuracy: 0.01)
        XCTAssertEqual(loaded.company(id)?.cash ?? -1, loaded.cash, accuracy: 0.01)
        let again = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(loaded))
        XCTAssertEqual(again.cash, loaded.cash, accuracy: 0.01, "a save that already has one account is not folded twice")
    }

    func testAnOldHoldingCompanyDisappearsAndItsStakesComeBackToYou() throws {
        var e = try ChainsTests.engine("UK")
        let id = ChainsTests.start(&e, "cafe")
        let own = e.state.cash
        let quote = e.state.rest["fundPx"]?["idx"] ?? .null
        let unit = quote.isNull ? 100 : quote.double
        let loaded = try oldSave(e) { o in
            var cos = o["cos"]?.array ?? []
            var h = cos[0].object
            h["id"] = 9_001; h["type"] = "hold"; h["name"] = "Old Holding"; h["cash"] = 50_000
            h["fm"] = .object(["idxU": 10, "fx": .object([:]), "rs": .array([])])
            cos.append(.object(h))
            o["cos"] = .array(cos)
            editCompany(&o, at: 0) {
                $0["cash"] = 0
                $0["hold"] = 9_001
                $0["own"] = 70
                $0["holders"] = .array([.object(["name": "Old Holding", "pct": 30, "hid": 9_001])])
            }
            var l: [String: JSONValue] = ["id": 777, "kind": "biz", "name": "Old loan", "bal": 1_000, "co": 9_001]
            l["amt0"] = 1_000
            o["loans"] = .array((o["loans"]?.array ?? []) + [.object(l)])
        }
        XCTAssertNil(loaded.company(9_001), "no holding companies in the game")
        XCTAssertFalse(loaded.companies.contains { $0.type == "hold" })
        let co = try XCTUnwrap(loaded.company(id))
        XCTAssertEqual(co.ownership, 100, accuracy: 0.001, "the stake held by the holding is yours again")
        XCTAssertTrue(co.value("holders").array.isEmpty)
        XCTAssertTrue(co.value("hold").isNull)
        XCTAssertEqual(loaded.loans.first { $0.id == 777 }?.companyID, 0, "its loans are yours")
        XCTAssertEqual(loaded.cash, own + 50_000 + 10 * unit, accuracy: 0.01, "its cash and its fund units are paid into your account")
    }

    func testAnOldFinanceManagerInTheMainOfficeIsLetGo() throws {
        let e = try ChainsTests.engine("UK")
        let loaded = try oldSave(e) { o in
            o["office"] = .object(["tier": "home", "since": 0, "staff": .array([
                .object(["id": 5_001, "role": "fin", "name": "A", "wage": 100]),
                .object(["id": 5_002, "role": "strat", "name": "B", "wage": 100])
            ])])
        }
        let roles = (loaded.rest["office"]?["staff"].array ?? []).map { $0["role"].string }
        XCTAssertEqual(roles, ["strat"])
    }
}
