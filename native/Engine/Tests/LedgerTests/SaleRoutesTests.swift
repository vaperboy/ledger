import XCTest
import GameCore
import Finance
@testable import Businesses
@testable import Events
@testable import Simulation

final class SaleRoutesTests: XCTestCase {
    private func shop(seed: Int = 21, revenue: Double = 60_000, profit: Double = 9_000) throws -> (GameEngine, Int) {
        var e = try ChainsTests.engine("UK", seed: seed)
        let id = ChainsTests.start(&e, "cafe")
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].status = .open
            s.companies[i].foundedWeek = s.week - 200
            s.companies[i].monthlyHistory = (0..<12).map { MonthRecord(monthIndex: $0, revenue: revenue, profit: profit, cash: 20_000) }
        }
        return (e, id)
    }

    private func tick(_ e: inout GameEngine, weeks: Int = 1) {
        for _ in 0..<weeks { e.update { s, d, c in s.week += 1; CompanySale.weekly(&s, data: d, context: c) } }
    }

    func testAuctionRunsThreeRoundsThenHammerSellsAndBooksBalance() throws {
        var (e, id) = try shop()
        let value = CompanySale.estimatedValue(e.state, companyID: id, data: e.data)
        XCTAssertEqual(e.startSale(companyID: id, percent: 100, method: .auction, reserve: value * 0.3), .started)
        var l = try XCTUnwrap(e.saleListing(companyID: id))
        XCTAssertEqual(l.route, "auction")
        XCTAssertEqual(l.round, 1)
        XCTAssertGreaterThanOrEqual(l.offers.count, 3)
        let r1 = l.offers.map { $0.price }.max() ?? 0
        tick(&e); tick(&e)
        l = try XCTUnwrap(e.saleListing(companyID: id))
        XCTAssertEqual(l.round, 3)
        XCTAssertGreaterThan(l.offers.map { $0.price }.max() ?? 0, r1, "bids rise from round to round")
        let cash0 = e.state.cash
        let got = try XCTUnwrap(e.hammerSale(companyID: id))
        XCTAssertGreaterThan(got, 0)
        XCTAssertEqual(e.state.company(id)?.status, .sold)
        XCTAssertGreaterThan(e.state.cash, cash0)
        XCTAssertNil(e.saleListing(companyID: id))
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testAuctionIsDeterministicAndAReserveNobodyMeetsEndsUnsold() throws {
        var (a, ida) = try shop(seed: 22), (b, idb) = try shop(seed: 22)
        let v = CompanySale.estimatedValue(a.state, companyID: ida, data: a.data)
        XCTAssertEqual(a.startSale(companyID: ida, percent: 100, method: .auction, reserve: v * 0.3), .started)
        XCTAssertEqual(b.startSale(companyID: idb, percent: 100, method: .auction, reserve: v * 0.3), .started)
        tick(&a, weeks: 2); tick(&b, weeks: 2)
        XCTAssertEqual(a.saleListing(companyID: ida)?.offers.map { $0.price }, b.saleListing(companyID: idb)?.offers.map { $0.price })
        XCTAssertEqual(a.saleListing(companyID: ida)?.offers.map { $0.buyer }, b.saleListing(companyID: idb)?.offers.map { $0.buyer })

        var (c, idc) = try shop(seed: 23)
        XCTAssertEqual(c.startSale(companyID: idc, percent: 100, method: .auction, reserve: v * 20), .started)
        XCTAssertEqual(c.saleListing(companyID: idc)?.offers.count, 0)
        tick(&c, weeks: 8)
        XCTAssertNil(c.saleListing(companyID: idc), "the auction ended with no sale")
        XCTAssertEqual(c.state.company(idc)?.status, .open)
    }

    func testOneQuoteShowsValueFeeTaxAndWhatYouKeepForEveryMethod() throws {
        let (e, id) = try shop(seed: 24)
        for method in CompanySale.Method.allCases {
            let q = try XCTUnwrap(e.saleQuote(companyID: id, percent: 30, method: method))
            XCTAssertEqual(q.pct, 30)
            XCTAssertEqual(q.stakeValue, q.companyValue * 0.3, accuracy: 1)
            XCTAssertLessThanOrEqual(q.youGet, q.expected + 0.5)
            XCTAssertGreaterThanOrEqual(q.tax, 0)
            if method != .ipo { XCTAssertEqual(q.ownershipAfter, 70, accuracy: 0.5) }
        }
        XCTAssertEqual(try XCTUnwrap(e.saleQuote(companyID: id, percent: 100, method: .offers)).ownershipAfter, 0, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(e.saleQuote(companyID: id, percent: 3, method: .offers)).pct, 10, "the smallest part is ten percent")
    }

    func testSellingAPartListsThatPartAndOnlyOneSaleRunsAtATime() throws {
        var (e, id) = try shop(seed: 25)
        XCTAssertEqual(e.startSale(companyID: id, percent: 40, method: .offers), .started)
        let l = try XCTUnwrap(e.saleListing(companyID: id))
        XCTAssertEqual(l.pct, 40)
        XCTAssertEqual(l.route, "private")
        guard case .refused = e.startSale(companyID: id, percent: 40, method: .auction) else { return XCTFail("one sale at a time") }
        guard case .refused = e.startSale(companyID: id, percent: 40, method: .ipo) else { return XCTFail("a listed company cannot also go public") }
    }

    func testASmallYoungCompanyCannotGoPublicAndSaysWhy() throws {
        var (e, id) = try shop(seed: 26)
        e.update { s, _, _ in s.companies[s.companyIndex(id)!].foundedWeek = s.week - 2 }
        let q = try XCTUnwrap(e.saleQuote(companyID: id, percent: 30, method: .ipo))
        XCTAssertNotNil(q.problem)
        guard case .refused(let why) = e.startSale(companyID: id, percent: 30, method: .ipo) else { return XCTFail() }
        XCTAssertFalse(why.isEmpty)
        XCTAssertFalse(e.isListed(companyID: id))
    }
}
