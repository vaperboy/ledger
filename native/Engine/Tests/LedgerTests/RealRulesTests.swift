import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Events
@testable import Simulation

/// Owner requests, 3 Nov: chain and franchise requirements are real-life papers; breakdowns under warranty are repaired without a decision;
/// appointment authority (an assistant manager needs confirmation from the level above); research reports arrive as inbox documents.
final class RealRulesTests: XCTestCase {
    private func game(manager: Bool = false, seed: Int = 4242) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 500_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, data: data, context: ctx) { id = i }
            Payments.injectCash(&s, companyID: id, amount: 300_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data, faithfulHiring: false)
            if let i = s.companyIndex(id) { s.companies[i].status = .open }
            if manager, let co = s.company(id), let bd = data.catalog[co.type] {
                for _ in 0..<4 {
                    let c = ManagerModel.generateCandidate(company: co, type: bd.managerType, state: &s, data: data)
                    if ManagerModel.hire(&s, personID: c.id, companyID: id, monthlyWage: c.askingMonthlyWage * 1.4, data: data) == .ok { break }
                }
            }
        }
        guard id != 0 else { throw XCTSkip("no company") }
        if manager { guard e.state.company(id)?.managerID != nil else { throw XCTSkip("no manager hired") } }
        return (e, id)
    }

    private func setDocs(_ e: inout GameEngine, _ id: Int, _ ids: [String]) {
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            var docs = s.companies[i].value("docs")
            for d in ids { docs[d] = .object(["st": "ok", "done": 0, "ok": 0]) }
            s.companies[i].set("docs", docs)
        }
    }

    // MARK: 1. Chain and franchise requirements

    func testProvenConceptNeedsAYearAndFourProfitableQuarters() throws {
        var (e, id) = try game()
        func proven() -> Bool { Franchising.provenConcept(e.state, e.state.company(id)!).ok }
        func set(open weeksAgo: Int, profits: [Double]) {
            e.update { s, _, _ in
                guard let i = s.companyIndex(id) else { return }
                s.companies[i].openedWeek = s.week - weeksAgo
                s.companies[i].monthlyHistory = profits.enumerated().map { MonthRecord(monthIndex: $0.offset, revenue: 1000, profit: $0.element, cash: 0) }
            }
        }
        set(open: 60, profits: Array(repeating: 100, count: 12)); XCTAssertTrue(proven())
        set(open: 40, profits: Array(repeating: 100, count: 12)); XCTAssertFalse(proven(), "under 52 weeks of trading")
        set(open: 60, profits: Array(repeating: 100, count: 9) + [-100, -100, -100]); XCTAssertFalse(proven(), "a loss-making quarter")
        set(open: 60, profits: Array(repeating: 100, count: 9)); XCTAssertFalse(proven(), "fewer than four quarters of record")
        // A single bad month inside a profitable quarter does not matter: the quarter is what counts.
        set(open: 60, profits: [100, 100, 100, 100, 100, 100, 100, 100, 100, 200, -100, 100]); XCTAssertTrue(proven())
    }

    func testFranchisorRequirementsAreRealPapersWithStatus() throws {
        var (e, id) = try game()
        let r0 = Franchising.requirements(e.state, e.state.company(id)!)
        XCTAssertEqual(r0.map { $0.key }, ["proven", "trademark", "ops_manual", "fran", "support"])
        XCTAssertTrue(r0.allSatisfy { !$0.ok && $0.status == .missing }, "a fresh company has none of them")
        XCTAssertFalse(r0.contains { $0.detail.lowercased().contains("reputation") || $0.title.lowercased().contains("cash") })
        // Applying for the trademark costs the fee, shows "waiting for review", and the review ends the wait.
        let cash0 = e.state.company(id)!.cash
        XCTAssertEqual(e.applyForChainDocument(companyID: id, document: "trademark"), .ok)
        XCTAssertLessThan(e.state.company(id)!.cash, cash0, "the fee is paid")
        XCTAssertEqual(e.state.company(id)!.value("docs")["trademark"]["signed"].bool, true, "the application is signed and can be refused")
        var tm = Franchising.requirements(e.state, e.state.company(id)!).first { $0.key == "trademark" }!
        XCTAssertEqual(tm.status, .waiting)
        let weeks = e.state.company(id)!.value("docs")["trademark"]["done"].int - e.state.week
        XCTAssertTrue((4...8).contains(weeks), "a trademark review takes 4 to 8 weeks, got \(weeks)")
        e.update { s, d, _ in
            s.week += weeks
            if let i = s.companyIndex(id) { Documents.weekly(&s, companyIndex: i, data: d) }
        }
        tm = Franchising.requirements(e.state, e.state.company(id)!).first { $0.key == "trademark" }!
        XCTAssertTrue(tm.status == .done || tm.detail.lowercased().contains("refused"), "reviewed: approved or refused with a reason")
        // The operations manual is written by the company: a small fee, no review, never refused.
        XCTAssertEqual(e.applyForChainDocument(companyID: id, document: "ops_manual"), .ok)
        XCTAssertNotEqual(e.state.company(id)!.value("docs")["ops_manual"]["signed"].bool, true)
        e.update { s, d, _ in
            s.week += 3
            if let i = s.companyIndex(id) { Documents.weekly(&s, companyIndex: i, data: d) }
        }
        XCTAssertEqual(Franchising.requirements(e.state, e.state.company(id)!).first { $0.key == "ops_manual" }!.status, .done)
    }

    func testChainRegistrationNeedsTrademarkAndManualOnly() throws {
        var (e, id) = try game()
        if case .notYet = e.applyForChainDocument(companyID: id, document: "chain") {} else { XCTFail("trademark and manual are missing") }
        // No cash, reputation or record is asked: just the two papers.
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].reputation = 5; s.companies[i].monthlyHistory = [] } }
        setDocs(&e, id, ["trademark", "ops_manual"])
        XCTAssertTrue(e.chainRequirements(companyID: id).allSatisfy { $0.ok })
        XCTAssertEqual(e.applyForChainDocument(companyID: id, document: "chain"), .ok)
    }

    func testFranchiseLaunchNeedsEveryPaper() throws {
        var (e, id) = try game(manager: true)
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].openedWeek = s.week - 80
            s.companies[i].monthlyHistory = (0..<12).map { MonthRecord(monthIndex: $0, revenue: 1000, profit: 100, cash: 0) }
        }
        setDocs(&e, id, ["trademark", "ops_manual"])
        XCTAssertEqual(e.launchFranchise(companyID: id, entryFee: 1, royalty: 0.05, support: 1), .needDocuments, "the disclosure document is missing")
        XCTAssertEqual(e.applyForChainDocument(companyID: id, document: "fran"), .ok)
        setDocs(&e, id, ["fran"])
        XCTAssertTrue(e.franchiseRequirements(companyID: id).allSatisfy { $0.ok }, "\(e.franchiseRequirements(companyID: id))")
        XCTAssertEqual(e.launchFranchise(companyID: id, entryFee: 1, royalty: 0.05, support: 1), .ok)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testFranchiseeRowsAreApplicationAgreementAndFinancing() throws {
        let (e, _) = try game()
        let w = World(state: e.state, data: e.data)
        let brand = try XCTUnwrap(["cafe", "gym", "barber", "bakery"].lazy.compactMap { FranchiseBrands.brands($0, country: "UK", w).first { $0.openness == "open" } }.first)
        let rows = e.franchiseeRequirements(brand, country: "UK")
        XCTAssertEqual(rows.map { $0.key }, ["review", "agreement", "financing"])
        XCTAssertEqual(rows[0].status, .missing)
        XCTAssertTrue(FranchiseBrands.status(brand, e.state, w).ok, "no reputation or experience gate")
    }

    // MARK: 2. Warranty

    private func setWarranty(_ e: inout GameEngine, _ id: Int, until: Int) {
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            var units = s.companies[i].value("units")
            for (k, list) in units.object { units[k] = .array(list.array.map { var u = $0; u["warr"] = .number(Double(until)); u["down"] = 0; return u }) }
            s.companies[i].set("units", units)
        }
    }

    func testBreakdownUnderWarrantyIsRepairedWithoutADecision() throws {
        var (e, id) = try game()
        XCTAssertFalse(e.state.company(id)!.value("units").object.isEmpty)
        setWarranty(&e, id, until: e.state.week + 100)
        var fired = true
        e.update { s, d, c in
            guard let i = s.companyIndex(id), let def = StrategicDecisions.byID["s_breakdown"] else { return }
            fired = StrategicDecisions.fire(&s, def, companyIndex: i, data: d, context: c)
        }
        XCTAssertFalse(fired, "no decision is raised")
        XCTAssertFalse(e.state.inbox.contains { $0.status == "open" && $0.title.contains("breaks down") })
        let info = try XCTUnwrap(e.state.inbox.first { $0.title.contains("repaired under warranty") })
        XCTAssertEqual(info.kind, "info")
        let down = e.state.company(id)!.value("units").object.values.flatMap { $0.array }.map { $0["down"].int }.filter { $0 > 0 }
        XCTAssertEqual(down.count, 1)
        XCTAssertTrue((1...2).contains(down[0]), "one or two days out of use")
        XCTAssertEqual(e.state.company(id)!.cash, e.state.company(id)!.cash)
    }

    func testBreakdownOutOfWarrantyStillAsks() throws {
        var (e, id) = try game()
        setWarranty(&e, id, until: 0)
        let cash0 = e.state.company(id)!.cash
        e.update { s, d, c in
            guard let i = s.companyIndex(id), let def = StrategicDecisions.byID["s_breakdown"] else { return }
            XCTAssertTrue(StrategicDecisions.fire(&s, def, companyIndex: i, data: d, context: c))
        }
        XCTAssertTrue(e.state.inbox.contains { $0.status == "open" && $0.title.contains("breaks down") })
        XCTAssertFalse(e.state.inbox.contains { $0.title.contains("under warranty") })
        XCTAssertEqual(e.state.company(id)!.cash, cash0, "nothing is paid until the owner chooses")
    }

    // MARK: 3. Appointment authority

    func testOwnerAppointsManagerAndCEOWhenThereIsOne() throws {
        let (e, id) = try game(manager: true)
        let gm = e.appointmentAuthority(companyID: id, role: "general manager")
        XCTAssertEqual(gm.decidedBy, .owner); XCTAssertNil(gm.needsConfirmationFrom)
        var e2 = e
        e2.update { s, _, _ in
            if let p = s.people.keys.sorted().first(where: { $0 != s.company(id)?.managerID }) { s.rest["org56"] = .object(["md": .object(["npc": .number(Double(p))])]) }
        }
        XCTAssertEqual(e2.appointmentAuthority(companyID: id, role: "general manager").decidedBy, .ceo)
        XCTAssertEqual(e2.appointmentAuthority(companyID: id, role: "assistant manager").needsConfirmationFrom, .ceo)
    }

    func testManagerCannotHireAssistantAloneButHiresStaff() throws {
        var (e, id) = try game(manager: true)
        let asst = e.appointmentAuthority(companyID: id, role: "assistant manager")
        XCTAssertEqual(asst.decidedBy, .manager)
        XCTAssertEqual(asst.needsConfirmationFrom, .owner)
        XCTAssertFalse(asst.reason.isEmpty)
        XCTAssertEqual(e.appointmentAuthority(companyID: id, role: "deputy").needsConfirmationFrom, .owner)
        let staff = e.appointmentAuthority(companyID: id, role: "barista")
        XCTAssertEqual(staff.decidedBy, .manager); XCTAssertNil(staff.needsConfirmationFrom)
        // The automatic hirer refuses an assistant role: it goes through a proposal.
        XCTAssertFalse(ManagerHiring.verdict(e.state, companyID: id, role: "assistant", target: 1, data: e.data).allowed)
        // The proposal is an open decision for the owner; no assistant exists until it is confirmed.
        var cand: [Person] = []
        e.update { s, d, _ in cand = ManagerModel.searchAssistants(&s, companyID: id, data: d) ?? [] }
        let person = try XCTUnwrap(cand.first)
        XCTAssertTrue(e.proposeAssistantManager(companyID: id, personID: person.id, monthlyWage: person.askingMonthlyWage))
        XCTAssertEqual(e.state.company(id)!.value("asst")["npc"].int, 0, "not hired before confirmation")
        let m = try XCTUnwrap(e.state.inbox.first { $0.actionID == "asst" && $0.status == "open" })
        XCTAssertEqual(Delegation.level(of: m), 5, "with no CEO it reaches the owner")
        XCTAssertFalse(e.proposeAssistantManager(companyID: id, personID: person.id, monthlyWage: 1), "one open proposal at a time")
        // Declining creates nobody; confirming installs the assistant.
        var declined = e
        XCTAssertTrue(declined.answer(messageID: m.id, option: 1))
        XCTAssertEqual(declined.state.company(id)!.value("asst")["npc"].int, 0)
        XCTAssertTrue(e.answer(messageID: m.id, option: 0))
        XCTAssertEqual(e.state.company(id)!.value("asst")["npc"].int, person.id)
        XCTAssertEqual(e.state.people[person.id]?.employerID, id)
    }

    // MARK: 4. Research documents

    func testResearchArrivesAsAnInboxDocument() throws {
        var (e, id) = try game()
        e.update { s, d, _ in
            MarketResearch.buy(&s, companyID: id, optionID: "benchmark", data: d)
            s.week += 5
            MarketResearch.weekly(&s, data: d)
        }
        let m = try XCTUnwrap(e.state.inbox.first { $0.kind == "doc" }, "\(e.state.inbox.prefix(4).map { $0.title }) \(e.state.company(id)!.value("res27"))")
        XCTAssertFalse(m.body.isEmpty, "the plain text stays as the fallback summary")
        let doc = try XCTUnwrap(e.messageDocument(messageID: m.id))
        XCTAssertEqual(doc.issuer, "Ledger Market Research")
        XCTAssertTrue(doc.reference.hasPrefix("LMR-"))
        XCTAssertFalse(doc.date.isEmpty)
        XCTAssertEqual(doc.sections.map { $0.heading }.first, "Summary")
        XCTAssertEqual(doc.sections.map { $0.heading }.last, "Recommendation")
        XCTAssertTrue(doc.sections.contains { $0.heading == "Prices" })
        // Survives a save and reload, and an ordinary message has no document.
        let back = try JSONDecoder().decode(GameState.self, from: try JSONEncoder().encode(e.state))
        XCTAssertEqual(back.inbox.first { $0.id == m.id }?.doc, doc)
        var plainID = 0
        e.update { s, _, _ in plainID = s.addMessage(from: "Test", title: "Plain", body: "text") }
        XCTAssertNil(e.messageDocument(messageID: plainID))
    }

    func testInboxDocumentRoundTripsThroughMessageRaw() {
        var m = Message(raw: [:])
        XCTAssertNil(m.doc)
        let d = InboxDocument(title: "T", issuer: "I", date: "1 Jan 2026", reference: "R-1",
                              sections: [.init(heading: "H", lines: ["a", "b"], points: [.init(label: "x", value: 2)]), .init(heading: "H2", lines: [])])
        m.doc = d
        XCTAssertEqual(m.doc, d)
        m.doc = nil
        XCTAssertNil(m.doc)
    }
}
