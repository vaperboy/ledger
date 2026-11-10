import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Simulation

final class WealthStatementTests: XCTestCase {
    func game() throws -> GameEngine {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5, story: .fresh, tradeID: "kiosk")
        e.update { s, _, _ in Ledger.move(&s, .me, 5_000_000, why: "Test funds") }
        return e
    }

    func holdIndex(_ e: inout GameEngine, shares: Int, close: Double) {
        e.update { s, _, _ in
            var b = ExchangeBook(s)
            PublicExchange.ensureServerStocks(s, &b)
            b.instruments[PublicExchange.worldIndex]?.close = close
            b.positions[PublicExchange.worldIndex] = ExchangePosition(instrument: PublicExchange.worldIndex, shares: shares, cost: Double(shares) * 90, since: 0)
            b.write(to: &s)
        }
    }

    func testPublicHoldingsCountAtTheLastClose() throws {
        var e = try game()
        let before = e.netWorth
        holdIndex(&e, shares: 1000, close: 120)
        let after = e.netWorth
        XCTAssertEqual(after.exchange, 120_000, accuracy: 0.01)
        XCTAssertEqual(after.total - before.total, 120_000, accuracy: 0.01)
        XCTAssertEqual(after.investments - before.investments, 120_000, accuracy: 0.01)
        XCTAssertEqual(Valuation.netWorth(e.state, trades: e.data.catalog, forGoals: true).exchange, 120_000, accuracy: 0.01)
    }

    func testPrivateCompaniesCountAtADiscountAndTheLinesAddUp() throws {
        var e = try game()
        holdIndex(&e, shares: 1000, close: 100)
        let w = e.wealth
        XCTAssertEqual(w.lines.reduce(0) { $0 + $1.amount }, w.total, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(w.discount, 0)
        XCTAssertEqual(w.total, w.plain.total - w.discount, accuracy: 5)
        XCTAssertEqual(w.plain.companies > 0 ? w.lines.first { $0.id == "private" }.map { $0.amount } ?? 0 : 0,
                       max(0, w.plain.companies - (e.state.rest["stakes"]?.array ?? []).reduce(0) { $0 + $1["val"].double } - GroupStakes.stakesValue(e.state)) * (1 - Wealth.privateDiscount), accuracy: 1)
    }

    func testEveryLineSaysWhatItIs() throws {
        var e = try game()
        holdIndex(&e, shares: 1000, close: 100)
        let w = e.wealth
        XCTAssertFalse(w.lines.isEmpty)
        for l in w.lines { XCTAssertFalse(l.words.isEmpty, l.id); XCTAssertFalse(l.title.isEmpty) }
        XCTAssertTrue(w.summary.hasPrefix("You are worth"))
        XCTAssertTrue(w.lines.contains { $0.id == "exchange" })
        XCTAssertGreaterThan(w.liquidShare, 0)
        XCTAssertLessThanOrEqual(w.liquidShare, 1)
    }

    func testAListedCompanyCountsAtTheCloseLessABlockDiscount() throws {
        var e = try game()
        let id = e.state.companies[0].id
        e.update { s, _, _ in
            _ = PublicExchange.register(&s, companyID: id, value: 50_000_000)
            var b = ExchangeBook(s); b.instruments["co:\(id)"]?.close = 60; b.write(to: &s)
        }
        let w = e.wealth
        let line = try XCTUnwrap(w.lines.first { $0.id == "listed" })
        XCTAssertEqual(line.amount, Double(CapTable.initialShares) * 60 * (1 - Wealth.blockDiscount), accuracy: 1)
        XCTAssertNil(w.lines.first { $0.id == "private" && $0.amount > 0.5 })
    }

    func testTheGoalsReadingNeverCountsMoreThanThePlainOne() throws {
        let e = try game()
        let goals = Wealth.statement(e.state, trades: e.data.catalog, currency: e.homeCurrency, forGoals: true)
        let plain = Wealth.statement(e.state, trades: e.data.catalog, currency: e.homeCurrency)
        XCTAssertLessThanOrEqual(goals.total, plain.total + 0.01)
    }

    func testTheNetWorthGuardStillHoldsAfterBuyingOnTheExchange() throws {
        var e = try game()
        e.placeExchangeOrder(instrument: PublicExchange.worldIndex, side: .buy, shares: 100, limit: 110)
        for _ in 0..<8 { e.nextDay() }
        let queued = e.pendingCelebrations.filter { $0.title.hasPrefix("Net worth") || $0.title == "First million" }
        XCTAssertTrue(queued.isEmpty, "\(queued.map(\.title))")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testTradingResultCountsSoldAndHeldShares() throws {
        var e = try game()
        holdIndex(&e, shares: 100, close: 100)
        e.update { s, _, _ in var b = ExchangeBook(s); b.realised = 500; b.write(to: &s) }
        XCTAssertEqual(PublicExchange.tradingResult(e.state), 500 + 100 * 10, accuracy: 0.01)
        let sub = e.leaderboardSubmission(playerID: "me")
        XCTAssertEqual(sub.tradingResult, 1500, accuracy: 0.01)
        XCTAssertEqual(sub.name, "T")
    }

    func sub(_ id: String, _ nw: Double, _ tr: Double = 0) -> LeaderboardSubmission { LeaderboardSubmission(playerID: id, name: id, week: 1, netWorth: nw, tradingResult: tr) }

    func testTheBoardIsSortedAndMarksYou() {
        let others = (1...30).map { sub("p\($0)", Double($0) * 100) }
        let v = Leaderboards.view(.netWorth, me: sub("me", 1550), others: others)
        XCTAssertEqual(v.count, 31)
        XCTAssertEqual(v.top.count, 10)
        XCTAssertEqual(v.top.first?.id, "p30")
        XCTAssertEqual(v.you?.rank, 16)
        XCTAssertEqual(v.you?.isYou, true)
        XCTAssertEqual(v.around.first { $0.isYou }?.rank, 16)
        XCTAssertLessThanOrEqual(v.around.count, 7)
        XCTAssertEqual(v.around.map { $0.rank }, Array(13...19))
    }

    func testWhenYouAreInTheTopListThereAreNoRowsAround() {
        let v = Leaderboards.view(.tradingResult, me: sub("me", 0, 999), others: [sub("a", 0, 5), sub("b", 0, 1)])
        XCTAssertEqual(v.you?.rank, 1)
        XCTAssertTrue(v.around.isEmpty)
    }

    func testTiesGoByNameAndYourOldRowIsReplaced() {
        let v = Leaderboards.view(.netWorth, me: sub("me", 100), others: [sub("zed", 100), sub("amy", 100), sub("me", 5)])
        XCTAssertEqual(v.count, 3)
        XCTAssertEqual(v.top.map { $0.id }, ["amy", "me", "zed"])
        XCTAssertEqual(v.you?.value, 100)
    }
}
