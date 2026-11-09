import XCTest
import GameCore
import Countries
import Finance
@testable import Businesses
@testable import Simulation

/// Starting a company moves the owner's money into it at cost; it does not raise net worth, and no net-worth trophy or milestone is queued by the start.
final class StartNetWorthTests: XCTestCase {
    static let trades = ["cafe", "gym", "kiosk", "hotel", "bank", "carrental", "factory", "boutique"]

    func testStartingACompanyKeepsNetWorthWithinTwoPercentOfTheMoneyPutIn() throws {
        for trade in Self.trades {
            var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5)
            e.update { s, _, _ in Ledger.move(&s, .me, 60_000_000, why: "Test funds") }
            let put = 30_000_000.0
            let before = e.netWorth.total
            guard case .success(let out) = e.startCompanyChoosingPremises(tradeID: trade, cityID: e.state.player.cityID, form: .limited, size: nil, name: nil,
                                                                          pick: NewCompanyPlan.Pick(listingIndex: 2, buy: false), fundWith: put) else { XCTFail("\(trade) did not start"); continue }
            _ = e.quickSetup(companyID: out.companyID)
            let delta = e.netWorth.total - before
            XCTAssertLessThan(abs(delta), put * 0.02, "\(trade): net worth moved by \(delta) on day 0")
        }
    }

    func testNoNetWorthTrophyOrMilestoneIsQueuedInTheFirstFourWeeks() throws {
        for trade in Self.trades {
            var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5, story: .fresh, tradeID: trade)
            for _ in 0..<28 { _ = e.nextDay() }
            let nwWords = e.pendingCelebrations.filter { $0.title.hasPrefix("Net worth") || $0.title == "First million" }
            XCTAssertTrue(nwWords.isEmpty, "\(trade): \(nwWords.map(\.title))")
        }
    }

    func testAYoungCompanyCountsAtWhatWasPutInForGoals() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5, story: .fresh, tradeID: "kiosk")
        let paid = e.state.companies[0].ownerNetFlow
        e.update { s, _, _ in s.companies[0].cash += paid * 5 }   // a windfall that only a valuation would see
        let plain = Valuation.netWorth(e.state, trades: e.data.catalog).companies
        let goals = Valuation.netWorth(e.state, trades: e.data.catalog, forGoals: true).companies
        XCTAssertGreaterThan(plain, paid * 4)
        XCTAssertLessThanOrEqual(goals, paid * 1.001)
        e.update { s, _, _ in s.week += Valuation.youngCompanyWeeks + 1 }
        XCTAssertEqual(Valuation.netWorth(e.state, trades: e.data.catalog, forGoals: true).companies, Valuation.netWorth(e.state, trades: e.data.catalog).companies, accuracy: 1)
    }

    /// Opening a company buys only what it needs to open and trade; the optional kit is left for later.
    func testAFreshStartBuysOnlyWhatTheTradeNeedsToOpen() throws {
        for trade in ["gym", "cafe", "hotel"] {
            let e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5, story: .fresh, tradeID: trade)
            let co = e.state.companies[0]
            let bd = try XCTUnwrap(e.data.catalog[trade])
            var optional = 0
            for eq in bd.equipment where eq.vehicleModels == nil {
                let n = CapacityModel.equipmentCount(co, eq)
                if eq.opensTheTrade { XCTAssertGreaterThanOrEqual(n, 1, "\(trade): \(eq.id) is needed to open") }
                else { XCTAssertEqual(n, 0, "\(trade): \(eq.id) is optional and was bought at the start"); optional += 1 }
            }
            XCTAssertGreaterThan(optional, 0, "\(trade) has optional kit to leave out")
            XCTAssertEqual(co.status, .open)
        }
    }

    func testQuickSetupBuysNoOptionalEquipmentByDefault() throws {
        for trade in ["gym", "cafe", "hotel"] {
            var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5)
            e.update { s, _, _ in Ledger.move(&s, .me, 90_000_000, why: "Test funds") }
            guard case .success(let id) = e.startCompany(tradeID: trade, cityID: e.state.player.cityID, form: .limited, fundWith: 80_000_000) else { XCTFail(trade); continue }
            let co = try XCTUnwrap(e.state.company(id))
            let bd = try XCTUnwrap(e.data.catalog[trade])
            for eq in bd.equipment where !eq.opensTheTrade && eq.vehicleModels == nil { XCTAssertEqual(CapacityModel.equipmentCount(co, eq), 0, "\(trade): \(eq.id)") }
            for eq in bd.equipment where eq.opensTheTrade && eq.vehicleModels == nil { XCTAssertGreaterThanOrEqual(CapacityModel.equipmentCount(co, eq), 1, "\(trade): \(eq.id)") }
        }
    }
}
