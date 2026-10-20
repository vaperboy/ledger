import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation
import Employees

/// Week-by-week averages over 12 seeds, the native twin of tools/ref/snippets/trace_weeks.js (see docs/BALANCE_PARITY.md).
/// Prints JSON in the same shape as the original script. Not a pass/fail test: it only runs with LEDGER_STATS=1.
final class BalanceTraceTests: XCTestCase {
    /// LEDGER_FAITHFUL=1: set-up and staffing as the original's test script does (one offer per job, nobody replaced when they leave).
    static var faithful: Bool { ProcessInfo.processInfo.environment["LEDGER_FAITHFUL"] != nil }
    func testPrintWeekTrace() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_STATS"] != nil else { return }
        let trades = (ProcessInfo.processInfo.environment["LEDGER_TRADES"] ?? "gym,bakery,restaurant,cafe").split(separator: ",").map(String.init)
        let seeds = (0..<12).map { 1000 + $0 * 37 }
        var out: [String: Any] = [:]
        for t in trades {
            var W = Array(repeating: [String: Double](), count: 26)
            var cnt = Array(repeating: 0.0, count: 26)
            var books: [String: Double] = [:]
            var nb = 0.0, inv = 0.0
            for sd in seeds {
                var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: sd)
                var id = 0
                e.update { s, data, ctx in
                    Ledger.move(&s, .me, 50_000_000, why: "Test funds")
                    if case .success(let i) = CompanySetup.create(&s, tradeID: t, cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
                    let est = CompanySetup.estimate(tradeID: t, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
                    Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6)
                    _ = CompanySetup.quickSetup(&s, companyID: id, data: data, faithfulHiring: BalanceTraceTests.faithful)
                }
                if BalanceTraceTests.faithful { e.setPolicy({ var p = ManagementPolicy(); p.autoRehire = false; return p }()) }
                for d in 0..<(26 * 7) {
                    e.nextDay()
                    for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
                    if d % 7 == 6, let co = e.state.company(id) {
                        let lw = co.value("lastW"); let k = d / 7
                        for (n, v) in [("D", lw["D"].double), ("cap", lw["cap"].double), ("units", lw["units"].double), ("rev", lw["rev"].double), ("cogs", lw["cogs"].double),
                                       ("aware", co.awareness), ("rep", co.reputation), ("q", co.quality), ("staff", Double(co.staff.count)), ("cash", co.cash)] {
                            W[k][n, default: 0] += v
                        }
                        cnt[k] += 1
                    }
                }
                let co = e.state.company(id)!
                for (k, v) in co.books.total { books[k, default: 0] += v }
                nb += 1; inv += co.inventory
            }
            let weeks: [[String: Int]] = (0..<26).map { k in W[k].mapValues { Int(($0 / max(1, cnt[k])).rounded()) } }
            out[t] = ["weeks": weeks, "books": books.mapValues { Int(($0 / nb).rounded()) }, "inv": Int(inv / nb)] as [String: Any]
        }
        let data = try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
        print("TRACE " + String(decoding: data, as: UTF8.self))
    }

    func testPrintInjected() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_STATS"] != nil else { return }
        for t in ["cafe", "gym", "restaurant", "bakery", "courier", "barber", "boutique", "webdev"] {
            let e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 1000)
            let est = CompanySetup.estimate(tradeID: t, cityID: e.state.player.cityID, form: .limited, size: 1, state: e.state, data: e.data)!
            var e2 = e
            var id = 0; var before = 0.0
            e2.update { s, data, ctx in
                Ledger.move(&s, .me, 50_000_000, why: "Test funds")
                if case .success(let i) = CompanySetup.create(&s, tradeID: t, cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
                Payments.injectCash(&s, companyID: id, amount: est.total * 1.6)
                before = s.company(id)!.cash
                _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
            }
            let c = e2.state.company(id)!
            let eqc = c.value("eq").object.values.reduce(0) { $0 + $1["cost"].double }
            print("SETUPC \(t) size=\(c.size) before=\(Int(before)) after=\(Int(c.cash)) spent=\(Int(before - c.cash)) eqc=\(Int(eqc)) veh=\(c.value("veh").array.count) prem=\(c.value("prem")["m2"].double)/\(Int(c.value("prem")["rent"].double)) staff=\(c.staff.map { $0.role + ":" + String(Int($0.monthlyWage)) })")
            print("INJ \(t) total=\(Int(est.total)) x1.6=\(Int(est.total * 1.6)) \(est)")
        }
    }

    /// One company, one seed, week by week (twin of snippets/weekly_one.js): LEDGER_TRADE, LEDGER_SEED.
    func testPrintWeeklyOne() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_STATS"] != nil else { return }
        let t = ProcessInfo.processInfo.environment["LEDGER_TRADE"] ?? "boutique"
        let seed = Int(ProcessInfo.processInfo.environment["LEDGER_SEED"] ?? "1000")!
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 50_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: t, cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: t, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data, faithfulHiring: BalanceTraceTests.faithful)
        }
        if BalanceTraceTests.faithful { e.setPolicy({ var p = ManagementPolicy(); p.autoRehire = false; return p }()) }
        for d in 0..<(26 * 7) {
            e.nextDay(); for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
            if d % 7 == 6 {
                let co = e.state.company(id)!
                let b = co.books.total
                print("WEEK \(d / 7 + 1) cash=\(Int(co.cash)) inv=\(Int(co.inventory)) vat=\(Int(co.vatBalance)) pay=\(co.value("pay")) rev=\(Int(b["rev"] ?? 0)) cogs=\(Int(b["cogs"] ?? 0)) oth=\(Int(b["oth"] ?? 0)) tax=\(Int(b["tax"] ?? 0)) wages=\(Int(b["wages"] ?? 0)) rent=\(Int(b["rent"] ?? 0))")
            }
        }
    }

    /// Where does one company's cash go? Tallies every balance change by the calling function (`LEDGER_STATS=1 LEDGER_TRADE=boutique swift test -c release --filter testPrintCashByCause`). Twin of snippets/cash_by_cause.js.
    func testPrintCashByCause() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_STATS"] != nil else { return }
        let t = ProcessInfo.processInfo.environment["LEDGER_TRADE"] ?? "boutique"
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 1000)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 50_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: t, cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: t, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data, faithfulHiring: BalanceTraceTests.faithful)
        }
        var tally: [String: Double] = [:]
        Ledger.observer = { holder, amount in
            guard case .company(let c) = holder, c == id else { return }
            let key = Ledger.cause.map { $0.split(separator: ":", omittingEmptySubsequences: false).prefix(2).joined(separator: ":") } ?? (amount < 0 ? "raw-" : "raw+")
            tally[key, default: 0] += amount
        }
        defer { Ledger.observer = nil }
        let start = e.state.company(id)!.cash
        for _ in 0..<(26 * 7) { e.nextDay(); for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) } }
        print("CAUSE start=\(Int(start)) end=\(Int(e.state.company(id)!.cash))")
        for (k, v) in tally.sorted(by: { $0.key < $1.key }) { print("CAUSE \(Int(v)) \(k)") }
    }
}
