import XCTest
import GameCore
import Finance
import Businesses
import Employees
import Businesses
@testable import Events
@testable import Simulation

/// The owner's talks by position, the strategic direction, and replacing the CEO (a vote by shares with co-owners).
final class OwnerMeetingsTests: XCTestCase {
    private func mood(_ e: GameEngine, _ id: Int) -> Double { let v = e.state.company(id)!.value("mood"); return v.isNull ? 60 : v.double }
    private func setup(seed: Int, holders: Bool = false) throws -> (GameEngine, Int, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 80_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 6_000_000) else { throw XCTSkip("start") }
        e.update { s, d, _ in _ = CompanySetup.quickSetup(&s, companyID: id, data: d) }
        let cands = try XCTUnwrap(e.searchManagers(companyID: id))
        XCTAssertEqual(e.hireManager(personID: cands[0].id, companyID: id, monthlyWage: cands[0].askingMonthlyWage * 1.3), .ok)
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].monthlyHistory = (0..<6).map { MonthRecord(monthIndex: $0, revenue: 40_000, profit: $0 < 3 ? 6_000 : -4_000, cash: 10_000) }
        }
        if holders {
            e.update { s, _, _ in
                guard let i = s.companyIndex(id) else { return }
                let total = CapTable.table(s.companies[i]).total
                _ = CapTable.issue(&s, i, newShares: CapTable.sharesForPercent(35, total: total), to: "Ann Partner", paid: 1, extra: ["k27": "growth", "sat": 60])
                _ = CapTable.issue(&s, i, newShares: CapTable.sharesForPercent(30, total: CapTable.table(s.companies[i]).total), to: "Bo Capital", paid: 1, extra: ["k27": "div", "sat": 60])
            }
        }
        return (e, id, cands[0].id)
    }

    func testTopicsDifferByPositionAndEveryTopicHasADialogue() throws {
        let (e, id, mgr) = try setup(seed: 41)
        let who = e.ownerCounterparts(companyID: id)
        XCTAssertEqual(who.first?.id, mgr)
        XCTAssertEqual(who.first?.position, "ceo")
        let ceoTopics = e.ownerTopics(companyID: id, personID: mgr).map { $0.id }
        XCTAssertTrue(ceoTopics.contains("results") && ceoTopics.contains("advice") && ceoTopics.contains("expect"))
        for t in ceoTopics {
            let sc = try XCTUnwrap(e.ownerScene(companyID: id, personID: mgr, topic: t), t)
            XCTAssertFalse(sc.lines.isEmpty)
            XCTAssertTrue((2...3).contains(sc.choices.count), t)
        }
        for pos in ["fin", "sales", "hr", "ops", "mkt"] { XCTAssertNotNil(OwnerMeetings.topicTable[pos]) }
        XCTAssertNotEqual(OwnerMeetings.topicTable["fin"]!.map { $0.0 }, ceoTopics)
    }

    func testResultsTalkMovesMoodAndHasACooldown() throws {
        var (e, id, mgr) = try setup(seed: 42)
        let m0 = mood(e, id)
        let out = try XCTUnwrap(e.ownerChoose(companyID: id, personID: mgr, topic: "results", choice: "thanks"))
        XCTAssertEqual(out.tone, "good")
        XCTAssertGreaterThan(mood(e, id), m0)
        XCTAssertGreaterThan(e.ownerTopics(companyID: id, personID: mgr).first { $0.id == "results" }!.waitWeeks, 0)
        let again = try XCTUnwrap(e.ownerChoose(companyID: id, personID: mgr, topic: "results", choice: "thanks"))
        XCTAssertTrue(again.text.contains("recently"))
        XCTAssertNil(e.ownerChoose(companyID: id, personID: mgr, topic: "results", choice: "nonsense"))
    }

    func testStrategicDirectiveIsSavedAndBiasesProposals() throws {
        var (e, id, mgr) = try setup(seed: 43)
        XCTAssertNil(e.companyDirective(companyID: id))
        _ = e.ownerChoose(companyID: id, personID: mgr, topic: "advice", choice: "lean")
        XCTAssertEqual(e.companyDirective(companyID: id), "lean")
        XCTAssertGreaterThan(OwnerMeetings.bias(directive: "lean", kind: "cut"), 0)
        XCTAssertLessThan(OwnerMeetings.bias(directive: "lean", kind: "hire"), 0)
        XCTAssertEqual(OwnerMeetings.bias(directive: "growth", kind: "quality"), 0)
    }

    func testFinalWarningCanOnlyEverCostTheManagerTheirMood() throws {
        var (e, id, mgr) = try setup(seed: 44)
        let m0 = mood(e, id)
        _ = try XCTUnwrap(e.ownerChoose(companyID: id, personID: mgr, topic: "challenge", choice: "final"))
        XCTAssertLessThan(mood(e, id), m0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testSoleOwnerBoardIsAdvisoryAndEveryoneSpeaks() throws {
        let (e, id, _) = try setup(seed: 45)
        XCTAssertTrue(e.boardIsAdvisory(companyID: id))
        XCTAssertFalse(e.boardRound(companyID: id).isEmpty)
        let v = e.advisoryVote(kind: "sell", companyID: id)
        XCTAssertFalse(v.active)
        XCTAssertTrue(v.passes, "the sole owner decides alone")
        XCTAssertFalse(v.advice.isEmpty)
        XCTAssertFalse(e.ceoVote(companyID: id).active)
    }

    func testSoleOwnerReplacesTheCEOAtOnce() throws {
        var (e, id, _) = try setup(seed: 46)
        XCTAssertEqual(e.proposeCEOChange(companyID: id), .dismissed)
        XCTAssertNil(e.state.company(id)?.managerID)
        XCTAssertEqual(e.proposeCEOChange(companyID: id), .refused("There is nobody to replace."))
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testCoOwnersVoteByShareAndAFailedVoteBlocksTheProposal() throws {
        var (e, id, _) = try setup(seed: 47, holders: true)
        // a profitable company: the co-owners back the CEO, you hold 45% so you cannot decide alone
        e.update { s, _, _ in
            if let i = s.companyIndex(id) { s.companies[i].monthlyHistory = (0..<6).map { MonthRecord(monthIndex: $0, revenue: 50_000, profit: 9_000, cash: 10_000) } }
        }
        // the co-owners' views are mostly settled by the results; a rare change of heart is a hash of name and week, so look for an ordinary week
        var calm = 0, v = e.ceoVote(companyID: id)
        for w in 20..<60 { e.update { s, _, _ in s.week = w }; v = e.ceoVote(companyID: id); if !v.passes { calm = w; break } }
        XCTAssertGreaterThan(calm, 0)
        XCTAssertTrue(v.active)
        XCTAssertEqual(v.owners.count, 3)
        XCTAssertFalse(v.passes)
        XCTAssertTrue(v.owners.filter { !$0.isYou }.allSatisfy { !$0.reason.isEmpty })
        let mood0 = mood(e, id)
        guard case .voteFailed = e.proposeCEOChange(companyID: id) else { return XCTFail("the vote should fail") }
        XCTAssertNotNil(e.state.company(id)?.managerID)
        XCTAssertLessThan(mood(e, id), mood0)
        guard case .blocked = e.proposeCEOChange(companyID: id) else { return XCTFail("blocked for a while") }
    }

    func testCoOwnersCarryTheVoteWhenTheCompanyLosesMoney() throws {
        var (e, id, _) = try setup(seed: 48, holders: true)
        e.update { s, _, _ in
            if let i = s.companyIndex(id) { s.companies[i].monthlyHistory = (0..<6).map { MonthRecord(monthIndex: $0, revenue: 30_000, profit: -8_000, cash: 10_000) } }
        }
        let v = e.ceoVote(companyID: id)
        XCTAssertTrue(v.passes, "yes: \(v.percentYes)")
        XCTAssertEqual(e.proposeCEOChange(companyID: id), .dismissed)
        XCTAssertNil(e.state.company(id)?.managerID)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testAnUnhappyHolderCanDemandANewManagerAndTheVoteDecides() throws {
        var (e, id, mgr0) = try setup(seed: 49, holders: true)
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].monthlyHistory = (0..<6).map { MonthRecord(monthIndex: $0, revenue: 30_000, profit: -8_000, cash: 10_000) }
            var h = s.companies[i].value("holders").array
            for k in h.indices { h[k]["sat"] = 10 }
            s.companies[i].status = .open
            s.companies[i].set("holders", .array(h))
        }
        var found: Message?
        for w in 30..<80 where found == nil {
            e.update { s, d, c in
                s.week = w
                if let i = s.companyIndex(id) { s.companies[i].set("dm27", 0); Shareholders.maybeDemand(&s, i, data: d, context: c) }
            }
            found = e.state.inbox.last { $0.actionID == Shareholders.action && $0.value("data")["kind"].string == "mgr" }
        }
        let m = try XCTUnwrap(found, "a manager demand should come up")
        XCTAssertEqual(m.title.contains("new manager"), true)
        XCTAssertTrue(e.answer(messageID: m.id, option: 0))
        XCTAssertNotEqual(e.state.company(id)?.managerID, mgr0, "the co-owners carried the vote: \(e.ceoVote(companyID: id).percentYes)")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    /// The weekly check remembers the manager in post (`mgr12`) and raises "the manager has left" when it finds the post empty. A change the owner
    /// made on purpose must clear that memory, or the next week brings an emergency about something the owner just did.
    func testReplacingTheCeoClearsTheManagerHasLeftMemory() throws {
        var (e, id, mgr) = try setup(seed: 61)
        e.update { s, _, _ in s.companies[s.companyIndex(id)!].set("mgr12", .number(Double(mgr))) }
        XCTAssertEqual(e.proposeCEOChange(companyID: id), .dismissed)
        XCTAssertTrue(e.state.company(id)!.value("mgr12").isNull)
    }
}
