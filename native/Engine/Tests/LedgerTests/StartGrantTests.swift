import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation

final class StartGrantTests: XCTestCase {
    func testEveryStarterGetsTheSameSavingsAndAShortCappedRunway() throws {
        for code in ["NO", "UK"] {
            let trades: [StarterTrade] = GameEngine.startableTrades(countryCode: code)
            XCTAssertGreaterThan(trades.count, 8, code)
            XCTAssertTrue(trades.allSatisfy { TradeUnlocks.isStarter($0.id) }, "\(code): a first start lists starter trades only")
            var owns: Set<Double> = []
            for t in trades {
                let e: GameEngine
                do { e = try GameEngine.newGame(countryCode: code, playerName: "T", seed: 3, story: .fresh, tradeID: t.id, companyName: "Test Co") }
                catch { XCTFail("\(code) \(t.id) did not start: \(error)"); continue }
                let co = try XCTUnwrap(e.state.companies.first, t.id)
                let fy = e.data.balance.firstYear
                let start = try XCTUnwrap(e.state.rest["start"])
                let own = start["own"].double, grant = start["grant"].double
                owns.insert(own)
                let instalments = e.state.loans.filter { $0.companyID == co.id }.reduce(0) { $0 + $1.monthlyPayment }
                let weekly = e.context.weeklyCost(co, e.state) + instalments * 12 / 52
                XCTAssertGreaterThan(weekly, 0, t.id)
                XCTAssertEqual(grant, min(own * fy.startGrantCapShare, weekly * Double(fy.startRunwayWeeks)), accuracy: 100, "\(code) \(t.id): the grant is a short runway, capped at part of the savings")
                XCTAssertGreaterThanOrEqual(e.state.cash, own * fy.startKeepShare + grant - 1, "\(code) \(t.id): working money is left after the opening")
                XCTAssertEqual(start["cash"].double, own + grant, accuracy: 0.5, "\(code) \(t.id)")
                XCTAssertEqual(start["loan"].double, e.state.loans.filter { $0.name == OpeningLoan.label }.reduce(0) { $0 + $1.balance }, accuracy: 0.5, "\(code) \(t.id)")
                XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(code) \(t.id): \(Ledger.gaps(e.state))")
            }
            XCTAssertEqual(owns.count, 1, "\(code): every starter brings the same savings \(owns)")
        }
    }

    func testTheGrantIsAVisibleLineSizedPerCompanyType() throws {
        var grants: [String: Double] = [:]
        for trade in ["cafe", "bakery", "carclean"] {
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
        XCTAssertGreaterThan(grants["bakery"] ?? 0, grants["carclean"] ?? 0, "a company with higher running costs gets a longer-lasting grant")
        XCTAssertGreaterThan(grants["carclean"] ?? 0, 0)
    }

    func testTheStartGrantNeverFundsABigTrade() throws {
        for trade in ["hotel", "airline", "oilgas", "shipping", "restaurant", "gym"] {
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

    func testTheGrantIsAShortRunwayInsideTheProtectedWeeks() throws {
        let fy = try Balance.bundled().firstYear
        XCTAssertLessThanOrEqual(fy.startRunwayWeeks, 4, "the grant covers a few weeks of running costs, not the opening")
        XCTAssertLessThan(fy.startRunwayWeeks, fy.noOverdraftWeeks)
        XCTAssertGreaterThan(fy.startKeepShare, 0)
    }
}
