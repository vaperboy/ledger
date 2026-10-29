import XCTest
import GameCore
import Finance
import Businesses
import Employees
import Simulation

/// Stage 2 defects from the audit of cars, perks and commission: mileage booked twice. Owner rule: commission only means NOTHING in base pay,
/// whatever the minimum wage; "mix" keeps a real base and "fix" keeps its wage, both never under the minimum.
final class MileageAndCommissionFloorTests: XCTestCase {
    private func estate(_ code: String, seed: Int = 11) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: code, playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 80_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "estate", cityID: e.state.player.cityID, form: .limited, fundWith: 30_000_000) else {
            XCTFail("could not start an estate company in \(code)"); throw CocoaError(.fileReadUnknown)
        }
        // Licences and fit-out take a few weeks; the weekly staff routine only runs for an open company.
        var days = 0
        while e.state.company(id)?.status != .open, days < 60 * 7 { e.nextDay(); days += 1 }
        XCTAssertEqual(e.state.company(id)?.status, .open, "\(code) opens")
        return (e, id)
    }

    private func hireAgent(_ e: inout GameEngine, _ id: Int, hours: Double? = nil) throws -> Int {
        var pid = 0
        e.update { s, d, _ in pid = Hiring.generateCandidate(role: "estate", company: s.company(id), tier: "mid", state: &s, data: d).id }
        let wage = e.state.people[pid]!.askingMonthlyWage * 1.5
        let r = hours.map { e.hire(personID: pid, companyID: id, monthlyWage: wage, terms: Hiring.Terms(hours: $0)) } ?? e.hire(personID: pid, companyID: id, monthlyWage: wage)
        XCTAssertEqual(r, .ok)
        return pid
    }

    // MARK: Mileage

    /// One agent on their own car for 4 weeks costs exactly 4 weeks of mileage, not 8, and the books still balance.
    func testFourWeeksBookExactlyFourWeeksOfMileage() throws {
        var (e, id) = try estate("UK")
        let pid = try hireAgent(&e, id)
        var withCar = e, without = e
        XCTAssertTrue(withCar.contractPropose(companyID: id, personID: pid, proposal: .init(.benefits, amount: 1, choice: "ownCar")).changedTerms)
        XCTAssertFalse(without.state.company(id)!.staff.first { $0.id == pid }!.flag("ownCar"))
        let w0 = World(state: e.state, data: e.data), co0 = e.state.company(id)!
        let weekly = PersonalEquipment.mileagePerMonth(w0.currency(co0), country: w0.country(co0), e.data.catalog["estate"]!, tables: e.data.catalog.tables) * 12 / 52
        func oth(_ g: GameEngine) -> Double { g.state.company(id)!.books.year["oth"] ?? 0 }
        var measured = 0
        for _ in 0..<4 {
            let w0 = oth(withCar), n0 = oth(without)
            for _ in 0..<7 { withCar.nextDay(); without.nextDay() }
            let w1 = oth(withCar), n1 = oth(without)
            if w1 < w0 || n1 < n0 { continue }   // the year's books rolled over in this week: nothing to compare
            XCTAssertEqual((w1 - w0) - (n1 - n0), weekly, accuracy: 1.0, "each week books one week of mileage, not two")
            measured += 1
        }
        XCTAssertGreaterThanOrEqual(measured, 3)
        XCTAssertTrue(Ledger.gaps(withCar.state).isEmpty)
        XCTAssertTrue(Ledger.gaps(without.state).isEmpty)
    }

    // MARK: Commission pay and the minimum wage

    private func payModelFloor(_ code: String, mode: String, hours: Double?) throws {
        var (e, id) = try estate(code)
        let pid = try hireAgent(&e, id, hours: hours)
        // A security-minded person may refuse commission only; pick a seed-independent person by clearing the trait.
        e.update { s, _, _ in
            s.people[pid]!.set("sec", 0.1)
            var flags = s.company(id)!.value("flags"); flags["noquit"] = 1; s.companies[s.companyIndex(id)!].set("flags", flags)
        }
        XCTAssertTrue(e.contractPropose(companyID: id, personID: pid, proposal: .init(.payBasis, choice: mode)).changedTerms, code)
        func check(_ note: String) {
            let w = World(state: e.state, data: e.data)
            let co = e.state.company(id)!
            guard let m = co.staff.first(where: { $0.id == pid }) else { return }   // left by chance during the 26 weeks
            let floor = w.minimumWage(co, hours: m.weeklyHours ?? StaffModel.fullWeekHours)
            if mode == "com" {
                XCTAssertEqual(m.monthlyWage, 0, "\(code) commission only \(note): base pay must be nothing, was \(m.monthlyWage)")
            } else {
                XCTAssertGreaterThanOrEqual(m.monthlyWage, floor - 0.5, "\(code) \(mode) \(note): base \(m.monthlyWage) under minimum \(floor)")
                XCTAssertGreaterThan(m.monthlyWage, 0, "\(code) \(mode) keeps a real base")
            }
            XCTAssertEqual(m.commissionMode, mode == "fix" ? "fix" : mode)
        }
        check("after setting")
        for _ in 0..<(26 * 7) { e.nextDay() }
        check("after 26 weeks")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, code)
        guard mode != "fix" else { return }
    }

    func testCommissionOnlyHasNoBaseAndMixAndFixKeepTheMinimumWageInSeveralCountries() throws {
        for code in ["UK", "US", "MX", "PL"] {
            for mode in ["com", "mix", "fix"] {
                try payModelFloor(code, mode: mode, hours: nil)
                try payModelFloor(code, mode: mode, hours: 20)
            }
        }
    }

    /// Commission still accrues with no base: the smoothed commission feeds `commEma` once the seller has sales.
    func testCommissionStillAccruesWithNoBase() throws {
        var (e, id) = try estate("UK", seed: 3)
        let pid = try hireAgent(&e, id)
        e.update { s, _, _ in
            s.people[pid]!.set("sec", 0.1)
            var flags = s.company(id)!.value("flags"); flags["noquit"] = 1; s.companies[s.companyIndex(id)!].set("flags", flags)
            Ledger.move(&s, .company(id), 5_000_000, why: "Test funds")
        }
        XCTAssertTrue(e.contractPropose(companyID: id, personID: pid, proposal: .init(.payBasis, choice: "com")).changedTerms)
        var accrued = 0.0, weeks = 0
        for _ in 0..<(26 * 7) {
            e.nextDay()
            guard let m = e.state.company(id)?.staff.first(where: { $0.id == pid }) else { break }
            weeks += 1
            accrued = max(accrued, m.num("commEma"))
        }
        let co = try XCTUnwrap(e.state.company(id))
        let m = try XCTUnwrap(co.staff.first { $0.id == pid })
        _ = co
        XCTAssertEqual(m.monthlyWage, 0, "commission only stays without a base after 26 weeks")
        XCTAssertGreaterThan(accrued, 0, "commission accrued")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }
}
