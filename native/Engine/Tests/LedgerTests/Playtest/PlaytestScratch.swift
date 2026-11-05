import XCTest
import GameCore
import Finance
import Businesses
import Simulation

final class PlaytestScratch: XCTestCase {
    func testScratch() throws {
        try XCTSkipUnless(PT.enabled && PT.env["LEDGER_PT_SCRATCH"] != nil)
        let trade = PT.env["LEDGER_PT_TRADE"] ?? "cafe"
        let bot = try PlayBot(Job(country: PT.env["LEDGER_PT_COUNTRY"] ?? "UK", trade: trade, seed: 1, policy: .competent, scenario: .single, years: 1))
        bot.scenarioSetup()
        for _ in 0..<(40 * 7) { bot.answerAll(); let o = bot.e.nextDay(); if o.completedWeek { bot.tend() } }
        let a = bot.e.state.company(bot.mainID)!
        for m in a.monthlyHistory { print("M rev=\(Int(m.revenue)) profit=\(Int(m.profit)) cash=\(Int(m.cash))") }
        print("BOOKS", a.books.month, a.books.total)
    }
}
