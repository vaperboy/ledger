import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Investments
import Simulation

final class MarketAppTests: XCTestCase {
    private func position(_ e: GameEngine, _ id: String) throws -> PortfolioPosition { try XCTUnwrap(e.portfolio.positions.first { $0.id == id }, "no position \(id)") }

    func testFundBuyPriceMoveAndSellResults() throws {
        var e = try ChainsTests.engine("UK")
        let cur = e.homeCurrency
        let q = e.marketQuote(asset: "fund:idx", owner: .player, amount: 50_000)
        XCTAssertNil(q.refusal)
        let fee = Brokerage.brokerFee(50_000, currency: cur)
        XCTAssertEqual(q.fee, fee, accuracy: 1e-9)
        XCTAssertEqual(q.cashChange, -(50_000 + fee), accuracy: 1e-9)
        let before = e.state.cash
        let r = e.marketBuy(asset: "fund:idx", owner: .player, amount: 50_000)
        XCTAssertTrue(r.done, r.refusal ?? "")
        XCTAssertEqual(r.cashChange, -(50_000 + fee), accuracy: 1e-6)
        XCTAssertEqual(e.state.cash, before - 50_000 - fee, accuracy: 1e-6)

        var p = try position(e, "me:fund:idx")
        XCTAssertEqual(p.costBasis, 50_000 + fee, accuracy: 1e-6)
        XCTAssertEqual(p.value, 50_000, accuracy: 1e-6)
        XCTAssertEqual(p.pnl, -fee, accuracy: 1e-6)
        XCTAssertEqual(p.pnlWeek, 0, "units bought this week have not lived through a price move")
        XCTAssertEqual(p.allocation, 1, accuracy: 1e-9)

        e.update { s, _, _ in let px = Brokerage.price(s, .fund, "idx"); s.rest["fundPx"]?["idx"] = .number(px * 1.1) }
        p = try position(e, "me:fund:idx")
        XCTAssertEqual(p.value, 55_000, accuracy: 1e-6)
        XCTAssertEqual(p.pnl, 5_000 - fee, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(p.pnlPercent), (5_000 - fee) / (50_000 + fee), accuracy: 1e-9)
        XCTAssertEqual(e.portfolio.totals.pnl, p.pnl, accuracy: 1e-6)

        let gainsBefore = e.state.tax.gains
        let sq = e.marketSellQuote(position: p.id, units: p.units / 2)
        XCTAssertNil(sq.refusal)
        let fee2 = Brokerage.brokerFee(27_500, currency: cur)
        XCTAssertEqual(sq.cashChange, 27_500 - fee2, accuracy: 1e-6)
        XCTAssertEqual(sq.realizedGain, 27_500 - fee2 - (50_000 + fee) / 2, accuracy: 1e-6)
        let s = e.marketSell(position: p.id, units: p.units / 2)
        XCTAssertTrue(s.done, s.refusal ?? "")
        XCTAssertEqual(s.cashChange, sq.cashChange, accuracy: 1e-6)
        XCTAssertEqual(e.state.tax.gains - gainsBefore, sq.realizedGain, accuracy: 1e-6)
        p = try position(e, "me:fund:idx")
        XCTAssertEqual(p.costBasis, (50_000 + fee) / 2, accuracy: 1e-6)
        XCTAssertEqual(p.value, 27_500, accuracy: 1e-6)

        XCTAssertTrue(e.marketSell(position: p.id, amount: 1e12).done)
        XCTAssertNil(e.portfolio.positions.first { $0.id == "me:fund:idx" })
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testWeekResultCountsOnlyUnitsThatLivedThroughTheMove() throws {
        var e = try ChainsTests.engine("UK")
        XCTAssertTrue(e.marketBuy(asset: "fund:idx", owner: .player, amount: 80_000).done)
        ChainsTests.play(&e, days: 7)
        let h = Markets.fundHistory(e.state, "idx")
        XCTAssertGreaterThanOrEqual(h.count, 1)
        let p = try position(e, "me:fund:idx")
        if h.count >= 2 { XCTAssertEqual(p.pnlWeek, p.units * (h[h.count - 1] - h[h.count - 2]), accuracy: 1e-6) }
        ChainsTests.play(&e, days: 7)
        let h2 = Markets.fundHistory(e.state, "idx")
        XCTAssertGreaterThanOrEqual(h2.count, 2)
        let p1 = try position(e, "me:fund:idx")
        XCTAssertEqual(p1.pnlWeek, p1.units * (h2[h2.count - 1] - h2[h2.count - 2]), accuracy: 1e-6)
        XCTAssertNotEqual(p1.pnlWeek, 0)
        XCTAssertEqual(e.state.day, 0)
        XCTAssertEqual(p1.pnlToday, p1.pnlWeek, accuracy: 1e-9, "prices move on day 0")
        XCTAssertEqual(p1.history, h2)
        XCTAssertTrue(e.marketBuy(asset: "fund:idx", owner: .player, amount: 80_000).done)
        let p2 = try position(e, "me:fund:idx")
        XCTAssertEqual(p2.pnlWeek, p1.pnlWeek, accuracy: 1e-6)
        ChainsTests.play(&e, days: 1)
        XCTAssertEqual(try position(e, "me:fund:idx").pnlToday, 0, "no price move on other days")
        XCTAssertGreaterThanOrEqual(e.portfolio.history.count, 2)
    }

    func testCryptoSpreadAndFeeAreInTheResult() throws {
        var e = try ChainsTests.engine("UK")
        let q = e.marketQuote(asset: "crypto:BTC", owner: .player, amount: 100_000)
        XCTAssertNil(q.refusal)
        XCTAssertEqual(q.fee, 400, accuracy: 1e-9)
        XCTAssertEqual(q.units, 100_000 / (q.price * 1.008), accuracy: 1e-12)
        XCTAssertEqual(q.spreadCost, 100_000 - q.units * q.price, accuracy: 1e-6)
        XCTAssertTrue(e.marketBuy(asset: "crypto:BTC", owner: .player, amount: 100_000).done)
        let p = try position(e, "me:crypto:BTC")
        XCTAssertEqual(p.pnl, -(q.fee + q.spreadCost), accuracy: 1e-6)
        let sq = e.marketSellQuote(position: p.id, units: p.units)
        XCTAssertEqual(sq.cashChange, p.value * 0.992 * (1 - 0.004), accuracy: 1e-6)
        XCTAssertTrue(e.marketSell(position: p.id, units: p.units).done)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testRefusals() throws {
        var e = try ChainsTests.engine("UK")
        XCTAssertNotNil(e.marketQuote(asset: "stock:TECH", owner: .player, amount: 10_000).refusal, "single-company shares are not offered")
        XCTAssertNotNil(e.marketQuote(asset: "fund:idx", owner: .player, amount: 1).refusal, "below the smallest order")
        XCTAssertNotNil(e.marketQuote(asset: "fund:nope", owner: .player, amount: 10_000).refusal)
        XCTAssertNotNil(e.marketQuote(asset: "fund:idx", owner: .player, amount: 1e15).refusal, "more than the accounts hold")
        XCTAssertFalse(e.marketBuy(asset: "stock:TECH", owner: .player, amount: 10_000).done)
        XCTAssertNotNil(e.marketSellQuote(position: "me:fund:idx", units: 1).refusal, "nothing held")
        XCTAssertEqual(e.marketOwners.map { $0.owner }, [.player])
    }

    func testOldSavesGetTheirCurrentValueAsCostBasis() throws {
        var e = try ChainsTests.engine("UK")
        XCTAssertTrue(e.marketBuy(asset: "fund:mm", owner: .player, amount: 30_000).done)
        e.update { s, _, _ in s.rest["inv"]?["funds"]["mm"]["cost"] = .null }
        let saved = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(e.state))
        let loaded = GameEngine(state: saved, data: e.data, events: e.events, marketing: e.marketing)
        let me = try position(loaded, "me:fund:mm")
        XCTAssertEqual(me.pnl, 0, accuracy: 0.01)
    }

    func testCompanyAgainstItsMarket() throws {
        var e = try ChainsTests.engine("UK")
        let cafe = ChainsTests.start(&e, "cafe")
        ChainsTests.play(&e, days: 7 * 10)
        let m = try XCTUnwrap(e.marketPosition(companyID: cafe))
        XCTAssertEqual(m.companyID, cafe)
        XCTAssertFalse(m.national)
        XCTAssertGreaterThan(m.of, 1, "the market has rivals")
        XCTAssertTrue((1...m.of).contains(m.rank))
        XCTAssertEqual(m.competitors.count, m.of)
        XCTAssertEqual(m.competitors.reduce(0) { $0 + $1.share }, 1, accuracy: 1e-6)
        XCTAssertEqual(m.competitors.map { $0.revenue }, m.competitors.map { $0.revenue }.sorted(by: >))
        XCTAssertEqual(m.competitors[m.rank - 1].companyID, cafe)
        let priced = m.competitors.compactMap { $0.priceIndex }
        XCTAssertEqual(priced.count, m.of)
        XCTAssertEqual(priced.reduce(0, +) / Double(priced.count), 1, accuracy: 1e-9, "the price index is against the market's mean")
        XCTAssertLessThanOrEqual(m.topRivals.count, 3)
        XCTAssertFalse(m.topRivals.contains { $0.isYours })
        XCTAssertEqual(m.share, m.competitors[m.rank - 1].share, accuracy: 1e-12)
        if let mr = m.marketRating, let r = m.rating { XCTAssertEqual(try XCTUnwrap(m.ratingVsMarket), r - mr, accuracy: 1e-9) }
        XCTAssertFalse(m.shareHistory.isEmpty, "a month has ended")

        let rivals = e.marketRivals()
        XCTAssertFalse(rivals.isEmpty)
        XCTAssertTrue(rivals.allSatisfy { $0.companyID == cafe && $0.valuation > 0 })
        let rid = rivals[0].id
        XCTAssertEqual(e.rivalValue(companyID: cafe, rivalID: rid), rivals[0].valuation)
        XCTAssertTrue(e.toggleWatch(rivalID: rid))
        XCTAssertEqual(e.watchlist.map { $0.id }, [rid])
        XCTAssertTrue(e.marketRivals().first { $0.id == rid }?.watched == true)
        XCTAssertFalse(e.toggleWatch(rivalID: rid))
        XCTAssertTrue(e.watchlist.isEmpty)
        XCTAssertFalse(e.toggleWatch(rivalID: -1), "a rival not in your markets cannot be starred")

        let o = e.marketOverview
        XCTAssertEqual(o.markets, 1)
        XCTAssertEqual(try XCTUnwrap(o.combinedShare), m.share, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(o.opportunities.count, 3)
        let countries = e.marketCountries()
        XCTAssertEqual(countries.count, e.data.countries.countries.count)
        XCTAssertTrue(countries[0].isHome)
        XCTAssertEqual(countries[0].yourCompanies, 1)
        let home = e.state.homeCountryCode
        let cities = e.marketCities(countryCode: home, tradeID: "cafe")
        XCTAssertFalse(cities.isEmpty)
        XCTAssertTrue(cities.allSatisfy { $0.rivals != nil && $0.tradeDemandLevel != nil })
        XCTAssertEqual(cities.first { $0.id == e.state.company(cafe)?.cityID }?.yourCompanies, 1)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }
}
