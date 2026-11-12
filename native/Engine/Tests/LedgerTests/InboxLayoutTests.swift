import XCTest
import GameCore
import Businesses
import Simulation

final class InboxLayoutTests: XCTestCase {
    private func ids(_ sections: [InboxSection], _ id: String) -> [String] {
        sections.first { $0.id == id }?.messages.map { $0.title } ?? []
    }

    func testEveryNoticeLandsInExactlyOneGroup() throws {
        var e = try ChainsTests.engine()
        e.update { s, _, _ in
            s.week = 10
            let opts = [JSONValue.option("A", "", effects: [:]), JSONValue.option("B", "", effects: [:])]
            _ = s.addMessage(kind: "decision", from: "Co", title: "Open question", body: "b", status: "open", options: opts, expiresWeek: 12)
            _ = s.addMessage(from: "Co", title: "News this week", body: "b")
            s.week = 12
            _ = s.addMessage(from: "Co", title: "Fresh news", body: "b")
            let handled = s.addMessage(kind: "decision", from: "Co", title: "Manager answered", body: "b", options: opts)
            if let k = s.inbox.firstIndex(where: { $0.id == handled }) { s.inbox[k].set("mgrName", "Mia") }
            _ = s.addMessage(from: "Co", title: "Finance desk note", body: "b", aud: "finance")
        }
        let list: [Message] = e.state.inbox
        let sections: [InboxSection] = InboxLayout.sections(list, week: 12)
        XCTAssertEqual(sections.map { $0.messages.count }.reduce(0, +), list.count)
        XCTAssertEqual(Set(sections.flatMap { $0.messages.map { $0.id } }).count, list.count)
        XCTAssertTrue(ids(sections, "needs").contains("Open question"))
        XCTAssertTrue(ids(sections, "week").contains("Fresh news"))
        XCTAssertTrue(ids(sections, "earlier").contains("News this week"))
        XCTAssertFalse(ids(sections, "needs").contains("Manager answered"))
        XCTAssertTrue(ids(sections, "handled").contains("Manager answered"))
        XCTAssertTrue(ids(sections, "handled").contains("Finance desk note"))
        XCTAssertEqual(sections.first?.id, "needs")
        XCTAssertEqual(InboxLayout.sections(list, week: 12, infoFirst: true).first?.id, "week")
    }

    func testTheMostUrgentQuestionComesFirst() throws {
        var e = try ChainsTests.engine()
        e.update { s, _, _ in
            let opts = [JSONValue.option("A", "", effects: [:]), JSONValue.option("B", "", effects: [:])]
            _ = s.addMessage(kind: "decision", from: "Co", title: "Later", body: "b", status: "open", options: opts, expiresWeek: s.week + 3)
            _ = s.addMessage(kind: "decision", from: "Co", title: "Sooner", body: "b", status: "open", options: opts, expiresWeek: s.week + 1)
        }
        let sections: [InboxSection] = InboxLayout.sections(e.state.inbox, week: e.state.week)
        let needs: [String] = ids(sections, "needs")
        let sooner: Int = try XCTUnwrap(needs.firstIndex(of: "Sooner"))
        let later: Int = try XCTUnwrap(needs.firstIndex(of: "Later"))
        XCTAssertLessThan(sooner, later)
    }

    func testActionsOpenTheRightPlace() throws {
        var e = try ChainsTests.engine()
        let id = ChainsTests.start(&e, "cafe")
        var staff = 0, prop = 0, plain = 0, bank = 0, accounting = 0, none = 0, club = 0
        e.update { s, _, _ in
            staff = s.addMessage(from: "Co", title: "Staff", body: "b", companyID: id, action: "staffx")
            prop = s.addMessage(from: "Co", title: "Premises", body: "b", companyID: id, action: "prop")
            club = s.addMessage(from: "Co", title: "Club", body: "b", companyID: id, action: "club24")
            plain = s.addMessage(from: "Co", title: "Plain", body: "b", companyID: id)
            bank = s.addMessage(from: "Your bank", title: "Bank", body: "b")
            accounting = s.addMessage(from: "The tax office", title: "Tax", body: "b")
            none = s.addMessage(from: "Somebody", title: "None", body: "b")
        }
        func target(_ mid: Int) -> InboxTarget? {
            guard let m = e.state.inbox.first(where: { $0.id == mid }) else { return nil }
            return InboxLayout.target(m, in: e.state)
        }
        XCTAssertEqual(target(staff), .company(id, "staff"))
        XCTAssertEqual(target(prop), .company(id, "properties"))
        XCTAssertEqual(target(club), .company(id, "club"))
        XCTAssertEqual(target(plain), .company(id, ""))
        XCTAssertEqual(target(bank), .app("bank"))
        XCTAssertEqual(target(accounting), .app("bank"))
        XCTAssertNil(target(none))
    }

    func testAMessageAboutAGoneCompanyFallsBackToItsApp() throws {
        var e = try ChainsTests.engine()
        var mid = 0
        e.update { s, _, _ in mid = s.addMessage(from: "Your insurer", title: "Cover", body: "b", companyID: 987_654, app: "atlas") }
        let m = try XCTUnwrap(e.state.inbox.first { $0.id == mid })
        XCTAssertEqual(InboxLayout.target(m, in: e.state), .app("atlas"))
    }

    func testTrophyNoticesOpenTheProfile() throws {
        var e = try ChainsTests.engine()
        var mid = 0
        e.update { s, _, _ in mid = s.addMessage(from: "Trophy wall", title: "Trophy", body: "b", route: .inbox) }
        let m = try XCTUnwrap(e.state.inbox.first { $0.id == mid })
        XCTAssertEqual(InboxLayout.target(m, in: e.state), .app("profile"))
    }
}
