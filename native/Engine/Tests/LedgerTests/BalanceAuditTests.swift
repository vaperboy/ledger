import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Events
@testable import Simulation

final class BalanceAuditTests: XCTestCase {
    private func exchangeGame() throws -> GameEngine {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5, story: .fresh, tradeID: "kiosk")
        e.update { s, _, _ in Ledger.move(&s, .me, 5_000_000, why: "Test funds") }
        return e
    }

    private func closeWeek(_ e: inout GameEngine) {
        e.update { s, _, ctx in
            s.week += 1
            s.day = 1
            PublicExchange.runDay(&s, context: ctx, holdingValue: { _ in nil })
        }
    }

    private func nav(_ e: GameEngine) -> Double { ExchangeBook(e.state).instruments[PublicExchange.worldIndex]?.nav ?? 0 }

    func testServerShareFillsNeverBeatTheValuePerShare() throws {
        var e = try exchangeGame()
        guard case .placed = e.placeExchangeOrder(instrument: PublicExchange.worldIndex, side: .buy, shares: 200, limit: nav(e) * 1.2) else { return XCTFail("buy refused") }
        closeWeek(&e)
        let pos = try XCTUnwrap(ExchangeBook(e.state).positions[PublicExchange.worldIndex])
        XCTAssertEqual(pos.shares, 200)
        XCTAssertGreaterThanOrEqual(pos.cost, 200 * nav(e) - 1, "a buy pays at least the value per share")
        let cash0 = e.state.cash
        guard case .placed = e.placeExchangeOrder(instrument: PublicExchange.worldIndex, side: .sell, shares: 200, limit: nav(e) * 0.8) else { return XCTFail("sell refused") }
        closeWeek(&e)
        XCTAssertLessThanOrEqual(e.state.cash - cash0, 200 * nav(e) + 1, "a sale receives at most the value per share")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testPatientLimitOrdersCannotHarvestTheDailyWobble() throws {
        var e = try exchangeGame()
        e.update { s, _, _ in
            var b = ExchangeBook(s)
            PublicExchange.ensureServerStocks(s, &b)
            let n = b.instruments[PublicExchange.worldIndex]?.nav ?? 100
            b.positions[PublicExchange.worldIndex] = ExchangePosition(instrument: PublicExchange.worldIndex, shares: 1000, cost: 1000 * n, since: 0)
            b.write(to: &s)
        }
        let n0 = nav(e)
        XCTAssertGreaterThan(n0, 0)
        let start = e.state.cash + 1000 * n0
        for _ in 0..<80 {
            let held = ExchangeBook(e.state).positions[PublicExchange.worldIndex]?.shares ?? 0
            _ = e.placeExchangeOrder(instrument: PublicExchange.worldIndex, side: .buy, shares: 500, limit: nav(e) * 0.9985)
            if held >= 500 { _ = e.placeExchangeOrder(instrument: PublicExchange.worldIndex, side: .sell, shares: 500, limit: nav(e) * 1.0015) }
            closeWeek(&e)
        }
        let held = ExchangeBook(e.state).positions[PublicExchange.worldIndex]?.shares ?? 0
        let end = e.state.cash + Double(held) * nav(e)
        XCTAssertLessThanOrEqual(end, start + 1, "buying low and selling high around a fixed value per share must not pay: \(end - start)")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    private func listing(_ id: String, stopped: Bool = false, paused: Bool = false, stopsDay: Int? = nil) -> SupplyListing {
        SupplyListing(id: id, ownerID: "owner-\(id)", ownerName: "Name \(id)", profileCode: "P-\(id)", companyName: "Co \(id)", companyID: nil, tradeID: "farm", tradeName: "Farm",
                      city: "Leeds", region: "North", lineID: "goods", lineName: "Stock", priceTier: 1, qualityTier: 1, capacityPerWeek: 300, leadDays: 2, minOrder: 10, termsDays: 14,
                      linkKey: "key-\(id)", record: DeliveryRecord(weeksTrading: 20, ordersTotal: 40, ordersOnTime: 39, unitsPromised: 800, unitsDelivered: 790, cleanWeeks: 12, lifetimeUnits: 790),
                      paused: paused, stopped: stopped, country: "UK", stopsDay: stopsDay)
    }

    func testAListingThatHasStoppedCannotBeSignedOrOrdered() throws {
        var e = try ChainsTests.engine("UK", seed: 777)
        let id = ChainsTests.start(&e, "grocery")
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].status = .open
            s.companies[i].set("lastW", .object(["cogs": .number(4000), "units": .number(100), "cap": .number(200)]))
        }
        func contract(_ lid: String) -> SupplyContract {
            SupplyContract(id: "C-\(lid)", buyerCompanyID: id, lineID: "goods", listingID: lid, supplierOwnerID: "owner-\(lid)", supplierName: "Name \(lid)", unitsPerWeek: 20, startDay: 0)
        }
        XCTAssertFalse(e.signPlayerSupplier(contract: contract("s"), listing: listing("s", stopped: true), weeklyMarketSpend: 100_000))
        XCTAssertFalse(e.signPlayerSupplier(contract: contract("p"), listing: listing("p", paused: true), weeklyMarketSpend: 100_000))
        XCTAssertFalse(e.signPlayerSupplier(contract: contract("d"), listing: listing("d", stopsDay: 400), weeklyMarketSpend: 100_000))
        XCTAssertEqual(e.orderFromSupplier(companyID: id, listing: listing("s", stopped: true), units: 20), .badOrder)
        XCTAssertTrue(e.playerSupplyContracts.isEmpty)
        XCTAssertTrue(e.signPlayerSupplier(contract: contract("ok"), listing: listing("ok"), weeklyMarketSpend: 100_000))
    }

    func testTheInternalPriceOfAnOwnProductStaysBetweenNothingAndFull() throws {
        var e = try exchangeGame()
        e.update { s, _, _ in
            s.rest["founded"] = .array([.object(["id": .number(7), "sw16": .object([:])])])
            Startups.setInternalPrice(&s, startupID: 7, percent: 9_999)
            XCTAssertEqual(s.rest["founded"]?.array.first?["sw16"]["int"].double, 100)
            Startups.setInternalPrice(&s, startupID: 7, percent: -50)
            XCTAssertEqual(s.rest["founded"]?.array.first?["sw16"]["int"].double, 0)
        }
    }

    func testABoxCashPrizeIsPaidOncePerOpeningThroughTheLedger() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 3, story: .fresh, tradeID: "kiosk")
        let cash0 = e.state.cash
        XCTAssertNotNil(e.claimBoxMoney(1_000, claimID: "open-1"))
        XCTAssertNil(e.claimBoxMoney(1_000, claimID: "open-1"))
        XCTAssertNil(e.claimBoxMoney(BoxOdds.moneyCap + 1, claimID: "open-2"))
        XCTAssertGreaterThan(e.state.cash, cash0)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testPaidBoxesAndAuctionsNeverPayOutMoreGoldThanTheyTake() {
        for kind in BoxKind.allCases { XCTAssertTrue(BoxOdds.isFair(kind), "\(kind)") }
        for price in [10, 100, 1_000, 25_000] { XCTAssertGreaterThanOrEqual(AuctionRules.fee(forSale: price), 1); XCTAssertLessThan(AuctionRules.proceeds(forSale: price), price) }
    }

    func testLadderAndDailyGoalCashStaySmall() {
        let ladder = GoalClaims.ladderCash.values.reduce(0, +)
        XCTAssertLessThanOrEqual(ladder, 12_000)
        XCTAssertLessThan(GoalClaims.dailyCash * 365, 100_000, "a daily goal every day of a year stays small")
    }

    private func liquid(_ e: GameEngine) -> Double { e.state.cash + e.state.companies.filter { $0.status.isLive }.reduce(0) { $0 + $1.cash } }

    func testAPlayerWhoOnlyPressesNextDayDoesNotProfitInTheSecondYear() throws {
        for code in ["UK", "NO", "US"] {
            var e = try GameEngine.newGame(countryCode: code, playerName: "T", seed: 7, story: .fresh, tradeID: "cafe", companyName: "Idle Cafe")
            let start = liquid(e)
            for _ in 0..<(52 * 7) { e.nextDay() }
            let afterYearOne = liquid(e)
            for _ in 0..<(52 * 7) { e.nextDay() }
            let afterYearTwo = liquid(e)
            XCTAssertLessThanOrEqual(afterYearTwo - afterYearOne, start * 0.05, "\(code): a shop left on its defaults made \(Int(afterYearTwo - afterYearOne)) in its second year")
        }
    }
}
