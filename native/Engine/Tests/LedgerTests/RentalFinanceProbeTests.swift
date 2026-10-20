import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Property and finance companies played for three years on three seeds: do they open, keep the books balanced, and earn
/// what such a business realistically earns? The printed table (LEDGER_RF=1) feeds docs/BALANCE_PARITY.md.
final class RentalFinanceProbeTests: XCTestCase {
    struct Year { var revenue = 0.0, profit = 0.0, value = 0.0, cash = 0.0 }
    struct Run {
        var trade: String, seed: Int
        var invested = 0.0
        var years: [Year] = []
        var status = "", staff = 0
        var propertyValue = 0.0, mortgage = 0.0
        var book: FinanceBook? = nil
        var gaps = 0
        var openedWeek = -1
        var loanBalance = 0.0
    }

    /// `well`: a company run properly (the standard team is hired and kept; for finance, the owner puts in the capital the regulator expects).
    static func play(_ trade: String, seed: Int, years: Int = 3, country: String = "UK", fundFactor: Double = 1.6, tweak: ((inout GameEngine, Int) -> Void)? = nil) throws -> Run {
        var e = try GameEngine.newGame(countryCode: country, playerName: "T", seed: seed)
        var run = Run(trade: trade, seed: seed)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 20_000_000_000, why: "Test funds")
            guard case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: .limited, data: data, context: ctx) else { return }
            id = i
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            run.invested = (est?.total ?? 1_000_000) * fundFactor
            Payments.injectCash(&s, companyID: id, amount: run.invested)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        tweak?(&e, id)
        for d in 0..<(years * 52 * 7) {
            e.nextDay()
            for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
            if d % 7 == 6, let co = e.state.company(id), co.status.isLive, co.openedWeek != nil, run.openedWeek < 0 { run.openedWeek = e.state.week }
        }
        guard let co = e.state.company(id), let bd = e.data.catalog[co.type] else { return run }
        let h = co.monthlyHistory
        for y in 0..<years {
            let slice = Array(h.dropFirst(y * 12).prefix(12))
            run.years.append(Year(revenue: slice.reduce(0) { $0 + $1.revenue }, profit: slice.reduce(0) { $0 + $1.profit }, value: 0, cash: slice.last?.cash ?? 0))
        }
        run.years[years - 1].value = Valuation.companyValue(co, state: e.state, trades: e.data.catalog)
        run.status = co.status.rawValue
        run.staff = co.staff.count
        run.propertyValue = co.properties.reduce(0) { $0 + $1.value }
        run.loanBalance = e.state.loans.filter { $0.companyID == id }.reduce(0) { $0 + $1.balance }
        run.book = FinanceModel.book(co, bd, state: e.state)
        run.gaps = Ledger.gaps(e.state).count
        return run
    }

    func testPrintProbe() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_RF"] != nil else { return }
        let only = ProcessInfo.processInfo.environment["LEDGER_TRADES"]?.split(separator: ",").map(String.init)
        for t in ["resrent", "comrent", "parking", "insco", "bank", "fund"] where only == nil || only!.contains(t) {
            for seed in [11, 12, 13] {
                let r = try Self.play(t, seed: seed)
                print("RF \(t) seed \(seed) invested \(Int(r.invested / 1000))k status \(r.status) opened w\(r.openedWeek) staff \(r.staff) gaps \(r.gaps) props \(Int(r.propertyValue / 1000))k loan \(Int(r.loanBalance / 1000))k")
                for (n, y) in r.years.enumerated() {
                    print("RF    y\(n + 1) rev \(Int(y.revenue / 1000))k profit \(Int(y.profit / 1000))k cash \(Int(y.cash / 1000))k value \(Int(y.value / 1000))k")
                }
                if let b = r.book { print("RF    book \(b)") }
            }
        }
    }
}
