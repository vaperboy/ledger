import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

final class ConnectivityLinksTests: XCTestCase {
    private func game() throws -> GameEngine {
        try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5, story: .fresh, tradeID: "cafe", companyName: "Test")
    }

    func testCompanylessSenderGetsItsAppAndACompanyMessageDoesNot() throws {
        var e = try game()
        var ids: [Int] = []
        let cid: Int = e.state.companies[0].id
        e.update { s, _, _ in
            ids.append(s.addMessage(from: "Your insurer", title: "a", body: ""))
            ids.append(s.addMessage(from: "Bank", title: "b", body: ""))
            ids.append(s.addMessage(from: "The tax office", title: "c", body: ""))
            ids.append(s.addMessage(from: "Weather service", title: "d", body: ""))
            ids.append(s.addMessage(from: "Bank", title: "e", body: "", companyID: cid))
            ids.append(s.addMessage(from: "A stranger", title: "f", body: ""))
            ids.append(s.addMessage(from: "A stranger", title: "g", body: "", app: "news"))
        }
        let links: [String] = ids.map { id in e.state.inbox.first { $0.id == id }!.appLink }
        XCTAssertEqual(links, ["atlas", "bank", "accounting", "news", "", "", "news"])
    }

    func testAppLinkSurvivesASaveAndOldMessagesHaveNone() throws {
        var e = try game()
        var id = 0
        e.update { s, _, _ in id = s.addMessage(from: "Your bank", title: "x", body: "") }
        let data: Data = try JSONEncoder().encode(e.state)
        let back: GameState = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(back.inbox.first { $0.id == id }?.appLink, "bank")
        let old: GameState = try Golden.state("save_cafe_week15")
        XCTAssertTrue(old.inbox.allSatisfy { $0.appLink.isEmpty })
        XCTAssertTrue(old.inbox.allSatisfy { $0.raw["ap"] == nil }, "an old save is written back without the new key")
    }

    func testEveryCareerGoalAndDailyGoalHasAKnownLink() throws {
        let e = try game()
        let known: Set<String> = ["sales", "hire", "inbox", "marketing", "money", "company", "management", "customers", "achievements", "newCompany"]
        let goals: [Career.Goal] = e.careerGoals
        XCTAssertFalse(goals.isEmpty)
        for g in goals { XCTAssertTrue(known.contains(g.link), "\(g.id) links to \(g.link)") }
        for id in ["start", "weeks", "hire", "cmp", "grow"] {
            let d = PlayerGoals.DailyGoal(id: id, title: "", progress: "", done: false, streak: 0)
            XCTAssertTrue(known.contains(d.link), "daily goal \(id) links to \(d.link)")
        }
    }
}
