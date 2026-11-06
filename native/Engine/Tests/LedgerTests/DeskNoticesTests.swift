import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

/// Notices carry a severity and an audience; routine matters go to the desk that answers for them and only serious ones reach the owner.
final class DeskNoticesTests: XCTestCase {
    private func game() throws -> (GameEngine, Int, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7)
        e.update { s, _, _ in Ledger.move(&s, .me, 500_000_000, why: "Test funds") }
        guard case .success(let a) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 50_000_000),
              case .success(let b) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 50_000_000) else { throw XCTSkip("no cafes") }
        return (e, a, b)
    }

    func testSeverityIsStoredOrDerived() throws {
        var s = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7).state
        let id = s.addMessage(from: "X", title: "t", body: "b", tone: "bad", sev: 3, aud: "finance")
        XCTAssertEqual(s.inbox.first { $0.id == id }?.severity, 3)
        XCTAssertFalse(s.inbox[0].isOwnerAddressed)
        s.addMessage(from: "X", title: "t", body: "b", tone: "bad")
        XCTAssertEqual(s.inbox[0].severity, 2)
        XCTAssertTrue(s.inbox[0].isOwnerAddressed)
        s.addMessage(kind: "ask", from: "X", title: "t", body: "b", status: "open", options: [JSONValue.option("Ok")])
        XCTAssertEqual(s.inbox[0].severity, 3)
        s.addMessage(from: "X", title: "t", body: "b")
        XCTAssertEqual(s.inbox[0].severity, 1)
    }

    func testPayrollShortGoesToTheAccountantOncePerWeek() throws {
        var (e, a, b) = try game()
        e.update { s, d, _ in
            for id in [a, b] { CompanySetup.chooseAccountant(&s, companyID: id, accountantID: nil, data: d) }
        }
        e.update { s, d, c in
            for id in [a, b] { Payday.reportShort(&s, s.company(id)!, due: 5000, short: 1000, serious: false, data: d, context: c) }
        }
        let msgs = e.state.inbox.filter { $0.actionID == "pay29s" }
        XCTAssertEqual(msgs.count, 1, "one notice a week for all companies")
        XCTAssertEqual(msgs[0].status, "done")
        XCTAssertFalse(msgs[0].handledBy.isEmpty, "the accountant is shown as handling it")
        XCTAssertFalse(msgs[0].isOwnerAddressed)
        XCTAssertTrue(e.openDecisions.filter { $0.actionID.hasPrefix("pay29") }.isEmpty)
    }

    func testPayrollShortReachesTheOwnerWhenSeriousOrUnattended() throws {
        var (e, a, _) = try game()
        e.update { s, _, _ in if let i = s.companyIndex(a) { s.companies[i].raw["acc"] = .null; s.companies[i].staff.removeAll { $0.role == "acct" } } }
        e.update { s, d, c in Payday.reportShort(&s, s.company(a)!, due: 5000, short: 1000, serious: false, data: d, context: c) }
        var m = try XCTUnwrap(e.state.inbox.first { $0.actionID == "pay29s" })
        XCTAssertEqual(m.status, "open", "nobody answers for the desk")
        XCTAssertTrue(m.isOwnerAddressed)
        XCTAssertEqual(m.severity, 3)
        let before = e.state.company(a)!.cash
        XCTAssertTrue(e.answer(messageID: m.id, option: 0))
        m = try XCTUnwrap(e.state.inbox.first { $0.id == m.id })
        XCTAssertEqual(m.status, "done")
        XCTAssertEqual(e.state.company(a)!.cash, before, "acknowledging moves no money")
    }

    func testDeskResolverFindsAnAccountant() throws {
        var (e, a, _) = try game()
        e.update { s, d, _ in CompanySetup.chooseAccountant(&s, companyID: a, accountantID: nil, data: d) }
        let co = e.state.company(a)!
        XCTAssertNotNil(Delegation.desk("finance", in: co, state: e.state, data: e.data))
        XCTAssertNil(Delegation.desk("owner", in: co, state: e.state, data: e.data))
    }
}
