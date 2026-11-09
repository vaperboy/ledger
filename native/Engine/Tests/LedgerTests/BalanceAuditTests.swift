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

    private func listing(_ id: String, stopped: Bool = false, paused: Bool = false, stopsDay: Int? = nil, committed: Int = 0) -> SupplyListing {
        SupplyListing(id: id, ownerID: "owner-\(id)", ownerName: "Name \(id)", profileCode: "P-\(id)", companyName: "Co \(id)", companyID: nil, tradeID: "farm", tradeName: "Farm",
                      city: "Leeds", region: "North", lineID: "goods", lineName: "Stock", priceTier: 1, qualityTier: 1, capacityPerWeek: 300, leadDays: 2, minOrder: 10, termsDays: 14,
                      linkKey: "key-\(id)", record: DeliveryRecord(weeksTrading: 20, ordersTotal: 40, ordersOnTime: 39, unitsPromised: 800, unitsDelivered: 790, cleanWeeks: 12, lifetimeUnits: 790),
                      paused: paused, stopped: stopped, committedUnits: committed, country: "UK", stopsDay: stopsDay)
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

    private func supplyGame() throws -> (GameEngine, Int) {
        var e = try ChainsTests.engine("UK", seed: 777)
        let id = ChainsTests.start(&e, "grocery")
        e.update { s, _, _ in
            guard let i = s.companyIndex(id) else { return }
            s.companies[i].status = .open
            s.companies[i].set("lastW", .object(["cogs": .number(4000), "units": .number(100), "cap": .number(200)]))
        }
        return (e, id)
    }

    private func supplyContract(_ lid: String, buyer: Int, units: Int = 20) -> SupplyContract {
        SupplyContract(id: "C-\(lid)", buyerCompanyID: buyer, lineID: "goods", listingID: lid, supplierOwnerID: "owner-\(lid)", supplierName: "Name \(lid)", unitsPerWeek: units, startDay: 0)
    }

    func testTheLastStockCannotGoToTwoBuyers() throws {
        var (e, id) = try supplyGame()
        XCTAssertFalse(e.signPlayerSupplier(contract: supplyContract("full", buyer: id, units: 20), listing: listing("full", committed: 290), weeklyMarketSpend: 100_000))
        XCTAssertFalse(e.signPlayerSupplier(contract: supplyContract("small", buyer: id, units: 5), listing: listing("small"), weeklyMarketSpend: 100_000))
        XCTAssertTrue(e.signPlayerSupplier(contract: supplyContract("fits", buyer: id, units: 20), listing: listing("fits", committed: 280), weeklyMarketSpend: 100_000))
    }

    func testASupplierThatReportsNothingForThreeWeeksLosesTheContractAndTheBuyerIsWarned() throws {
        var (e, id) = try supplyGame()
        XCTAssertTrue(e.signPlayerSupplier(contract: supplyContract("quiet", buyer: id), listing: listing("quiet"), weeklyMarketSpend: 100_000))
        e.update { s, _, _ in s.week += 2; PlayerSupply.weekly(&s) }
        XCTAssertEqual(e.playerSupplyContracts.count, 1)
        XCTAssertTrue(e.state.inbox.contains { $0.title == "Your supplier has gone quiet" })
        e.update { s, _, _ in s.week += 1; PlayerSupply.weekly(&s) }
        XCTAssertTrue(e.playerSupplyContracts.isEmpty)
        XCTAssertTrue(e.state.inbox.contains { $0.title == "Your supplier stopped supplying" })
    }

    func testAReportedDeliveryKeepsTheContractAlive() throws {
        var (e, id) = try supplyGame()
        XCTAssertTrue(e.signPlayerSupplier(contract: supplyContract("busy", buyer: id), listing: listing("busy"), weeklyMarketSpend: 100_000))
        for _ in 0..<6 {
            e.update { s, _, _ in s.week += 1; PlayerSupply.weekly(&s) }
            e.reportSupplyDelivery(listingID: "busy", promised: 20, delivered: 20)
        }
        XCTAssertEqual(e.playerSupplyContracts.count, 1)
    }

    func testCrowdStartupSharesAreNotPricedFarAboveWhatTheyAreWorth() {
        let plan = CrowdStartupRules.Plan(cost: 900_000, founderPutIn: 300_000)
        let sold = CrowdStartupRules.maxInvestorPercent(plan)
        XCTAssertLessThan(sold, 49)
        XCTAssertGreaterThanOrEqual(sold / 100 * plan.cost, plan.investorTarget * 0.6, "investors get at least 60% of what they pay in value at launch")
        XCTAssertLessThanOrEqual(CrowdStartupRules.stageMultiples.last ?? 0, 1.6)
        XCTAssertGreaterThanOrEqual(CrowdStartupRules.stageMultiples.first ?? 0, 1.0)
    }

    func testStructuralCareerGoalsPaySmallCashAndLevelUp() {
        for id in GoalClaims.structuralCareerIDs {
            XCTAssertNotNil(Career.defs.first { $0.id == id }, id)
            XCTAssertLessThanOrEqual(GoalClaims.careerCash(id: id, .long), 500)
        }
        XCTAssertLessThanOrEqual(GoalClaims.careerCash(.long), 10_000)
        XCTAssertLessThanOrEqual(GoalClaims.ladderCash.values.reduce(0, +), 6_000)
    }

    func testASaleToAnOutsideBuyerKeepsAThinMarginAndNeverBeatsCapacity() throws {
        var e = try GameEngine.showcase(days: 45)
        let sup = try XCTUnwrap(e.state.companies.first { $0.status == .open }?.id)
        let s0 = e.state.company(sup)?.cash ?? 0
        e.update { s, _, _ in _ = SupplyMarketBooks.settleSupply(&s, supplierCompanyID: sup, buyerCompanyID: nil, units: 10, unitPrice: 100, unitCost: 1) }
        XCTAssertLessThanOrEqual((e.state.company(sup)?.cash ?? 0) - s0, 10 * 100 * (1 - SupplyMarketBooks.standInCostShare) + 1)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testAShopLeftOnItsDefaultsIsUntendedUntilTheOwnerChoosesHowToSell() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7, story: .fresh, tradeID: "cafe", companyName: "C")
        let id = try XCTUnwrap(e.state.companies.first?.id)
        XCTAssertLessThan(e.data.balance.firstYear.untendedDemand, 1)
        XCTAssertTrue(e.data.balance.firstYear.untended(e.state))
        _ = e.setPriceLevel(companyID: id, level: 1)
        for _ in 0..<10 { e.nextDay() }
        XCTAssertFalse(e.data.balance.firstYear.untended(e.state))
    }
}
