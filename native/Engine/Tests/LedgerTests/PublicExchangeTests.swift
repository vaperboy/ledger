import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Simulation

private func order(_ id: Int, _ trader: String, _ side: ExchangeSide, _ shares: Int, _ limit: Double, seq: Int? = nil) -> ExchangeOrder {
    ExchangeOrder(id: id, instrument: "x", trader: trader, side: side, shares: shares, limit: limit, seq: seq ?? id)
}

/// The closing auction and the exchange's price, position, listing and blackout rules.
final class ExchangeRulesTests: XCTestCase {
    func testTheAuctionTradesTheMostSharesAtOnePrice() {
        let r = ExchangeRules.clear([order(1, "a", .buy, 100, 11), order(2, "b", .buy, 100, 10), order(3, "c", .sell, 150, 9.5), order(4, "d", .sell, 100, 10.5)],
                                    reference: 10, low: 8, high: 12)
        // At 10: buyers 200, sellers 150 -> 150 trade. At 10.5: buyers 100, sellers 250 -> 100. At 9.5: buyers 200, sellers 150 -> 150 (same, more surplus on the buy side).
        XCTAssertEqual(r.volume, 150)
        XCTAssertEqual(r.price, 10)
        XCTAssertEqual(r.fills.reduce(0) { $0 + $1.shares }, 150)
        XCTAssertTrue(r.fills.allSatisfy { $0.price == 10 })
        // The highest bidder fills first.
        XCTAssertEqual(r.fills.first?.buyOrder, 1)
    }

    func testNothingTradesWhenTheLimitsDoNotCross() {
        let r = ExchangeRules.clear([order(1, "a", .buy, 100, 9), order(2, "b", .sell, 100, 11)], reference: 10, low: 8, high: 12)
        XCTAssertNil(r.price)
        XCTAssertTrue(r.fills.isEmpty)
    }

    func testNobodyTradesWithThemselves() {
        let r = ExchangeRules.clear([order(1, "me", .buy, 100, 11), order(2, "me", .sell, 100, 9)], reference: 10, low: 8, high: 12)
        XCTAssertTrue(r.fills.isEmpty)
    }

    func testOrdersOutsideTheDayBoundsDoNotSetThePrice() {
        let r = ExchangeRules.clear([order(1, "a", .buy, 100, 20), order(2, "b", .sell, 100, 5)], reference: 10, low: 9, high: 11)
        // Both limits are beyond the bounds, so only the reference is a candidate, and both still trade there.
        XCTAssertEqual(r.price, 10)
        XCTAssertEqual(r.volume, 100)
    }

    func testEarlierOrderTradesFirstAtTheSameLimit() {
        let r = ExchangeRules.clear([order(1, "a", .buy, 100, 10, seq: 5), order(2, "b", .buy, 100, 10, seq: 2), order(3, "c", .sell, 100, 10)], reference: 10, low: 8, high: 12)
        XCTAssertEqual(r.fills.map { $0.buyOrder }, [2])
    }

    func testBandMatchesTheServer() {
        XCTAssertTrue(ExchangeRules.inBand(price: 75, nav: 100))
        XCTAssertTrue(ExchangeRules.inBand(price: 125, nav: 100))
        XCTAssertFalse(ExchangeRules.inBand(price: 74.9999, nav: 100))
        XCTAssertFalse(ExchangeRules.inBand(price: 125.01, nav: 100))
    }

    func testOwnerKeepsAMajority() {
        XCTAssertEqual(ExchangeRules.ownerFloor(total: CapTable.initialShares), 510_000)
        XCTAssertEqual(ExchangeRules.ownerFloor(total: 101), 52)
        XCTAssertEqual(ExchangeRules.ownerSellable(owned: CapTable.initialShares, openSells: 100_000, total: CapTable.initialShares), 390_000)
        XCTAssertEqual(ExchangeRules.ownerSellable(owned: 500_000, openSells: 0, total: CapTable.initialShares), 0)
        XCTAssertEqual(ExchangeRules.holderBuyable(owned: 150_000, openBuys: 20_000, total: CapTable.initialShares), 30_000)
        XCTAssertEqual(ExchangeRules.holderBuyable(owned: 250_000, openBuys: 0, total: CapTable.initialShares), 0)
    }

