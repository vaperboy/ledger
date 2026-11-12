import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

final class StartGrantTests: XCTestCase {
    func testEveryStartableCompanyTypeGetsTheSameRunway() throws {
        for code in ["NO", "UK"] {
            let trades: [StarterTrade] = GameEngine.startableTrades(countryCode: code, all: true)
            XCTAssertGreaterThan(trades.count, 10, code)
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
        for trade in ["cafe", "gym", "hotel", "carclean"] {
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
        XCTAssertGreaterThan(grants["hotel"] ?? 0, grants["cafe"] ?? 0, "a bigger company type gets a bigger grant")
        XCTAssertGreaterThan(grants["gym"] ?? 0, 0)
    }

    func testTheRunwayCoversTheWeeksWithoutOverdraft() throws {
        let fy = try Balance.bundled().firstYear
        XCTAssertEqual(fy.startRunwayWeeks, fy.noOverdraftWeeks, "the start money lasts the protected weeks")
    }
}
