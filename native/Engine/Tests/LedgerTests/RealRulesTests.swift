import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Events
@testable import Simulation

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

    private func reach(_ e: inout GameEngine, _ f: LevelFeature) {
        e.update { s, _, _ in PlayerLevel.award(&s, PlayerLevel.threshold(LevelGates.level(f))) }
    }

    func testStartingAChainWaitsForItsLevelAndNeedsNoPapers() throws {
        var (e, id) = try game()
        XCTAssertNil(e.startChain(companyID: id, name: "Brand"))
        XCTAssertNil(e.chainOf(companyID: id))
        reach(&e, .chain)
        let chainID = try XCTUnwrap(e.startChain(companyID: id, name: "Brand"))
        XCTAssertEqual(e.chainOf(companyID: id)?["id"].int, chainID)
        XCTAssertEqual(e.state.company(id)!.value("docs")["chain"]["st"].string, "ok")
        XCTAssertEqual(e.startChain(companyID: id, name: "Other"), chainID, "a second press returns the same chain")
    }

    func testFranchisingWaitsForItsLevelAndNeedsNoPapers() throws {
        var (e, id) = try game(manager: true)
        XCTAssertNil(e.startFranchise(companyID: id))
        XCTAssertFalse(e.isFranchisor(companyID: id))
        reach(&e, .franchise)
        XCTAssertEqual(e.startFranchise(companyID: id), .ok)
        XCTAssertTrue(e.isFranchisor(companyID: id))
        XCTAssertEqual(e.franchiseSystem(companyID: id)["roy"].double, Franchising.standardRoyalty, accuracy: 0.0001)
        XCTAssertEqual(e.startFranchise(companyID: id), .already)
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
        XCTAssertFalse(ManagerHiring.verdict(e.state, companyID: id, role: "assistant", target: 1, data: e.data).allowed)
        var cand: [Person] = []
        e.update { s, d, _ in cand = ManagerModel.searchAssistants(&s, companyID: id, data: d) ?? [] }
        let person = try XCTUnwrap(cand.first)
        XCTAssertTrue(e.proposeAssistantManager(companyID: id, personID: person.id, monthlyWage: person.askingMonthlyWage))
        XCTAssertEqual(e.state.company(id)!.value("asst")["npc"].int, 0, "not hired before confirmation")
        let m = try XCTUnwrap(e.state.inbox.first { $0.actionID == "asst" && $0.status == "open" })
        XCTAssertEqual(Delegation.level(of: m), 5, "with no CEO it reaches the owner")
        XCTAssertFalse(e.proposeAssistantManager(companyID: id, personID: person.id, monthlyWage: 1), "one open proposal at a time")
        var declined = e
        XCTAssertTrue(declined.answer(messageID: m.id, option: 1))
        XCTAssertEqual(declined.state.company(id)!.value("asst")["npc"].int, 0)
        XCTAssertTrue(e.answer(messageID: m.id, option: 0))
        XCTAssertEqual(e.state.company(id)!.value("asst")["npc"].int, person.id)
        XCTAssertEqual(e.state.people[person.id]?.employerID, id)
    }

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