    func testCloseBoundsFollowThePreviousCloseAndStayInTheBand() {
        let b = ExchangeRules.closeBounds(previous: 100, nav: 100)
        XCTAssertEqual(b.low, 90); XCTAssertEqual(b.high, 110)
        // The value per share fell by half: the band now sits below the old close, so the day's price is pinned to the band's top.
        let f = ExchangeRules.closeBounds(previous: 100, nav: 50)
        XCTAssertEqual(f.low, 62.5); XCTAssertEqual(f.high, 62.5)
    }

    func testListingNeedsAgeAndValue() {
        XCTAssertEqual(ExchangeRules.listingCheck(value: 40, minimum: 30, ageWeeks: 10), .tooYoung(weeksLeft: 16))
        XCTAssertEqual(ExchangeRules.listingCheck(value: 20, minimum: 30, ageWeeks: 30), .tooSmall(needed: 30))
        XCTAssertEqual(ExchangeRules.listingCheck(value: 40, minimum: 30, ageWeeks: 30), .ok)
    }

    func testTheInsiderWindow() {
        let listed = 1000
        XCTAssertNotNil(ExchangeRules.insiderBlock(listedDay: listed, disclosureDay: -1, today: listed + 10))        // lock-up
        XCTAssertNil(ExchangeRules.insiderBlock(listedDay: listed, disclosureDay: -1, today: listed + 40))
        XCTAssertNotNil(ExchangeRules.insiderBlock(listedDay: listed, disclosureDay: -1, today: listed + 85))        // a week before the results
        XCTAssertNotNil(ExchangeRules.insiderBlock(listedDay: listed, disclosureDay: -1, today: listed + 91))        // results day
        XCTAssertNotNil(ExchangeRules.insiderBlock(listedDay: listed, disclosureDay: -1, today: listed + 92))
        XCTAssertNil(ExchangeRules.insiderBlock(listedDay: listed, disclosureDay: -1, today: listed + 93))
        XCTAssertNotNil(ExchangeRules.insiderBlock(listedDay: listed, disclosureDay: listed + 50, today: listed + 52))   // after a dividend
        XCTAssertNil(ExchangeRules.insiderBlock(listedDay: listed, disclosureDay: listed + 50, today: listed + 53))
        XCTAssertEqual(ExchangeRules.nextResultsDay(listedDay: listed, today: listed + 5), listed + 91)
    }
}

