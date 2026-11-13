import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

final class StartGrantTests: XCTestCase {
    func testEveryStartableCompanyTypeGetsTheSameRunway() throws {
        for code in ["NO", "UK"] {
            let trades: [StarterTrade] = GameEngine.startableTrades(countryCode: code)
            XCTAssertGreaterThan(trades.count, 8, code)
            XCTAssertTrue(trades.allSatisfy { TradeUnlocks.isStarter($0.id) }, "\(code): a first start lists starter trades only")
            var runways: [String: Double] = [:]
            for t in trades {
                let e: GameEngine
                do { e = try GameEngine.newGame(countryCode: code, playerName: "T", seed: 3, story: .fresh, tradeID: t.id, companyName: "Test Co") }
                catch { XCTFail("\(code) \(t.id) did not start: \(error)"); continue }
                let co = try XCTUnwrap(e.state.companies.first, t.id)
                let weekly = e.context.weeklyCost(co, e.state)
                XCTAssertGreaterThan(weekly, 0, t.id)
                let weeks = e.state.cash / weekly
                runways[t.id] = weeks
                let target = Double(e.data.balance.firstYear.startRunwayWeeks)
                XCTAssertEqual(weeks, target, accuracy: 0.05 + 100 / weekly, "\(code) \(t.id): \(weeks) weeks of fixed costs")
                let start = try XCTUnwrap(e.state.rest["start"])
                XCTAssertEqual(start["cash"].double, start["own"].double + start["grant"].double, accuracy: 0.5, "\(code) \(t.id)")
                XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(code) \(t.id): \(Ledger.gaps(e.state))")
            }
            let spread = (runways.values.max() ?? 0) - (runways.values.min() ?? 0)
            XCTAssertLessThan(spread, 0.5, "\(code): runways \(runways)")
        }
    }

    func testTheGrantIsAVisibleLineSizedPerCompanyType() throws {
        var grants: [String: Double] = [:]
        for trade in ["cafe", "gym", "bakery", "carclean"] {
            let e = try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 3, story: .fresh, tradeID: trade, companyName: "Test Co")
            let co = try XCTUnwrap(e.state.companies.first)
            let grant = StartGrant.amount(e.state)
            grants[trade] = grant
            let own = try XCTUnwrap(e.state.rest["start"]?["own"].double)
            XCTAssertLessThanOrEqual(own, e.homeCurrency.tidy(e.homeCurrency.scaledPrice(e.data.balance.firstYear.startSavings)) + 1, trade)
            XCTAssertTrue(e.state.statement.contains { $0.label == "Starting money" && abs($0.amount - own) < 1 }, trade)
            if grant > 0 {
                XCTAssertTrue(co.transactions.contains { $0["l"].string == StartGrant.label && abs($0["a"].double - grant) < 1 }, "\(trade): the grant shows in the company's account")
                XCTAssertTrue(AccountingLedger.rows(co).contains { $0.label == StartGrant.label && abs($0.amount - grant) < 1 }, "\(trade): the grant is in the books")
            }
        }
        XCTAssertGreaterThan(grants["gym"] ?? 0, grants["carclean"] ?? 0, "a bigger company type gets a bigger grant")
        XCTAssertGreaterThan(grants["gym"] ?? 0, 0)
    }

    func testTheStartGrantNeverFundsABigTrade() throws {
        for trade in ["hotel", "airline", "oilgas", "shipping", "restaurant"] {
            XCTAssertThrowsError(try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 3, story: .fresh, tradeID: trade, companyName: "Test Co"), trade)
        }
        let e = try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 3)
        for id in TradeUnlocks.starterIDs {
            let cost = try XCTUnwrap(e.data.catalog[id]).openingCost
            XCTAssertLessThanOrEqual(cost, 100_000, "\(id) is inside the starter range")
        }
    }

    func testBigTradesWaitForTheirLevel() throws {
        var e = try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 3)
        let locked: [String] = ["airline", "oilgas", "shipping", "hotel", "grocery", "factory"]
        let before = Dictionary(uniqueKeysWithValues: e.tradePickerRows().map { ($0.tradeID, $0.blocked) })
        for id in locked { XCTAssertNotNil(before[id].flatMap { $0 }, "\(id) is locked for a new player") }
        XCTAssertNil(before["cafe"].flatMap { $0 })
        e.update { s, _, _ in PlayerLevel.award(&s, PlayerLevel.threshold(LevelGates.level(.exchange))) }
        let mid = Dictionary(uniqueKeysWithValues: e.tradePickerRows().map { ($0.tradeID, $0.blocked) })
        XCTAssertNil(mid["hotel"].flatMap { $0 }, "big trades open with the stock exchange level")
        XCTAssertNotNil(mid["airline"].flatMap { $0 }, "the largest trades stay shut")
        e.update { s, _, _ in PlayerLevel.award(&s, PlayerLevel.threshold(LevelGates.level(.abroad))) }
        let late = Dictionary(uniqueKeysWithValues: e.tradePickerRows().map { ($0.tradeID, $0.blocked) })
        XCTAssertNil(late["airline"].flatMap { $0 })
    }

    func testInsuranceAndRivalsOpenEarly() {
        XCTAssertLessThanOrEqual(LevelGates.level(.insurance), 4)
        XCTAssertLessThanOrEqual(LevelGates.level(.rivals), 6)
        XCTAssertGreaterThanOrEqual(LevelGates.level(.rivals), 5)
    }

    func testTheRunwayCoversTheWeeksWithoutOverdraft() throws {
        let fy = try Balance.bundled().firstYear
        XCTAssertEqual(fy.startRunwayWeeks, fy.noOverdraftWeeks, "the start money lasts the protected weeks")
    }
}
