import XCTest
import GameCore
import Finance
import Businesses
import Employees
import Simulation

final class MileageAndCommissionFloorTests: XCTestCase {
    private func estate(_ code: String, seed: Int = 11) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: code, playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 80_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "estate", cityID: e.state.player.cityID, fundWith: 30_000_000) else {
            XCTFail("could not start an estate company in \(code)"); throw CocoaError(.fileReadUnknown)
        }
        var days = 0
        while e.state.company(id)?.status != .open, days < 60 * 7 { e.nextDay(); days += 1 }
        XCTAssertEqual(e.state.company(id)?.status, .open, "\(code) opens")
        e.update { s, _, _ in if let i = s.companyIndex(id) { s.companies[i].managerID = 0 } }
        e.update { s, _, _ in if let i = s.companyIndex(id), s.companies[i].value("prem")["kind"].string == "office" || s.companies[i].value("prem")["kind"].isNull { var p = s.companies[i].value("prem"); if p.isNull { p = .object([:]) }; p["m2"] = .number(900); s.companies[i].set("prem", p) } }
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

    func testFourWeeksBookExactlyFourWeeksOfMileage() throws {
        var (e, id) = try estate("UK")
        let pid = try hireAgent(&e, id)
        var withCar = e, without = e
        XCTAssertTrue(withCar.contractPropose(companyID: id, personID: pid, proposal: .init(.benefits, amount: 1, choice: "ownCar")).changedTerms)
        XCTAssertFalse(without.state.company(id)!.staff.first { $0.id == pid }!.flag("ownCar"))
        let w0 = World(state: e.state, data: e.data), co0 = e.state.company(id)!
        let weekly = PersonalEquipment.mileagePerMonth(w0.currency(co0), country: w0.country(co0), e.data.catalog["estate"]!, tables: e.data.catalog.tables) * 12 / 52
        func mileage(_ g: GameEngine, since: Int) -> (n: Int, sum: Double) {
            let t = g.state.company(id)!.transactions.filter { $0["l"].string == "Mileage for own cars" && $0["w"].int > since }
            return (t.count, t.reduce(0) { $0 + abs($1["a"].double) })
        }
        let start = withCar.state.week
        var measured = 0
        for k in 1...4 {
            for _ in 0..<7 { withCar.nextDay(); without.nextDay() }
            let m = mileage(withCar, since: start)
            XCTAssertEqual(m.n, k, "each week books one mileage line, not two")
            XCTAssertEqual(m.sum, weekly * Double(k), accuracy: 1.0 * Double(k), "each week books one week of mileage, not two")
            XCTAssertEqual(mileage(without, since: start).n, 0)
            measured += 1
        }
        XCTAssertGreaterThanOrEqual(measured, 3)
        XCTAssertTrue(Ledger.gaps(withCar.state).isEmpty)
        XCTAssertTrue(Ledger.gaps(without.state).isEmpty)
    }

    private func payModelFloor(_ code: String, mode: String, hours: Double?) throws {
        var (e, id) = try estate(code)
        let pid = try hireAgent(&e, id, hours: hours)
        e.update { s, _, _ in
            s.people[pid]!.set("sec", 0.1); s.people[pid]!.set("pers", "loyal")
            do { let ci = s.companyIndex(id)!; var st = s.companies[ci].staff; if let k = st.firstIndex(where: { $0.id == pid }) { st[k].happyUntilWeek = s.week + 60; s.companies[ci].staff = st } }
            var flags = s.company(id)!.value("flags"); flags["noquit"] = 1; s.companies[s.companyIndex(id)!].set("flags", flags)
        }
        XCTAssertTrue(e.contractPropose(companyID: id, personID: pid, proposal: .init(.payBasis, choice: mode)).changedTerms, code)
        func check(_ note: String) {
            let w = World(state: e.state, data: e.data)
            let co = e.state.company(id)!
            guard let m = co.staff.first(where: { $0.id == pid }) else { return }
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

    func testCommissionStillAccruesWithNoBase() throws {
        var (e, id) = try estate("UK", seed: 5)
        let pid = try hireAgent(&e, id)
        e.update { s, _, _ in
            s.people[pid]!.set("sec", 0.1); s.people[pid]!.set("pers", "loyal")
            do { let ci = s.companyIndex(id)!; var st = s.companies[ci].staff; if let k = st.firstIndex(where: { $0.id == pid }) { st[k].happyUntilWeek = s.week + 60; s.companies[ci].staff = st } }
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
