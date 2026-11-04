import XCTest
import GameCore
import Businesses
import Simulation

/// LEDGER_P2=trade1,trade2: the standard two-year probe (UK, seed LEDGER_SEED or 11, BalanceProbeTests.play owner).
/// Prints money in, profit year 1 and 2, value, cash, status, staff.
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
