import XCTest
import GameCore
import Businesses
import Simulation
import Events
import Finance
import Countries

final class BalanceCausesProbe: XCTestCase {
    func testTwoYearProbe() throws {
        guard let list = ProcessInfo.processInfo.environment["LEDGER_P2"] else { return }
        let seed = Int(ProcessInfo.processInfo.environment["LEDGER_SEED"] ?? "11")!
        for t in list.split(separator: ",").map(String.init) {
            guard let o = try BalanceProbeTests.play(trade: t, seed: seed, years: Int(ProcessInfo.processInfo.environment["LEDGER_YEARS"] ?? "2")!) else { print("P2 \(t) no run"); continue }
            print(String(format: "P2 %@ | invested %.0f | y1 %.0f | y2 %.0f | value %.0f | cash %.0f | %@ | staff %d", t, o.invested, o.profitY1, o.profitY3, o.value, o.cash, o.status, o.staff))
        }
    }
}

extension BalanceCausesProbe {
    func testFoundedStartupProbe() throws {
        guard let spec = ProcessInfo.processInfo.environment["LEDGER_STARTUP"] else { return }
        let a = spec.split(separator: ",").map(String.init)
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: Int(ProcessInfo.processInfo.environment["LEDGER_SEED"] ?? "11")!)
        e.update { s, _, _ in Ledger.move(&s, .me, 20_000_000_000, why: "Test funds") }
        let r = e.foundStartup(name: nil, sector: a[0], product: a[1], model: a[2], who: a[3], seedMultiple: Double(a[4])!)
        print("ST found:", r)
        guard let f0 = e.foundedStartups.first, let sec = StartupProducts.sector(a[0]) else { return }
        var launched = -1
        let years = Int(ProcessInfo.processInfo.environment["LEDGER_YEARS"] ?? "2")!
        for day in 0..<(years * 364) {
            e.nextDay()
            if day % 7 == 6, launched < 0, let f = e.foundedStartups.first(where: { $0.id == f0.id }), f.product?.phase == "ready" {
                let price = e.state.company(f0.companyID).map { World(state: e.state, data: e.data).currency($0).scaledPrice(sec.arpu) / 12 } ?? 1
                e.update { s, _, _ in _ = Startups.launch(&s, startupID: f0.id, price: price) }
                launched = day / 7
            }
            if day % 56 == 55, let co = e.state.company(f0.companyID) {
                let w = e.state.rest["founded"]?.array.first { $0["cid"].int == f0.companyID }?["sw16"]
                print("ST w\(day / 7 + 1) \(co.status.rawValue) staff=\(co.staff.count) cash=\(Int(co.cash / 1000))k phase=\(w?["phase"].string ?? "-") prog=\(String(format: "%.2f", w?["prog"].double ?? 0)) cust=\(Int(w?["cust"].double ?? 0)) revW=\(Int((w?["revW"].double ?? 0) / 1000))k")
            }
        }
        if let co = e.state.company(f0.companyID) { print("ST end launchedWeek=\(launched) status=\(co.status.rawValue) cash=\(Int(co.cash / 1000))k monthly profit k:", co.monthlyHistory.map { Int($0.profit / 1000) }) }
    }
}
