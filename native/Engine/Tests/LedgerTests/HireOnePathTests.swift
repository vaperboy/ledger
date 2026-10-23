import XCTest
import GameCore
import Finance
import Businesses
import Simulation

/// A6: one engine path hires a candidate. These tests pin what the two `GameEngine.hire` overloads did, then that one path serves every caller.
final class HireOnePathTests: XCTestCase {
    private func shop(_ trade: String, seed: Int = 11) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 80_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, form: .limited, fundWith: 20_000_000) else { XCTFail("start"); throw CocoaError(.fileReadUnknown) }
        return (e, id)
    }

    private func candidate(_ e: inout GameEngine, _ id: Int, role: String) -> Int {
        var pid = 0
        e.update { s, d, _ in pid = Hiring.generateCandidate(role: role, company: s.company(id), tier: "mid", state: &s, data: d).id }
        return pid
    }

    private struct Outcome: Equatable {
        var result: Hiring.HireResult
        var randomState: Int32
        var staffCount: Int
        var wage: Double?
        var basis: String?
        var onboarding: String?
        var ownCar: Bool
        var gaps: Int
    }

    private func outcome(_ e: GameEngine, _ id: Int, _ pid: Int, _ r: Hiring.HireResult) -> Outcome {
        let co = e.state.company(id)!
        let m = co.staff.first { $0.id == pid }
        return Outcome(result: r, randomState: e.state.random.state, staffCount: co.staff.count, wage: m?.monthlyWage, basis: m?.payBasis,
                       onboarding: m.map { "\($0.value("onb"))" }, ownCar: m?.flag("ownCar") ?? false, gaps: Ledger.gaps(e.state).count)
    }

    /// Offers of every size (refused, accepted) give the same result and use the same random draws through either entry point and the core function.
    func testOffersMatchBetweenEntryPointsAndTheCoreFunction() throws {
        for factor in [0.5, 0.8, 0.9, 1.0, 1.1, 1.4] {
            let (e0, id) = try shop("cafe")
            var base = e0
            let pid = candidate(&base, id, role: "barista")
            let wage = base.state.people[pid]!.askingMonthlyWage * factor
            var a = base, b = base, c = base
            let ra = a.hire(personID: pid, companyID: id, monthlyWage: wage)
            let rb = b.hire(personID: pid, companyID: id, monthlyWage: wage, terms: Hiring.Terms())
            var rc = Hiring.HireResult.refused
            c.update { s, d, _ in rc = Hiring.hire(pid, into: id, monthlyWage: wage, state: &s, data: d) }
            XCTAssertEqual(outcome(a, id, pid, ra), outcome(b, id, pid, rb), "factor \(factor)")
            XCTAssertEqual(outcome(a, id, pid, ra), outcome(c, id, pid, rc), "factor \(factor)")
            if ra == .ok { XCTAssertEqual(a.hire(personID: pid, companyID: id, monthlyWage: wage), .taken) }
        }
    }

    func testMinimumWageIsRaisedAndTheBooksBalance() throws {
        var (e, id) = try shop("cafe")
        let minimum = World(state: e.state, data: e.data).minimumWage(e.state.company(id)!)
        let p = candidate(&e, id, role: "barista")
        e.update { s, _, _ in s.people[p]!.askingMonthlyWage = minimum * 0.9 }
        XCTAssertEqual(e.hire(personID: p, companyID: id, monthlyWage: 1), .ok, "an offer of 1 is raised to the minimum")
        XCTAssertGreaterThanOrEqual(e.state.company(id)!.staff.first { $0.id == p }!.monthlyWage, minimum - 0.5)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testRecordAndPaperworkAreCreatedTogether() throws {
        var (e, id) = try shop("cafe")
        let pid = candidate(&e, id, role: "barista")
        XCTAssertEqual(e.hire(personID: pid, companyID: id, monthlyWage: e.state.people[pid]!.askingMonthlyWage * 1.5), .ok)
        let m = try XCTUnwrap(e.state.company(id)!.staff.first { $0.id == pid })
        XCTAssertEqual(m.hiredWeek, e.state.week)
        XCTAssertEqual(e.state.people[pid]!.employerID, id)
        XCTAssertFalse(m.value("onb").isNull)
    }

    /// Own car: asked for through `Terms`, for estate agents only (the player-facing path). The old plain overload's flag did not check the role.
    func testOwnCarOnlyForEstateAgents() throws {
        var (e, id) = try shop("estate")
        let agent = candidate(&e, id, role: "estate")
        XCTAssertEqual(e.hire(personID: agent, companyID: id, monthlyWage: e.state.people[agent]!.askingMonthlyWage * 1.5, terms: Hiring.Terms(ownCar: true)), .ok)
        XCTAssertTrue(e.state.company(id)!.staff.first { $0.id == agent }!.flag("ownCar"))
        let other = candidate(&e, id, role: "barista")
        XCTAssertEqual(e.hire(personID: other, companyID: id, monthlyWage: e.state.people[other]!.askingMonthlyWage * 1.5, terms: Hiring.Terms(ownCar: true)), .ok)
        XCTAssertFalse(e.state.company(id)!.staff.first { $0.id == other }!.flag("ownCar"))
    }

    func testPartTimeAndSeasonalTermsAreApplied() throws {
        var (e, id) = try shop("cafe")
        let a = candidate(&e, id, role: "barista"), b = candidate(&e, id, role: "barista")
        XCTAssertEqual(e.hire(personID: a, companyID: id, monthlyWage: e.state.people[a]!.askingMonthlyWage * 1.4, terms: Hiring.Terms(hours: 20)), .ok)
        XCTAssertNotNil(e.state.company(id)!.staff.first { $0.id == a }!.weeklyHours)
        XCTAssertEqual(e.state.company(id)!.staff.first { $0.id == a }!.payBasis, "hour")
        XCTAssertEqual(e.hire(personID: b, companyID: id, monthlyWage: e.state.people[b]!.askingMonthlyWage * 1.4, terms: Hiring.Terms(hours: 25, seasonMonths: [6, 7])), .ok)
        XCTAssertFalse(e.state.company(id)!.staff.first { $0.id == b }!.value("seas").isNull)
    }

    // MARK: Only one function makes staff records

    func testOnlyHiringHireCreatesStaffFromACandidate() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources")
        var creators: [String] = []
        var engineHires: [String] = []
        for case let url as URL in FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)! where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains("StaffMember(raw") { creators.append(url.lastPathComponent) }
            if text.contains("mutating func hire(personID") { engineHires.append(url.lastPathComponent) }
        }
        XCTAssertEqual(creators, ["Hiring.swift"], "a staff record from a candidate is made in Hiring.hire only")
        XCTAssertEqual(engineHires, ["MiscActions.swift"], "GameEngine has one hire(personID:) and it passes terms through")
    }
}
