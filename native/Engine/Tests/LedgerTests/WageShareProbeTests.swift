import XCTest
import GameCore
import Countries
import Employees
import Finance
@testable import Businesses
import Simulation

/// LEDGER_WAGEPROBE=1: why do wages come out above the control in a one-year managed cafe with bonus plans, perks and expenses?
/// Splits the difference into hire noise (a control that differs only by one extra random draw), the plan's own cost (bonus accrued, perk cost) and
/// headcount/turnover. Prints; asserts nothing. See native/docs/KNOWN_GAPS.md ("Wage share check").
final class WageShareProbeTests: XCTestCase {
    private func open(seed: Int) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 200_000_000, why: "Test funds") }
        guard case .success(let id) = e.startCompany(tradeID: "cafe", cityID: e.state.player.cityID, form: .limited, fundWith: 60_000_000) else { throw XCTSkip("no company") }
        var days = 0
        while e.state.company(id)?.status != .open, days < 60 * 7 { e.nextDay(); days += 1 }
        return (e, id)
    }

    private func hire(_ e: inout GameEngine, _ id: Int, role: String) -> Int? {
        var pid = 0
        e.update { s, d, _ in
            var p = Hiring.generateCandidate(role: role, company: s.company(id), tier: "mid", state: &s, data: d)
            p.set("pers", "steady"); p.set("sec", 0.1)
            s.people[p.id] = p; pid = p.id
        }
        return e.hire(personID: pid, companyID: id, monthlyWage: e.state.people[pid]!.askingMonthlyWage * 1.5, terms: Hiring.Terms()) == .ok ? pid : nil
    }

    enum Variant: String, CaseIterable { case control, noise, all, bonusOnly, trainingOnly, lunchOnly }

    private struct Year { var wages = 0.0, oth = 0.0, rev = 0.0, bonus = 0.0, crewWage = 0.0, avgHeads = 0.0, heads = 0, everHired = 0, managerWage = 0.0 }

    private func year(seed: Int, _ v: Variant) throws -> Year {
        var (e, id) = try open(seed: seed)
        let cands = try XCTUnwrap(e.searchManagers(companyID: id))
        XCTAssertEqual(e.hireManager(personID: cands[0].id, companyID: id, monthlyWage: cands[0].askingMonthlyWage * 1.3), .ok)
        var crew: [Int] = []
        for r in ["barista", "barista", "cook", "waiter"] { if let p = hire(&e, id, role: r) { crew.append(p) } }
        if v == .noise { e.update { s, _, _ in _ = s.random.next() } }
        for p in crew {
            if v == .all || v == .bonusOnly { _ = e.contractPropose(companyID: id, personID: p, proposal: .init(.bonus, choice: "plan:standard")) }
            if v == .all || v == .trainingOnly { _ = e.contractPropose(companyID: id, personID: p, proposal: .init(.benefits, amount: 1, choice: "exp:training")) }
        }
        if v == .all || v == .lunchOnly { _ = e.toggleStaffPerk(companyID: id, perk: "lunch", group: "crew") }
        var y = Year(), prev = 0.0
        var seen = Set(e.state.company(id)?.staff.map { $0.id } ?? [])
        for _ in 0..<(52 * 7) {
            e.nextDay()
            let pend = e.state.company(id)?.num("bnPend") ?? 0
            if pend > prev { y.bonus += pend - prev }
            prev = pend
            for m in e.state.company(id)?.staff ?? [] { seen.insert(m.id) }
            y.avgHeads += Double(e.state.company(id)?.staff.count ?? 0) / Double(52 * 7)
        }
        let co = try XCTUnwrap(e.state.company(id))
        y.wages = co.books.total["wages"] ?? 0; y.oth = co.books.total["oth"] ?? 0; y.rev = co.books.total["rev"] ?? 0
        y.crewWage = co.staff.reduce(0) { $0 + $1.monthlyWage }; y.heads = co.staff.count; y.everHired = seen.count; y.managerWage = co.managerMonthlyWage
        return y
    }

    func testPrintWhereTheWageDifferenceComesFrom() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_WAGEPROBE"] != nil else { return }
        let seeds = (ProcessInfo.processInfo.environment["LEDGER_SEEDS"] ?? "3,7,11,13,17,19,23,29").split(separator: ",").compactMap { Int($0) }
        for seed in seeds {
            let ctl = try year(seed: seed, .control)
            var line = String(format: "WAGE seed %2d control wages %.0f (avg heads %.2f)", seed, ctl.wages, ctl.avgHeads)
            for v in Variant.allCases where v != .control {
                let y = try year(seed: seed, v)
                line += String(format: " | %@ %+.1f%% (avg heads %.2f vs %.2f, wages per average head %+.1f%%, bonus accrued %.1f%% of control wages)", v.rawValue, (y.wages / ctl.wages - 1) * 100, y.avgHeads, ctl.avgHeads, ((y.wages / max(0.1, y.avgHeads)) / (ctl.wages / max(0.1, ctl.avgHeads)) - 1) * 100, y.bonus / ctl.wages * 100)
            }
            print(line)
        }
    }
}
