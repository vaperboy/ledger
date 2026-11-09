import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Simulation

/// People complete their own onboarding papers as part of settling in, an accountant files for the rest, and what is still open costs fines.
final class StaffPaperworkTests: XCTestCase {
    private func open(_ e: GameEngine) -> Int { e.state.companies[0].staff.reduce(0) { $0 + StaffExtras.missing($1).count } }

    private func blank(_ e: inout GameEngine) {
        e.update { s, _, _ in
            var staff = s.companies[0].staff
            for k in staff.indices { staff[k].set("onb", .object([:])) }
            s.companies[0].staff = staff
        }
    }

    func testStaffFillInTheirOwnPaperworkOverTheWeeks() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5, story: .fresh, tradeID: "cafe")
        blank(&e)
        let start = open(e)
        XCTAssertGreaterThan(start, 0)
        for _ in 0..<(7 * 12) { _ = e.nextDay() }
        let now = e.state.companies[0].staff.reduce(0) { $0 + StaffExtras.missing($1).count }
        XCTAssertLessThan(now, start / 4, "papers still open after twelve weeks: \(now) of \(start)")
    }

    func testAnAccountantFilesForTheOthers() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5, story: .fresh, tradeID: "cafe")
        e.update { s, _, _ in
            var staff = s.companies[0].staff
            var second = staff[0]
            second.set("id", .number(Double(s.makeID())))
            staff[0].role = "acct"
            staff.append(second)
            s.companies[0].staff = staff
        }
        blank(&e)
        var r = DeterministicRandom(seed: 3)
        var staff = e.state.companies[0].staff
        for _ in 0..<6 { StaffExtras.filedByAccountant(&staff, random: &r) }
        XCTAssertEqual(staff.dropFirst().reduce(0) { $0 + StaffExtras.missing($1).count }, 0)
    }

    func testMissingPaperworkStillCostsFines() throws {
        var r = DeterministicRandom(seed: 9)
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5, story: .fresh, tradeID: "cafe")
        var m = e.state.companies[0].staff[0]
        m.set("onb", .object([:])); m.hiredWeek = 0
        var person = try XCTUnwrap(e.state.people[m.id])
        var fines = 0
        for _ in 0..<2000 {
            var mm = m
            mm.set("onb", .object([:]))
            fines += StaffExtras.week(&mm, person: &person, week: 10, random: &r, companyUtilisation: nil, hasManager: false, managerLearned: false).fines.count
        }
        XCTAssertGreaterThan(fines, 0)
    }
}
