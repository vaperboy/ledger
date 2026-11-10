import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

final class CustomersCompetitionTests: XCTestCase {
    func engineWithCafe(weeks: Int) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 777)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 80_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: "cafe", cityID: s.player.cityID, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6 + 3_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        for _ in 0..<(weeks * 7) { e.nextDay() }
        return (e, id)
    }

    func testKeyAccountsBuyAndLeave() throws {
        var (e, id) = try engineWithCafe(weeks: 8)
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].set("accts", .array([.object(["id": 1, "name": "Acme Catering", "f": 0.2, "rel": 20, "w0": .number(Double(s.week)), "disc": 10])]))
            s.companies[i].reputation = 70
        }
        let before = e.state.company(id)?.books.total["rev"] ?? 0
        for _ in 0..<(8 * 7) { e.nextDay() }
        let co = try XCTUnwrap(e.state.company(id))
        let info = e.keyAccountInfo(co)
        XCTAssertTrue(info.allowed)
        XCTAssertGreaterThan(info.limit, 1)
        XCTAssertGreaterThan((co.books.total["rev"] ?? 0), before)
        if let a = info.accounts.first { XCTAssertGreaterThan(a.totalUnits, 0, "the account bought something") }
        XCTAssertEqual(e.meetAccount(companyID: id, accountID: 1) == .ok || e.meetAccount(companyID: id, accountID: 1) == .wait || e.keyAccountInfo(co).accounts.isEmpty, true)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testLawsuitAndCyberAttackDecisions() throws {
        var (e, id) = try engineWithCafe(weeks: 12)
        e.update { s, data, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].managerID = nil
            Lawsuits.begin(&s, companyIndex: i, weeklyRevenue: 20_000, data: data)
            Cyber.hit(&s, companyID: id, kind: "ransom", data: data)
            Cyber.hit(&s, companyID: id, kind: "leak", data: data)
            Cyber.hit(&s, companyID: id, kind: "fraud", data: data)
        }
        let open = e.openDecisions.filter { $0.companyID == id }
        let suit = try XCTUnwrap(open.first { $0.actionID == "sue16" })
        let ransom = try XCTUnwrap(open.first { $0.actionID == "cy56r" })
        let leak = try XCTUnwrap(open.first { $0.actionID == "cy56l" })
        XCTAssertTrue(e.answer(messageID: suit.id, option: 0))
        XCTAssertTrue(e.answer(messageID: ransom.id, option: 2))
        XCTAssertTrue(e.answer(messageID: leak.id, option: 1))
        for _ in 0..<(30 * 7) { e.nextDay() }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        XCTAssertTrue(e.cyberInfo(try XCTUnwrap(e.state.company(id))).status.log.count >= 3)
        e.setCyberLevel(companyID: id, level: 2)
        XCTAssertEqual(e.cyberInfo(try XCTUnwrap(e.state.company(id))).status.level, 2)
    }
}
