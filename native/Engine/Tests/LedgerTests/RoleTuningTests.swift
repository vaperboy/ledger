import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

final class RoleTuningTests: XCTestCase {
    struct Measure { var value: Double; var wage: Double; var revenue: Double }

    private func settled(_ seed: Int, trade: String, size: Double) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 400_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, data: data, context: ctx) { id = i }
            if let i = s.companyIndex(id) { s.companies[i].size = size }
            Payments.injectCash(&s, companyID: id, amount: 300_000_000)
            _ = CompanySetup.quickSetupReport(&s, companyID: id, data: data, options: CompanySetup.SetupOptions(optionalEquipment: true))
            if let i = s.companyIndex(id) {
                s.companies[i].status = .open; s.companies[i].ownerHours = 40
                var mkt = s.companies[i].value("mkt")
                mkt["meta"] = .object(["b": .number(World(state: s, data: data).currency(s.companies[i]).scaledPrice(1500)), "since": .number(Double(s.week)), "lock": .number(Double(s.week))])
                s.companies[i].set("mkt", mkt)
            }
        }
        guard id != 0, e.state.company(id)?.staff.isEmpty == false else { throw XCTSkip("no company") }
        return (e, id)
    }

    func measure(role: String, trade: String, size: Double, seeds: [Int], weeks: Int = 52) -> Measure? {
        var v = 0.0, w = 0.0, r = 0.0, n = 0.0
        for seed in seeds {
            guard let (base, id) = try? settled(seed, trade: trade, size: size) else { continue }
            var with = base, without = base
            with.update { s, _, _ in
                guard let i = s.companyIndex(id), let k = s.companies[i].staff.indices.first else { return }
                var st = s.companies[i].staff; st[k].set("duty", role); s.companies[i].staff = st
            }
            for _ in 0..<(7 * weeks) { with.nextDay(); without.nextDay() }
            v += with.state.company(id)!.cash - without.state.company(id)!.cash
            r += without.state.company(id)!.monthlyHistory.suffix(12).reduce(0) { $0 + $1.revenue }
            let co = base.state.company(id)!
            let factor = base.data.countries[co.countryCode]?.employerCostFactor ?? 1
            w += Hiring.marketWage(role: role, company: co, state: base.state, data: base.data) * 12 * factor
            n += 1
        }
        return n == 0 ? nil : Measure(value: v / n, wage: w / n, revenue: r / n)
    }

    func testRolesPayForThemselvesModestly() throws {
        let full = ProcessInfo.processInfo.environment["ROLE_TUNING"] == "full"
        let seeds = full ? [1, 2, 3, 4, 5, 6] : [1, 2]
        let table: [(role: String, trades: [String])] = [
            ("guard", full ? ["grocery", "boutique", "hardware"] : ["grocery"]), ("marketer", ["cafe", "grocery"]), ("recept", ["cafe", "grocery"]),
        ]
        for (role, trades) in table {
            for trade in trades {
                for size in (full ? [0.5, 1.0, 2.0] : [0.5, 2.0]) {
                    guard let m = measure(role: role, trade: trade, size: size, seeds: seeds) else { continue }
                    let net = m.wage > 0 ? (m.value - m.wage) / m.wage : 0
                    if role == "guard" && trade == "grocery" && size == 2.0 { XCTAssertGreaterThan(net, -0.1, "a guard pays for himself in a big shop") }
                    print("ROLE \(role) \(trade) size \(size): value \(Int(m.value)) wage \(Int(m.wage)) revenue \(Int(m.revenue)) net \(String(format: "%.0f", net * 100))%")
                }
            }
        }
    }
}
