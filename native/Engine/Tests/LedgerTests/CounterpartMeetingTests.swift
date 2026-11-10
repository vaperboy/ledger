import XCTest
import GameCore
import Finance
import Businesses
import Simulation

final class CounterpartMeetingTests: XCTestCase {
    private func game(_ country: String = "UK", seed: Int = 7) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: country, playerName: "T", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 500_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID) else { throw XCTSkip("no cafe") }
        return (e, id)
    }

    private func setWeek(_ e: inout GameEngine, _ delta: Int) { e.update { s, _, _ in s.week += delta } }

    func testSupplierLunch() throws {
        var (e, _) = try game()
        let vid = "V-UK-3"
        let cost = e.homeCurrency.scaledPrice(5000)
        let cash0 = e.state.cash
        XCTAssertEqual(e.lunchWithSupplier(vendorID: vid), .ok)
        XCTAssertEqual(cash0 - e.state.cash, jsRound(cost), accuracy: 0.5)
        let rel = e.state.rest["vr"]![vid]["r"].double
        XCTAssertEqual(rel, 7, "seed 7, week 0: the first draw of 5...9")
        XCTAssertGreaterThanOrEqual(rel, 5); XCTAssertLessThanOrEqual(rel, 9)
        XCTAssertEqual(e.state.rest["vr"]![vid]["meet"].int, e.state.week)
        let cash1 = e.state.cash
        XCTAssertEqual(e.lunchWithSupplier(vendorID: vid), .wait)
        XCTAssertEqual(e.state.cash, cash1)
        setWeek(&e, 3); XCTAssertEqual(e.lunchWithSupplier(vendorID: vid), .wait)
        setWeek(&e, 1); XCTAssertEqual(e.lunchWithSupplier(vendorID: vid), .ok)
        XCTAssertEqual(e.lunchWithSupplier(vendorID: "nope"), .unknown)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testSupplierLunchNeedsCash() throws {
        var (e, _) = try game()
        e.update { s, _, _ in Ledger.move(&s, .me, -(s.cash - 100), why: "Spend") }
        let cash = e.state.cash
        XCTAssertEqual(e.lunchWithSupplier(vendorID: "V-UK-3"), .cash)
        XCTAssertEqual(e.state.cash, cash)
        XCTAssertNil(e.state.rest["vr"]?["V-UK-3"]["meet"].isNull == false ? 1 : nil)
    }

    func testAccountDinner() throws {
        var (e, id) = try game()
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].set("accts", .array([.object(["id": 1, "name": "Acme Catering", "f": 0.2, "rel": 20, "w0": .number(Double(s.week)), "disc": 10])]))
        }
        let cost = e.homeCurrency.scaledPrice(6000)
        let cash0 = e.state.cash
        let wk = e.state.week
        XCTAssertEqual(e.meetAccount(companyID: id, accountID: 1), .ok)
        XCTAssertEqual(cash0 - e.state.cash, jsRound(cost), accuracy: 0.5)
        var h = HashedRandom("\(e.state.seed):meet:\(wk):1")
        let expected = min(100, 20 + (4 + (h.next() * 4).rounded(.down)) * (1 - pow(20.0 / 100, 1.6)))
        let a = try XCTUnwrap(e.keyAccountInfo(try XCTUnwrap(e.state.company(id))).accounts.first)
        XCTAssertEqual(a.relationship, expected, accuracy: 1e-9)
        XCTAssertEqual(a.lastMeeting, wk)
        XCTAssertEqual(e.meetAccount(companyID: id, accountID: 1), .wait)
        setWeek(&e, 3); XCTAssertEqual(e.meetAccount(companyID: id, accountID: 1), .wait)
        setWeek(&e, 1); XCTAssertEqual(e.meetAccount(companyID: id, accountID: 1), .ok)
        XCTAssertEqual(e.meetAccount(companyID: id, accountID: 77), .missing)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testAccountDinnerNeedsCash() throws {
        var (e, id) = try game()
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].set("accts", .array([.object(["id": 1, "name": "Acme", "f": 0.2, "rel": 20, "w0": 0, "disc": 10])]))
            Ledger.move(&s, .me, -(s.cash - 100), why: "Spend")
        }
        let cash = e.state.cash
        XCTAssertEqual(e.meetAccount(companyID: id, accountID: 1), .cash)
        XCTAssertEqual(e.state.cash, cash)
    }

    func testNoHandWrittenMeetingCoolDown() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/Businesses")
        var hits: [String] = []
        for name in ["Suppliers.swift", "Rivals.swift", "KeyAccounts.swift", "ManagerPeople.swift", "ManagerMeetings.swift"] {
            guard let text = try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) else { continue }
            for (n, line) in text.components(separatedBy: "\n").enumerated() where line.contains("[\"meet\"]") && (line.contains("< 4") || line.contains(">= 3")) || line.contains("meetW") && (line.contains("< 4") || line.contains(">= 3")) {
                hits.append("\(name):\(n + 1)")
            }
        }
        XCTAssertTrue(hits.isEmpty, "Use CounterpartMeeting.isCoolingDown / meet instead: \(hits)")
    }
}
