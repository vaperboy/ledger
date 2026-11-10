import XCTest
import GameCore
import Finance
@testable import Businesses
@testable import Events
@testable import Simulation

final class PublicCompanyTests: XCTestCase {
    private func bigCompany() throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5, story: .fresh, tradeID: "kiosk")
        let id = e.state.companies[0].id
        e.update { s, _, _ in
            Ledger.move(&s, .me, 5_000_000, why: "Test funds")
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].status = .open
            s.companies[i].foundedWeek = s.week - 200
            s.companies[i].monthlyHistory = (0..<12).map { MonthRecord(monthIndex: $0, revenue: 40_000_000, profit: 12_000_000, cash: 0) }
        }
        return (e, id)
    }

    private func quarterDay(_ e: inout GameEngine, id: Int) {
        e.update { s, d, c in
            var b = ExchangeBook(s)
            b.instruments[PublicExchange.id(of: id)]?.listedDay = PublicExchange.today(s) - ExchangeRules.quarterDays
            b.write(to: &s)
            PublicCompany.results(&s, data: d, context: c)
        }
    }

    func testGoingPublicSellsAStakeAtADiscountAndKeepsControl() throws {
        var (e, id) = try bigCompany()
        let q = try XCTUnwrap(e.saleQuote(companyID: id, percent: 30, method: .ipo))
        XCTAssertNil(q.problem, q.problem ?? "")
        let o = try XCTUnwrap(PublicCompany.offering(e.state, companyID: id, pct: 30, data: e.data, context: e.context))
        XCTAssertEqual(o.offerPrice / o.sharePrice, 1 - PublicCompany.discount, accuracy: 0.001)
        let cash0 = e.state.cash
        XCTAssertEqual(e.startSale(companyID: id, percent: 30, method: .ipo), .started)
        XCTAssertTrue(e.isListed(companyID: id))
        let co = try XCTUnwrap(e.state.company(id))
        XCTAssertEqual(co.ownership, 70, accuracy: 0.5)
        XCTAssertGreaterThan(co.ownership, PublicRules.controlAbove)
        XCTAssertEqual(e.state.cash - cash0, q.expected - q.fee, accuracy: max(5, q.expected * 0.001))
        XCTAssertEqual(Shareholders.policy(co), "none", "no dividend until the owner chooses a payout")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testOwnerCannotSellBelowAMajority() throws {
        let (e, id) = try bigCompany()
        let q = try XCTUnwrap(e.saleQuote(companyID: id, percent: 60, method: .ipo))
        XCTAssertNotNil(q.problem)
        let ok = try XCTUnwrap(e.saleQuote(companyID: id, percent: 49, method: .ipo))
        XCTAssertNil(ok.problem, ok.problem ?? "")
        XCTAssertGreaterThan(ok.ownershipAfter, PublicRules.controlAbove)
    }

    func testABadQuarterPostsResultsAndPushesThePriceDown() throws {
        var (e, id) = try bigCompany()
        XCTAssertEqual(e.startSale(companyID: id, percent: 30, method: .ipo), .started)
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            let good = (0..<9).map { MonthRecord(monthIndex: $0, revenue: 40_000_000, profit: 12_000_000, cash: 0) }
            let bad = (9..<12).map { MonthRecord(monthIndex: $0, revenue: 10_000_000, profit: -1_000_000, cash: 0) }
            s.companies[i].monthlyHistory = good + bad
        }
        let before = try XCTUnwrap(ExchangeBook(e.state).instruments[PublicExchange.id(of: id)]).sentiment
        quarterDay(&e, id: id)
        let after = try XCTUnwrap(ExchangeBook(e.state).instruments[PublicExchange.id(of: id)]).sentiment
        XCTAssertLessThan(after, before)
        let name = try XCTUnwrap(e.state.company(id)).name
        XCTAssertTrue(e.state.inbox.contains { $0.title == "Quarterly results: \(name)" })
    }

    func testAGoodQuarterLiftsThePrice() throws {
        var (e, id) = try bigCompany()
        XCTAssertEqual(e.startSale(companyID: id, percent: 30, method: .ipo), .started)
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            let old = (0..<9).map { MonthRecord(monthIndex: $0, revenue: 20_000_000, profit: 3_000_000, cash: 0) }
            let new = (9..<12).map { MonthRecord(monthIndex: $0, revenue: 40_000_000, profit: 12_000_000, cash: 0) }
            s.companies[i].monthlyHistory = old + new
        }
        let before = try XCTUnwrap(ExchangeBook(e.state).instruments[PublicExchange.id(of: id)]).sentiment
        quarterDay(&e, id: id)
        XCTAssertGreaterThan(try XCTUnwrap(ExchangeBook(e.state).instruments[PublicExchange.id(of: id)]).sentiment, before)
    }

    func testTheBoardPaysTheDividendOncePerQuarterByThePayoutYouChose() throws {
        var (e, id) = try bigCompany()
        XCTAssertEqual(e.startSale(companyID: id, percent: 30, method: .ipo), .started)
        XCTAssertEqual(e.setDividendPolicy(companyID: id, policy: "mid"), .applied)
        let cash0 = e.state.cash
        quarterDay(&e, id: id)
        XCTAssertLessThan(e.state.cash, cash0, "the public's share of the dividend leaves the account")
        XCTAssertGreaterThan(e.state.stats.dividendsReceived, 0, "your own share counts as dividend income")
        var again: ExchangeDividendResult = .notListed
        e.update { s, _, _ in again = PublicExchange.declareDividend(&s, companyID: id, amount: 1000) }
        guard case .tooSoon = again else { return XCTFail("a second dividend inside the quarter: \(again)") }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testNoDividendWithoutAPayoutChoice() throws {
        var (e, id) = try bigCompany()
        XCTAssertEqual(e.startSale(companyID: id, percent: 30, method: .ipo), .started)
        let cash0 = e.state.cash
        quarterDay(&e, id: id)
        XCTAssertEqual(e.state.cash, cash0, accuracy: 0.5)
    }

    func testBigChangesAreRestrictedWhileTheSharesArePublic() throws {
        var (e, id) = try bigCompany()
        XCTAssertNil(PublicRules.restriction(e.state, companyID: id, change: .close))
        XCTAssertEqual(e.startSale(companyID: id, percent: 30, method: .ipo), .started)
        XCTAssertNotNil(PublicRules.restriction(e.state, companyID: id, change: .close))
        XCTAssertNotNil(PublicRules.restriction(e.state, companyID: id, change: .sellAssets))
        XCTAssertNotNil(PublicRules.restriction(e.state, companyID: id, change: .largeLoan))
        guard case .restricted = e.closeCompany(companyID: id, weeks: 4) else { return XCTFail("a listed company cannot be closed") }
        XCTAssertEqual(e.state.company(id)?.status, .open)
    }

    func testSoldStakesReduceYourShareOfTheCompanyAndItsProfit() throws {
        var (e, id) = try bigCompany()
        let before = try XCTUnwrap(e.state.company(id)).ownership
        XCTAssertEqual(e.startSale(companyID: id, percent: 40, method: .ipo), .started)
        let after = try XCTUnwrap(e.state.company(id)).ownership
        XCTAssertEqual(after, before * 0.6, accuracy: 0.5)
        XCTAssertGreaterThan(Shareholders.outside(try XCTUnwrap(e.state.company(id))), 39)
    }
}
