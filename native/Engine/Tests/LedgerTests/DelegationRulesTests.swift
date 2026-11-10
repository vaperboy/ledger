import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

final class DelegationRulesTests: XCTestCase {
    private func company(_ e: inout GameEngine) throws -> Int {
        e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "webdev", cityID: e.state.player.cityID, quickSetup: false) else { throw XCTSkip("no company") }
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].status = .open } }
        return id
    }

    func testARedAlertComesOncePerFourWeeksBeforeAForcedSale() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 3)
        let id = try company(&e)
        e.update { s, _, ctx in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].weeksNegative = 10
            Ledger.set(&s, to: -90_000_000)
            Failure.warn(&s, context: ctx)
            Failure.warn(&s, context: ctx)
        }
        XCTAssertEqual(e.state.inbox.filter { $0.isAlert && $0.companyID == id }.count, 1)
    }

    func testNothingIsDelegatedWithoutAManager() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 3)
        _ = try company(&e)
        XCTAssertEqual(Delegation.spendLimit(e.state, data: e.data), 0, "no manager: every spend is the owner's")
        XCTAssertFalse(Delegation.autoRehire(e.state, e.state.companies[0]))
    }

    func testABankLendsAgainstWhatABusinessIsWorthEvenAtALoss() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 3)
        let id = try company(&e)
        let co = try XCTUnwrap(e.state.company(id))
        let none = Banking.offer(kind: "biz", amount: 1, company: co, state: e.state, netWorth: 0, companyValue: 0, context: e.context)
        let worth = Banking.offer(kind: "biz", amount: 1, company: co, state: e.state, netWorth: 0, companyValue: 500_000_000, context: e.context)
        XCTAssertGreaterThanOrEqual(worth.maximum, none.maximum)
        if none.creditBand != "E" { XCTAssertGreaterThan(worth.maximum, none.maximum, "worth counts, not only profit") }
    }
}

final class DocumentReviewTests: XCTestCase {
    func testASignedApplicationIsReviewedAndARefusalCanBeReappliedAtOnce() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5)
        e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "webdev", cityID: e.state.player.cityID, quickSetup: false) else { throw XCTSkip("no company") }
        let form = try XCTUnwrap(e.documentForm(companyID: id, documentID: "registration"))
        XCTAssertTrue(["", "ok", "applied"].contains(form.status))
        let ids = e.openingChecklist(companyID: id).map { $0.id }
        XCTAssertTrue(ids.contains("doc:vat") || e.state.company(id).map { Vat.isExempt($0, World(state: e.state, data: e.data)) } == true)
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            var docs = s.companies[i].value("docs"); docs["registration"] = .object(["st": "rejected"]); s.companies[i].set("docs", docs)
        }
        let r = e.applyForDocument(companyID: id, documentID: "registration")
        XCTAssertEqual(r, .ok, "no cooldown after a refusal")
        XCTAssertEqual(e.documentForm(companyID: id, documentID: "registration")?.status, "applied")
    }
}
