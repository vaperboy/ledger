import XCTest
import GameCore
import Finance
import Simulation
@testable import Businesses

/// The two paid checks of the main office: a reference check on a head-office candidate (original `hqref`) and a manager review of one company
/// (original `reviewnow`).
final class OfficeChecksTests: XCTestCase {
    func testReferenceCheckShowsTheRealLevelAndIsPaidOnce() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 31)
        var pid = 0
        e.update { s, data, _ in
            Ledger.move(&s, .me, 5_000_000, why: "Test funds")
            var p = Hiring.generateCandidate(role: "waiter", company: nil, state: &s, data: data)
            p.skill = 40; p.claimedSkill = 70   // the CV says Strong, the person is Developing
            s.people[p.id] = p
            pid = p.id
        }
        let cash0 = e.state.cash
        guard case .ok(let ref) = e.referenceCheckCandidate(personID: pid) else { return XCTFail("the check should work") }
        XCTAssertEqual(ref.skillBand, "Developing")
        XCTAssertEqual(ref.claimedBand, "Strong")
        XCTAssertFalse(ref.matchesCV, "the CV does not match")
        XCTAssertLessThan(e.state.cash, cash0, "a reference check costs money")
        XCTAssertTrue(e.state.people[pid]?.flag("checked") ?? false)
        let cash1 = e.state.cash
        guard case .ok = e.referenceCheckCandidate(personID: pid) else { return XCTFail("reading it again is free") }
        XCTAssertEqual(e.state.cash, cash1)
        XCTAssertEqual(e.referenceCheckCandidate(personID: -1), .unknownPerson)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testReferenceCheckNeedsCash() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 32)
        var pid = 0
        e.update { s, data, _ in
            pid = Hiring.generateCandidate(role: "waiter", company: nil, state: &s, data: data).id
            let c = s.cash; Ledger.move(&s, .me, -c, why: "Spent")
        }
        XCTAssertEqual(e.referenceCheckCandidate(personID: pid), .notEnoughCash)
        XCTAssertFalse(e.state.people[pid]?.flag("checked") ?? true)
    }

    func testManagerReviewIsExternalAndPaidWithoutAnAnalyst() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 33)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 200_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: "cafe", cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            _ = Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6 + 3_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        for _ in 0..<(8 * 7) { e.nextDay() }
        XCTAssertEqual(e.reviewManagerNow(companyID: id), .noManager, "no manager yet")
        e.update { s, data, _ in
            let cafe = s.company(id)
            var m = Hiring.generateCandidate(role: "manager", company: cafe, state: &s, data: data)
            m.employerID = id
            s.people[m.id] = m
            s.companies[s.companyIndex(id)!].managerID = m.id
        }
        let cash0 = e.state.cash
        guard case .ok(let card) = e.reviewManagerNow(companyID: id) else { return XCTFail("the review should work") }
        XCTAssertTrue((0...100).contains(card.score))
        XCTAssertLessThan(e.state.cash, cash0, "an external review costs money")
        let kept = try XCTUnwrap(e.state.company(id)).value("lastRev")
        XCTAssertEqual(kept["score"].int, card.score)
        XCTAssertEqual(kept["w"].int, e.state.week)

        // with a performance analyst in the main office it is free
        e.update { s, _, _ in s.rest["office"] = .object(["staff": .array([.object(["role": "perf"])])]) }
        let cash1 = e.state.cash
        guard case .ok = e.reviewManagerNow(companyID: id) else { return XCTFail("the review should work") }
        XCTAssertEqual(e.state.cash, cash1)

        // and without money for the external review nothing happens
        e.update { s, _, _ in s.rest["office"] = .null; let c = s.cash; Ledger.move(&s, .me, -c, why: "Spent") }
        XCTAssertEqual(e.reviewManagerNow(companyID: id), .notEnoughCash)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }
}
