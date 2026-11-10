import XCTest
import GameCore
import Finance
@testable import Businesses
@testable import Events
@testable import Simulation

final class SaleRoutesTests: XCTestCase {
    private func shop(seed: Int = 21) throws -> (GameEngine, Int) {
        var e = try ChainsTests.engine("UK", seed: seed)
        let id = ChainsTests.start(&e, "cafe")
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].status = .open
            s.companies[i].monthlyHistory = (0..<12).map { MonthRecord(monthIndex: $0, revenue: 60_000, profit: 9_000, cash: 20_000) }
        }
        return (e, id)
    }
    private func tick(_ e: inout GameEngine, weeks: Int = 1) {
        for _ in 0..<weeks { e.update { s, d, c in s.week += 1; CompanySale.weekly(&s, data: d, context: c) } }
    }

    func testAuctionRunsThreeRoundsThenHammerSellsAndBooksBalance() throws {
        var (e, id) = try shop()
        let value = CompanySale.estimatedValue(e.state, companyID: id, data: e.data)
        XCTAssertTrue(e.startAuction(companyID: id, reserve: value * 0.3))
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
        XCTAssertTrue(a.startAuction(companyID: ida, reserve: v * 0.3)); XCTAssertTrue(b.startAuction(companyID: idb, reserve: v * 0.3))
        tick(&a, weeks: 2); tick(&b, weeks: 2)
        XCTAssertEqual(a.saleListing(companyID: ida)?.offers.map { $0.price }, b.saleListing(companyID: idb)?.offers.map { $0.price })
        XCTAssertEqual(a.saleListing(companyID: ida)?.offers.map { $0.buyer }, b.saleListing(companyID: idb)?.offers.map { $0.buyer })

        var (c, idc) = try shop(seed: 23)
        XCTAssertTrue(c.startAuction(companyID: idc, reserve: v * 20))
        XCTAssertEqual(c.saleListing(companyID: idc)?.offers.count, 0)
        tick(&c, weeks: 8)
        XCTAssertNil(c.saleListing(companyID: idc), "the auction ended with no sale")
        XCTAssertEqual(c.state.company(idc)?.status, .open)
    }

    func testBuyoutNeedsAManagerAndOnlyTheManagerBids() throws {
        var (e, id) = try shop(seed: 24)
        XCTAssertFalse(e.startSale(companyID: id, route: "mbo"))
        XCTAssertFalse(try XCTUnwrap(e.saleRoutes(companyID: id).first { $0.id == "mbo" }).available)
        let cands = try XCTUnwrap(e.searchManagers(companyID: id))
        XCTAssertEqual(e.hireManager(personID: cands[0].id, companyID: id, monthlyWage: cands[0].askingMonthlyWage * 1.3), .ok)
        XCTAssertTrue(e.startSale(companyID: id, route: "mbo"))
        var l = try XCTUnwrap(e.saleListing(companyID: id))
        for _ in 0..<40 where l.offers.isEmpty { tick(&e); l = e.saleListing(companyID: id) ?? l }
        let o = try XCTUnwrap(l.offers.first)
        XCTAssertEqual(o.kind, "mbo")
        XCTAssertNotNil(e.acceptBuyerOffer(companyID: id, offerID: o.id))
        XCTAssertEqual((e.state.rest["deferred"]?.array ?? []).count, 1, "a third is paid later")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testMergerSwapsTheCompanyForAShareAndTakesTheRival() throws {
        var (e, id) = try shop(seed: 25)
        e.update { s, _, _ in
            guard let co = s.company(id) else { return }
            let key = co.type + "|" + co.cityID
            s.rest["mk"] = .object([key: .object(["n": 2, "riv": .array([.object(["id": 7, "name": "Rae's Cafe", "owner": "Rae Rival", "size": 1])])])])
        }
        XCTAssertEqual(e.mergeCandidates(companyID: id).map { $0.name }, ["Rae's Cafe"])
        XCTAssertTrue(try XCTUnwrap(e.saleRoutes(companyID: id).first { $0.id == "merger" }).available)
        XCTAssertEqual(e.mergeWithRival(companyID: id, rivalID: 7, percent: 30), .merged)
        XCTAssertEqual(e.state.company(id)?.ownership ?? 100, 70, accuracy: 0.5)
        XCTAssertTrue(e.mergeCandidates(companyID: id).isEmpty)
        XCTAssertEqual(e.mergeWithRival(companyID: id, rivalID: 7, percent: 30), .refused("That rival is no longer there."))
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testStakeTiersShowWhatEachUnlocksAndIpoGivesItsReason() throws {
        let (e, id) = try shop(seed: 26)
        let tiers = e.stakeTiers(companyID: id)
        XCTAssertEqual(tiers.map { $0.pct }, [10, 25, 34, 49])
        XCTAssertFalse(tiers[0].unlocks.contains { $0.contains("board seat") })
        XCTAssertTrue(tiers[1].unlocks.contains { $0.contains("board seat") })
        XCTAssertTrue(tiers[3].unlocks.contains { $0.contains("block") })
        XCTAssertEqual(tiers[3].youKeep, 51, accuracy: 0.5)
        let ipo = try XCTUnwrap(e.saleRoutes(companyID: id).first { $0.id == "ipo" })
        XCTAssertFalse(ipo.available)
        XCTAssertTrue(ipo.why.contains("holding"))
        XCTAssertEqual(e.saleRoutes(companyID: id).map { $0.id }, ["private", "broker", "auction", "mbo", "merger", "group", "stake", "ipo", "franchise"])
    }

    func testAListedCompanyShowsTheGroupRouteAsShut() throws {
        var (e, id) = try shop(seed: 27)
        XCTAssertTrue(e.startSale(companyID: id, route: "private"))
        let r = try XCTUnwrap(e.saleRoutes(companyID: id).first { $0.id == "group" })
        XCTAssertFalse(r.available)
        XCTAssertTrue(r.why.contains("listed"))
        XCTAssertNil(e.sellToGroup(companyID: id, groupID: "any"))
    }

    func testTheBoardsSellPointUsesTheSameListing() throws {
        var (e, id) = try shop(seed: 27)
        let d0 = e.data; e.update { s, _, _ in _ = ManagerModel.doEmergency(&s, companyID: id, code: "sell", data: d0) }
        XCTAssertEqual(e.saleListing(companyID: id)?.route, "broker")
        XCTAssertFalse(e.startSale(companyID: id, route: "private"), "one listing per company")
    }
}
