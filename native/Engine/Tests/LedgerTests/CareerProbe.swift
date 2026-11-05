import XCTest
import Finance
import GameCore
import Businesses
import Countries
@testable import Simulation

/// Policy comparison (LEDGER_PLAYTEST=1): does skill matter? Prints wealth built per policy at the end of years 1 to 3.
final class CareerProbe: XCTestCase {
    func run(_ code: String, _ trade: String, ads: Int, price: Double, expand: Bool) throws -> String {
        var e = try GameEngine.newGame(countryCode: code, playerName: "T", seed: 7, story: .fresh, tradeID: trade, companyName: "T")
        let id = e.state.companies[0].id
        let cur = e.homeCurrency
        _ = e.setPriceLevel(companyID: id, level: price)
        let channels = ["google", "meta", "seo"].filter { e.marketing.channels[$0] != nil }
        if ads > 0 { for k in channels.prefix(1) { if let ch = e.marketing.channels[k], ch.budgetOptions.count > ads { _ = e.setCampaign(companyID: id, channel: k, weeklyBudget: ch.budgetOptions[ads]) } } }
        let nw0 = Valuation.netWorth(e.state, trades: e.data.catalog).total
        var out: [String] = []
        var broke = false
        for d in 1...1092 {
            e.nextDay()
            for m in e.openDecisions where !m.options.isEmpty { _ = e.answer(messageID: m.id, option: 0) }
            if expand, d % 28 == 0, Gates.companiesOwned(e.state) < 3, e.state.companies.filter({ $0.status.isLive }).allSatisfy({ $0.cash > cur.scaledPrice(400_000) }) {
                e.update { s, _, _ in Ledger.move(&s, .me, cur.scaledPrice(150_000), why: "Test funds") }
                _ = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, form: .limited, name: "T\(d)", fundWith: cur.scaledPrice(150_000))
            }
            if e.state.isGameOver { broke = true; break }
            if d % 364 == 0 { out.append(cur.short(Valuation.netWorth(e.state, trades: e.data.catalog).total - nw0)) }
        }
        return out.joined(separator: " / ") + (broke ? " BROKE wk \(e.state.week)" : "") + " n=\(Gates.companiesOwned(e.state)) rank=\(e.careerStatus.rank.title) goals=\(Career.goalsDone(e.state))"
    }

    func testPolicies() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_PLAYTEST"] == "1" else { throw XCTSkip("set LEDGER_PLAYTEST=1") }
        for (c, t) in [("UK", "cafe"), ("DE", "bakery"), ("US", "barber")] {
            for (name, ads, price, exp) in [("idle", 0, 0.0, false), ("ads1", 1, 0.0, false), ("ads1+price+1", 1, 1.0, false), ("price-1", 0, -1.0, false), ("price+1", 0, 1.0, false), ("ads2+expand", 2, 0.0, true)] {
                print("POLICY", c, t, name, try run(c, t, ads: ads, price: price, expand: exp))
            }
        }
    }
}
