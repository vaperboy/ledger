import XCTest
import GameCore
import Finance
import Simulation
@testable import Businesses

final class OnlineSettlementsTests: XCTestCase {
    private func game() throws -> (engine: GameEngine, company: Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: 4242)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 160_000_000, why: "Test funds")
            guard case .success(let i) = CompanySetup.create(&s, tradeID: "bakery", cityID: s.player.cityID, data: data, context: ctx) else { return }
            let est = CompanySetup.estimate(tradeID: "bakery", cityID: s.player.cityID, size: 1, state: s, data: data)
            _ = Payments.injectCash(&s, companyID: i, amount: (est?.total ?? 1_000_000) * 1.6 + 3_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: i, data: data)
            id = i
        }
        for _ in 0..<(8 * 7) { e.nextDay() }
        return (e, id)
    }

    func testAnAuctionSaleLandsInPersonalCashOnceAndIsAcknowledgedEveryTime() throws {
        var e = try game().engine
        let cash0: Double = e.state.cash
        let item = OnlineSettlement(id: "s1", amount: 95, currency: "GBP", kind: "auction_sale", label: "Sold at auction")
        var first: [String] = []
        var second: [String] = []
        e.update { s, d, _ in first = OnlineSettlements.book(&s, [item], data: d) }
        let after: Double = e.state.cash
        e.update { s, d, _ in second = OnlineSettlements.book(&s, [item], data: d) }
        XCTAssertGreaterThan(after, cash0)
        XCTAssertEqual(e.state.cash, after, "the same settlement must not be booked twice")
        XCTAssertEqual(first, ["s1"])
        XCTAssertEqual(second, ["s1"])
        XCTAssertTrue(OnlineSettlements.isBooked(e.state, id: "s1"))
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testAWinningBidTakesCashAndTheAmountFollowsTheCurrency() throws {
        var e = try game().engine
        let cash0: Double = e.state.cash
        e.update { s, d, _ in OnlineSettlements.book(&s, [OnlineSettlement(id: "w1", amount: -105, currency: "GBP", kind: "auction_win", label: "Won at auction")], data: d) }
        let spentGBP: Double = cash0 - e.state.cash
        let cash1: Double = e.state.cash
        e.update { s, d, _ in OnlineSettlements.book(&s, [OnlineSettlement(id: "w2", amount: -105, currency: "USD", kind: "auction_win", label: "Won at auction")], data: d) }
        let spentUSD: Double = cash1 - e.state.cash
        XCTAssertGreaterThan(spentGBP, 0)
        XCTAssertGreaterThan(spentUSD, 0)
        XCTAssertNotEqual(spentGBP, spentUSD, accuracy: 0.001)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testASupplySaleIsRevenueOfTheSupplierCompanyAndAPurchaseIsOnlyAcknowledged() throws {
        let g = try game()
        var e = g.engine
        let id = g.company
        // The company draws on the one account, so who was paid is read from the cash flows.
        let co0: Double = e.state.cashFlow["co\(id)"] ?? 0
        let me0: Double = e.state.cashFlow["me"] ?? 0
        let cash0: Double = e.state.cash
        let sale = OnlineSettlement(id: "a:1", amount: 1000, currency: "GBP", kind: "supply_sale", label: "Sold to other players", companyKey: "own.\(id)", units: 50, unitPrice: 20)
        let purchase = OnlineSettlement(id: "a:2", amount: -1000, currency: "GBP", kind: "supply_purchase", companyKey: "own.\(id)", units: 50, unitPrice: 20)
        var done: [String] = []
        e.update { s, d, _ in done = OnlineSettlements.book(&s, [sale, purchase], data: d) }
        XCTAssertEqual(done, ["a:1", "a:2"])
        let received: Double = (e.state.cashFlow["co\(id)"] ?? 0) - co0
        XCTAssertGreaterThan(received, 0)
        XCTAssertEqual(e.state.cashFlow["me"] ?? 0, me0, accuracy: 0.01, "a supply sale pays the company, not the player")
        XCTAssertEqual(e.state.cash - cash0, received, accuracy: 0.01, "the purchase is only acknowledged: nothing else moves")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
    }

    func testASupplySaleForAClosedCompanyFallsBackToPersonalCash() throws {
        var e = try game().engine
        let me0: Double = e.state.cash
        e.update { s, d, _ in
            OnlineSettlements.book(&s, [OnlineSettlement(id: "x", amount: 400, currency: "GBP", kind: "supply_sale", companyKey: "own.9999", units: 10, unitPrice: 40)], data: d)
        }
        XCTAssertGreaterThan(e.state.cash, me0)
    }

    func testTheEngineEntryPointReturnsEveryIdAndKeepsTheMemoryBounded() throws {
        var e = try game().engine
        let items: [OnlineSettlement] = (0..<700).map { OnlineSettlement(id: "id\($0)", amount: 1, currency: "GBP", kind: "conviction_refund") }
        let done: [String] = e.bookOnlineSettlements(items)
        XCTAssertEqual(done.count, 700)
        XCTAssertLessThanOrEqual((e.state.rest["online"] ?? .null)["booked"].array.count, OnlineSettlements.memory)
        XCTAssertEqual(OnlineSettlements.companyID(fromKey: "own.12"), 12)
        XCTAssertNil(OnlineSettlements.companyID(fromKey: "x.12"))
    }
}
