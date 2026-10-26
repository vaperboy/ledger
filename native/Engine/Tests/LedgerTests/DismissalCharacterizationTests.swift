import XCTest
import GameCore
import Countries
import Employees
import Finance
@testable import Businesses
import Simulation

/// Pins what every dismissal path pays today, before the paths share one engine function (roadmap A1, A2). The expected numbers are worked
/// out from `World.terminationPayments`, so the tests hold whether or not the paths share code.
final class DismissalCharacterizationTests: XCTestCase {
    private func cafe(_ code: String = "UK", seed: Int = 9) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: code, playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 30_000_000) else { throw XCTSkip("no company") }
        return (e, id)
    }

    @discardableResult
    private func addStaff(_ e: inout GameEngine, _ id: Int, years: Double, wage: Double = 300_000, warnings: Int = 0) -> Int {
        var sid = 0
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            var m = StaffMember(raw: [:])
            m.id = s.makeID(); m.role = "waiter"; m.monthlyWage = wage; m.hiredWeek = s.week - Int(years * 52)
            if warnings > 0 { m.set("warn", warnings) }
            s.companies[i].staff.append(m)
            sid = m.id
        }
        return sid
    }

    private func cash(_ e: GameEngine, _ id: Int) -> Double { e.state.company(id)?.cash ?? 0 }
    private func labels(_ e: GameEngine, _ id: Int) -> [String] { (e.state.company(id)?.transactions ?? []).map { $0["l"].string } }

    private func owed(_ e: GameEngine, _ id: Int, wage: Double, tenureWeeks: Double, _ reason: LabourRules.TerminationReason, age: Double? = nil) -> Double {
        let w = World(state: e.state, data: e.data)
        let p = w.terminationPayments(e.state.company(id)!, monthlyWage: wage, tenureWeeks: tenureWeeks, reason: reason, age: age)
        return p.notice + p.severance + p.fine
    }

    func testProfileDismissWithoutWarningsPaysTheStatute() throws {
        var (e, id) = try cafe()
        let sid = addStaff(&e, id, years: 5)
        let expected = owed(e, id, wage: 300_000, tenureWeeks: 260, .redundancy)
        XCTAssertGreaterThan(expected, 0)
        let before = cash(e, id)
        let r = try XCTUnwrap(e.dismissStaff(companyID: id, staffID: sid))
        XCTAssertEqual(r.severance, expected, accuracy: 1)
        XCTAssertEqual(before - cash(e, id), expected + r.compensation, accuracy: 2, "cash out is the quote plus any settlement")
        XCTAssertTrue(labels(e, id).contains("Severance"))
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testProfileDismissWithTwoWarningsPaysNoSeveranceAndNoClaim() throws {
        var (e, id) = try cafe()
        let sid = addStaff(&e, id, years: 5, warnings: 2)
        let expected = owed(e, id, wage: 300_000, tenureWeeks: 260, .forCause)
        let before = cash(e, id)
        let r = try XCTUnwrap(e.dismissStaff(companyID: id, staffID: sid))
        XCTAssertFalse(r.claimedUnfairDismissal)
        XCTAssertEqual(r.severance, expected, accuracy: 1)
        XCTAssertEqual(before - cash(e, id), expected, accuracy: 2)
        XCTAssertFalse(labels(e, id).contains("Severance"), "a documented dismissal owes no severance in the UK")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testLayoffPaysRedundancyByTenure() throws {
        var (e, id) = try cafe()
        addStaff(&e, id, years: 6, wage: 300_000)
        addStaff(&e, id, years: 1, wage: 200_000)
        let all = try XCTUnwrap(e.state.company(id)).staff
        let expected = all.reduce(0.0) { $0 + owed(e, id, wage: $1.monthlyWage, tenureWeeks: Double(e.state.week - $1.hiredWeek), .redundancy,
                                                      age: e.state.people[$1.id].map { Double($0.age) }) }
        XCTAssertGreaterThan(expected, 0)
        let preview = e.layoffPreview(companyID: id, count: all.count)
        let before = cash(e, id)
        let gone = e.layOffStaff(companyID: id, count: all.count)
        XCTAssertEqual(gone.count, all.count)
        XCTAssertEqual(before - cash(e, id), expected, accuracy: 2)
        XCTAssertEqual(preview.severance, expected, accuracy: 2)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testRosterFireIsARedundancy() throws {
        var (e, id) = try cafe()
        let sid = addStaff(&e, id, years: 4)
        let expected = owed(e, id, wage: 300_000, tenureWeeks: 208, .redundancy)
        let before = cash(e, id)
        let paid = e.fire(personID: sid, companyID: id)
        XCTAssertEqual(paid, expected, accuracy: 1)
        XCTAssertEqual(before - cash(e, id), expected, accuracy: 2)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testManagerDismissalPaysTheStatuteUnderManagerLabels() throws {
        var (e, id) = try cafe()
        let cands = try XCTUnwrap(e.searchManagers(companyID: id))
        let pick = cands[0]
        XCTAssertEqual(e.hireManager(personID: pick.id, companyID: id, monthlyWage: pick.askingMonthlyWage * 1.2), .ok)
        e.update { s, _, _ in s.companies[s.companyIndex(id)!].set("mgrW0", s.week - 260) }
        let co = try XCTUnwrap(e.state.company(id))
        let expected = owed(e, id, wage: co.managerMonthlyWage, tenureWeeks: 260, .redundancy, age: e.state.people[pick.id].map { Double($0.age) })
        XCTAssertGreaterThan(expected, 0)
        let before = cash(e, id)
        let sev = e.dismissManager(companyID: id)
        XCTAssertEqual(sev, expected, accuracy: 1)
        XCTAssertEqual(before - cash(e, id), expected, accuracy: 2)
        XCTAssertTrue(labels(e, id).contains("Manager severance"))
        XCTAssertNil(e.state.company(id)?.managerID)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testAssistantDismissalIsAMonthOfPayWithEmployerCharge() throws {
        var (e, id) = try cafe()
        let cands = try XCTUnwrap(e.searchManagers(companyID: id))
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].set("asst", .object(["npc": .number(Double(cands[1].id)), "wage": .number(200_000), "duties": .array([]), "w0": .number(Double(s.week))]))
            var p = s.people[cands[1].id]!; p.employerID = id; s.people[p.id] = p
        }
        let social = World(state: e.state, data: e.data).country(try XCTUnwrap(e.state.company(id))).employerOnCost(monthlyWage: 200_000)
        let before = cash(e, id)
        e.dismissAssistant(companyID: id)
        XCTAssertEqual(before - cash(e, id), 200_000 * (1 + social), accuracy: 2)
        XCTAssertTrue(labels(e, id).contains("Notice pay"))
        XCTAssertTrue(e.state.company(id)!.value("asst").isNull)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testResignationLeavesWithoutAPayment() throws {
        var (e, id) = try cafe()
        let sid = addStaff(&e, id, years: 5)
        let before = cash(e, id)
        e.update { s, d, _ in StaffRoutine.handle(&s, companyIndex: s.companyIndex(id)!, .leave(staffID: sid), data: d) }
        XCTAssertNil(e.state.company(id)?.staff.first { $0.id == sid })
        XCTAssertEqual(cash(e, id), before, accuracy: 0.5)
        XCTAssertEqual(e.state.people[sid]?.employerID ?? 0, 0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testTeamSlotReleaseIsAMonthOfPay() throws {
        var (e, id) = try cafe()
        let cands = try XCTUnwrap(e.searchManagers(companyID: id))
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].set("team", .object(["ceo": .object(["npc": .number(Double(cands[2].id)), "wage": .number(500_000)]), "heads": .object([:])]))
            var p = s.people[cands[2].id]!; p.employerID = id; s.people[p.id] = p
        }
        let social = World(state: e.state, data: e.data).country(try XCTUnwrap(e.state.company(id))).employerOnCost(monthlyWage: 500_000)
        let before = cash(e, id)
        XCTAssertTrue(e.releaseTeam(companyID: id, key: "ceo"))
        XCTAssertEqual(before - cash(e, id), 500_000 * (1 + social), accuracy: 2)
        XCTAssertTrue(labels(e, id).contains { $0.hasPrefix("Severance: ") })
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }
}
