import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// LEDGER_MGRPROBE=1: managed companies over several seeds, two years: revenue, profit, rating, awareness and how many weeks the
/// manager had targets for the month. Used to report what a change to the manager-target rules does to managed companies; it asserts nothing.
final class ManagedTargetsProbeTests: XCTestCase {
    func testPrintManagedCompanies() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["LEDGER_MGRPROBE"] != nil else { return }
        let trades = (env["LEDGER_TRADES"] ?? "cafe,bakery,gym,barber").split(separator: ",").map(String.init)
        let seeds = (env["LEDGER_SEEDS"] ?? "11,12,13,14,15,16,17,18").split(separator: ",").compactMap { Int($0) }
        var grand = (rev: 0.0, profit: 0.0, rating: 0.0, aware: 0.0, tw: 0.0, n: 0.0)
        for trade in trades {
            var t = (rev: 0.0, profit: 0.0, rating: 0.0, aware: 0.0, tw: 0.0, n: 0.0)
            for seed in seeds {
                var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: seed)
                var id = 0
                e.update { s, data, ctx in
                    Ledger.move(&s, .me, 60_000_000_000, why: "Test funds")
                    guard case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: .limited, data: data, context: ctx) else { return }
                    id = i
                    let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
                    Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.3)
                    _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
                }
                guard id != 0, let cands = e.searchManagers(companyID: id), let c = cands.first else { continue }
                _ = e.hireManager(personID: c.id, companyID: id, monthlyWage: c.askingMonthlyWage * 1.2)
                var weeksWithTargets = 0.0
                for day in 0..<(2 * 52 * 7) {
                    e.nextDay()
                    for m in e.openDecisions where m.actionID.hasPrefix("pay29") || ManagerTargets.handlesAnswer(m.actionID) || ["prop", "mgrraise", "mgrpoach", "staffx"].contains(m.actionID) { e.answer(messageID: m.id, option: 0) }
                    if day % 7 == 0, let co = e.state.company(id), co.managerID != nil, ManagerTargets.current(co, week: e.state.week) != nil { weeksWithTargets += 1 }
                    if let co = e.state.company(id), co.status.isLive, co.cash < -50_000 { e.update { s, _, _ in Payments.injectCash(&s, companyID: id, amount: -co.cash + 100_000) } }
                }
                guard let co = e.state.company(id) else { continue }
                let h = co.monthlyHistory.suffix(12)
                t.rev += h.reduce(0) { $0 + $1.revenue }; t.profit += h.reduce(0) { $0 + $1.profit }
                t.rating += Reviews.rating(co); t.aware += co.awareness; t.tw += weeksWithTargets; t.n += 1
            }
            if t.n > 0 { print(String(format: "MGR %@ n=%.0f year2 revenue %.0f profit %.0f rating %.3f awareness %.2f weeks-with-targets %.1f", trade, t.n, t.rev / t.n, t.profit / t.n, t.rating / t.n, t.aware / t.n, t.tw / t.n)) }
            grand.rev += t.rev; grand.profit += t.profit; grand.rating += t.rating; grand.aware += t.aware; grand.tw += t.tw; grand.n += t.n
        }
        if grand.n > 0 { print(String(format: "MGR ALL n=%.0f year2 revenue %.0f profit %.0f rating %.3f awareness %.2f weeks-with-targets %.1f", grand.n, grand.rev / grand.n, grand.profit / grand.n, grand.rating / grand.n, grand.aware / grand.n, grand.tw / grand.n)) }
    }
}