final class PublicExchangeTests: XCTestCase {
    func game() throws -> GameEngine {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5, story: .fresh, tradeID: "kiosk")
        e.update { s, _, _ in Ledger.move(&s, .me, 5_000_000, why: "Test funds") }
        return e
    }

    /// Runs the exchange for the close of a Monday.
    func closeMonday(_ e: inout GameEngine, value: Double = 50_000_000) {
        e.update { s, _, ctx in
            s.day = 1
            var b = ExchangeBook(s); b.lastRun = -1; b.write(to: &s)
            PublicExchange.runDay(&s, context: ctx, holdingValue: { _ in value })
        }
    }

    func testAServerStockTradesAtTheCloseAndTheBooksStayBalanced() throws {
        var e = try game()
        let cash0 = e.state.cash
        let r = e.placeExchangeOrder(instrument: PublicExchange.worldIndex, side: .buy, shares: 100, limit: 120)
        guard case .placed = r else { return XCTFail("\(r)") }
        for _ in 0..<8 { e.nextDay() }
        let pos = try XCTUnwrap(ExchangeBook(e.state).positions[PublicExchange.worldIndex])
        XCTAssertEqual(pos.shares, 100)
        XCTAssertLessThan(e.state.cash, cash0)
        XCTAssertTrue(ExchangeBook(e.state).orders.isEmpty)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        // It counts in net worth at the last close.
        let close = try XCTUnwrap(ExchangeBook(e.state).instruments[PublicExchange.worldIndex]).close
        XCTAssertEqual(e.netWorth.exchange, 100 * close, accuracy: 0.01)
        XCTAssertEqual(Valuation.netWorth(e.state, trades: e.data.catalog, forGoals: true).exchange, e.netWorth.exchange, accuracy: 0.01)
    }

    func testBuyingServerSharesCostsOnlyTheFeeInNetWorth() throws {
        var e = try game()
        let before = e.netWorth.total
        e.placeExchangeOrder(instrument: PublicExchange.worldIndex, side: .buy, shares: 200, limit: 125)
        e.update { s, _, ctx in
            s.day = 1
            PublicExchange.runDay(&s, context: ctx, holdingValue: { _ in nil })
        }
        let pos = ExchangeBook(e.state).positions[PublicExchange.worldIndex]
        XCTAssertEqual(pos?.shares, 200)
        // Whatever the daily wobble of the price, 200 shares cost what they are worth at the close, plus a small fee: no jump in net worth.
        XCTAssertLessThan(abs(e.netWorth.total - before), 0.01 * 200 * 100 + 200)
    }

    func testOrdersAreRefusedOutsideTheBandAndBeyondMeans() throws {
        var e = try game()
        XCTAssertEqual(e.placeExchangeOrder(instrument: PublicExchange.worldIndex, side: .buy, shares: 10, limit: 200), .refused(.outsideBand(low: 75, high: 125)))
        XCTAssertEqual(e.placeExchangeOrder(instrument: PublicExchange.worldIndex, side: .sell, shares: 10, limit: 100), .refused(.tooMany(canSell: 0)))
        XCTAssertEqual(e.placeExchangeOrder(instrument: "nope", side: .buy, shares: 10, limit: 100), .refused(.unknown))
        XCTAssertEqual(e.placeExchangeOrder(instrument: PublicExchange.worldIndex, side: .buy, shares: 0, limit: 100), .refused(.invalid))
        guard case .refused(.notEnoughCash) = e.placeExchangeOrder(instrument: PublicExchange.worldIndex, side: .buy, shares: 100_000, limit: 100) else { return XCTFail("cash") }
    }

    func testAnOrderCanBeCancelled() throws {
        var e = try game()
        guard case .placed(let id) = e.placeExchangeOrder(instrument: PublicExchange.worldIndex, side: .buy, shares: 10, limit: 100) else { return XCTFail() }
        XCTAssertEqual(e.exchangeOrders.count, 1)
        XCTAssertTrue(e.cancelExchangeOrder(id: id))
        XCTAssertTrue(e.exchangeOrders.isEmpty)
    }

    func testNoAuctionOnTheWeekendAndOnlyOnceADay() throws {
        var e = try game()
        e.placeExchangeOrder(instrument: PublicExchange.worldIndex, side: .buy, shares: 100, limit: 120)
        e.update { s, _, ctx in
            s.day = 6   // Saturday's close is not a trading day
            PublicExchange.runDay(&s, context: ctx, holdingValue: { _ in nil })
        }
        XCTAssertEqual(ExchangeBook(e.state).orders.count, 1)
        e.update { s, _, ctx in
            s.day = 1
            PublicExchange.runDay(&s, context: ctx, holdingValue: { _ in nil })
            PublicExchange.runDay(&s, context: ctx, holdingValue: { _ in nil })   // the same day again changes nothing
        }
        XCTAssertTrue(ExchangeBook(e.state).orders.isEmpty)
        XCTAssertEqual(ExchangeBook(e.state).positions[PublicExchange.worldIndex]?.shares, 100)
    }

    func testSellingServerSharesPaysTheGainTax() throws {
        var e = try game()
        e.update { s, _, _ in
            var b = ExchangeBook(s)
            PublicExchange.ensureServerStocks(s, &b)
            b.positions[PublicExchange.worldIndex] = ExchangePosition(instrument: PublicExchange.worldIndex, shares: 500, cost: 1, since: 0)
            b.write(to: &s)
        }
        let cash0 = e.state.cash, gains0 = e.state.tax.gains
        guard case .placed = e.placeExchangeOrder(instrument: PublicExchange.worldIndex, side: .sell, shares: 500, limit: 80) else { return XCTFail() }
        e.update { s, _, ctx in s.day = 1; PublicExchange.runDay(&s, context: ctx, holdingValue: { _ in nil }) }
        XCTAssertNil(ExchangeBook(e.state).positions[PublicExchange.worldIndex])
        XCTAssertGreaterThan(e.state.tax.gains, gains0)
        XCTAssertGreaterThan(e.state.cash, cash0 - 1)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testTheWorldBankPaysAQuarterlyDividendToEarlierHolders() throws {
        var e = try game()
        e.update { s, _, ctx in
            var b = ExchangeBook(s)
            PublicExchange.ensureServerStocks(s, &b)
            b.positions[PublicExchange.worldBank] = ExchangePosition(instrument: PublicExchange.worldBank, shares: 1000, cost: 100_000, since: 0)
            b.write(to: &s)
            s.week = 13; s.day = 3
            let before = s.stats.dividendsReceived
            PublicExchange.runDay(&s, context: ctx, holdingValue: { _ in nil })
            XCTAssertGreaterThan(s.stats.dividendsReceived, before)
        }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    // MARK: A holding of your own on the exchange

    func listed(_ e: inout GameEngine, listedDay: Int = -1020) throws -> Int {
        let id = e.state.companies[0].id
        e.update { s, _, _ in
            XCTAssertTrue(PublicExchange.register(&s, holdingID: id, value: 50_000_000))
            var b = ExchangeBook(s); b.instruments["co:\(id)"]?.listedDay = listedDay; b.write(to: &s)
        }
        return id
    }

    func testTheOwnerSellsDownToAMajorityAndNoFurther() throws {
        var e = try game()
        let id = try listed(&e)
        let key = "co:\(id)"
        XCTAssertEqual(e.placeExchangeOrder(instrument: key, side: .sell, shares: 500_000, limit: 50), .refused(.tooMany(canSell: 490_000)))
        XCTAssertEqual(e.placeExchangeOrder(instrument: key, side: .buy, shares: 10, limit: 50), .refused(.ownShares))
        guard case .placed = e.placeExchangeOrder(instrument: key, side: .sell, shares: 490_000, limit: 45) else { return XCTFail() }
        // 490 000 are already promised: nothing more can be offered.
        XCTAssertEqual(e.placeExchangeOrder(instrument: key, side: .sell, shares: 1, limit: 45), .refused(.tooMany(canSell: 0)))
    }

    func testAnOwnerSaleMovesSharesToTheMarketAndMoneyToTheOwner() throws {
        var e = try game()
        let id = try listed(&e)
        let key = "co:\(id)"
        let cash0 = e.state.cash
        guard case .placed = e.placeExchangeOrder(instrument: key, side: .sell, shares: 10_000, limit: 40) else { return XCTFail() }
        closeMonday(&e)
        let table = CapTable.table(try XCTUnwrap(e.state.company(id)))
        let sold = CapTable.initialShares - table.you
        XCTAssertGreaterThan(sold, 0)
        XCTAssertLessThanOrEqual(sold, 10_000)
        XCTAssertEqual(table.holders.first { $0.name == "Exchange investors" }?.shares, sold)
        XCTAssertGreaterThan(e.state.cash, cash0)
        let inst = try XCTUnwrap(ExchangeBook(e.state).instruments[key])
        XCTAssertEqual(inst.volume, sold)
        XCTAssertTrue((ExchangeRules.band(nav: inst.nav).low...ExchangeRules.band(nav: inst.nav).high).contains(inst.close))
        // What is left of the order is still on the book for tomorrow.
        XCTAssertEqual(ExchangeBook(e.state).orders.reduce(0) { $0 + $1.shares }, 10_000 - sold)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        // The shares left are not double counted: the stake is valued once, in the company.
        XCTAssertEqual(e.netWorth.exchange, 0)
    }

    func testTheLockUpAndTheBlackoutKeepTheOwnerOut() throws {
        var e = try game()
        let id = try listed(&e, listedDay: PublicExchange.today(e.state))
        let key = "co:\(id)"
        guard case .refused(.insider) = e.placeExchangeOrder(instrument: key, side: .sell, shares: 100, limit: 50) else { return XCTFail("lock-up") }
        // An order that was placed before a blackout waits, and does not trade in it.
        e.update { s, _, _ in var b = ExchangeBook(s); b.instruments[key]?.listedDay = -1020; b.write(to: &s) }
        guard case .placed = e.placeExchangeOrder(instrument: key, side: .sell, shares: 100, limit: 40) else { return XCTFail() }
        e.update { s, _, _ in var b = ExchangeBook(s); b.instruments[key]?.dividendDay = PublicExchange.today(s); b.write(to: &s) }
        closeMonday(&e)
        XCTAssertEqual(CapTable.table(try XCTUnwrap(e.state.company(id))).you, CapTable.initialShares)
        XCTAssertEqual(ExchangeBook(e.state).orders.count, 1)
    }

    func testTheValueReportMovesAtMostATenthADay() throws {
        var e = try game()
        let id = try listed(&e)
        closeMonday(&e, value: 500_000_000)
        let inst = try XCTUnwrap(ExchangeBook(e.state).instruments["co:\(id)"])
        XCTAssertEqual(inst.nav, 55, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(inst.close, ExchangeRules.band(nav: inst.nav).high)
        XCTAssertLessThanOrEqual(inst.close, 55)   // the close moves at most a tenth from 50
    }

    func testOrdersLeftOutsideTheBandByAValueReportAreCancelled() throws {
        var e = try game()
        let id = try listed(&e)
        guard case .placed = e.placeExchangeOrder(instrument: "co:\(id)", side: .sell, shares: 100, limit: 62) else { return XCTFail() }
        closeMonday(&e, value: 20_000_000)   // value per share falls to 45 at most, so the band tops out at 56.25
        XCTAssertTrue(ExchangeBook(e.state).orders.isEmpty)
    }

    func testDividendRules() throws {
        var e = try game()
        let id = e.state.companies[0].id
        XCTAssertEqual(e.declareExchangeDividend(holdingID: id, amount: 100), .notListed)
        _ = try listed(&e)
        XCTAssertEqual(e.declareExchangeDividend(holdingID: id, amount: 0), .nothingToPay)
        e.update { s, _, _ in s.week = 20; var b = ExchangeBook(s); b.instruments["co:\(id)"]?.dividendDay = PublicExchange.today(s) - 10; b.write(to: &s) }
        XCTAssertEqual(e.declareExchangeDividend(holdingID: id, amount: 100), .tooSoon(daysLeft: 81))
    }

    func testAGoneCompanyHaltsTrading() throws {
        var e = try game()
        let id = try listed(&e)
        guard case .placed = e.placeExchangeOrder(instrument: "co:\(id)", side: .sell, shares: 100, limit: 50) else { return XCTFail() }
        e.update { s, _, ctx in
            s.day = 1
            PublicExchange.runDay(&s, context: ctx, holdingValue: { _ in 0 })
        }
        XCTAssertTrue(ExchangeBook(e.state).instruments["co:\(id)"]?.halted ?? false)
        XCTAssertTrue(ExchangeBook(e.state).orders.isEmpty)
        XCTAssertEqual(e.placeExchangeOrder(instrument: "co:\(id)", side: .sell, shares: 10, limit: 50), .refused(.halted))
    }

    func testTheExchangeSurvivesASaveRoundTrip() throws {
        var e = try game()
        e.placeExchangeOrder(instrument: PublicExchange.worldIndex, side: .buy, shares: 100, limit: 110)
        let data = try JSONEncoder().encode(e.state)
        let back = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(ExchangeBook(back), ExchangeBook(e.state))
    }

    func testMarketRowsListTheServerStocks() throws {
        var e = try game()
        e.placeExchangeOrder(instrument: PublicExchange.worldIndex, side: .buy, shares: 10, limit: 100)
        let rows = e.exchangeMarket
        XCTAssertEqual(Set(rows.filter { $0.kind == "srv" }.map { $0.id }), [PublicExchange.worldBank, PublicExchange.worldIndex])
        XCTAssertEqual(Set(rows.filter { $0.kind == "com" }.map { $0.id }), Set(["materials", "fuel", "power", "oil", "salmon"].map { PublicExchange.commodityID($0) }))
        XCTAssertEqual(rows.count, 7)
        XCTAssertTrue(rows.allSatisfy { $0.low < $0.nav && $0.nav < $0.high })
    }
}
