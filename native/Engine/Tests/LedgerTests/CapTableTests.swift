import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Events
@testable import Simulation

/// One cap table with real share counts. Repeated rounds, all four operations, migration of old percentages and a save round trip.
final class CapTableTests: XCTestCase {
    private func company() throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5)
        var id = 0
        e.update { s, d, c in
            Ledger.move(&s, .me, 900_000_000, why: "funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, data: d, context: c) { id = i }
            _ = Payments.injectCash(&s, companyID: id, amount: 50_000_000)
        }
        return (e, id)
    }
    private func total(_ co: Company) -> Double { co.ownership + co.value("holders").array.reduce(0) { $0 + $1["pct"].double } }

    func testRepeatedIssuesDiluteEveryoneAndAlwaysSumTo100() throws {
        var (e, id) = try company()
        for round in 1...3 {
            e.update { s, _, _ in
                let i = s.companyIndex(id)!
                let n = CapTable.sharesForPercent(20, total: CapTable.table(s.companies[i]).total)
                CapTable.issue(&s, i, newShares: n, to: "Investor \(round)", paid: 1000)
            }
        }
        let co = e.state.company(id)!
        XCTAssertEqual(total(co), 100, accuracy: 1e-6)
        let hs = co.value("holders").array
        XCTAssertEqual(hs[0]["pct"].double, 12.8, accuracy: 1e-3)
        XCTAssertEqual(hs[1]["pct"].double, 16, accuracy: 1e-3)
        XCTAssertEqual(hs[2]["pct"].double, 20, accuracy: 1e-3)
        XCTAssertEqual(co.ownership, 51.2, accuracy: 1e-3)
        XCTAssertEqual(CapTable.table(co).total, 1_953_125, "1,000,000 / 0.512")
    }

    func testSecondarySalesAndHolderSaleKeepTheTotalAt100() throws {
        var (e, id) = try company()
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            CapTable.issue(&s, i, newShares: CapTable.sharesForPercent(25, total: CapTable.table(s.companies[i]).total), to: "A", paid: 1)
            CapTable.sellFromYou(&s, i, shares: 100_000, to: "B", paid: 1)
            CapTable.sellFromYou(&s, i, shares: 100_000, to: "C", paid: 1)
            XCTAssertEqual(CapTable.holderSells(&s, i, holder: "A", shares: 50_000, to: "D"), 50_000)
            XCTAssertEqual(CapTable.holderSells(&s, i, holder: "B", shares: nil, to: "E"), 100_000)
        }
        let co = e.state.company(id)!
        XCTAssertEqual(total(co), 100, accuracy: 1e-6)
        XCTAssertEqual(co.value("holders").array.map { $0["name"].string }, ["A", "E", "C", "D"])
        let t = CapTable.table(co)
        XCTAssertEqual(t.you + t.holders.reduce(0) { $0 + $1.shares }, t.total)
    }

    func testOldPercentagesMigrateWithoutLossAndOverfullTablesAreScaled() throws {
        var (e, id) = try company()
        e.update { s, _, _ in   // what the old code left behind: holders 104.9% and you at 41.5%
            let i = s.companyIndex(id)!
            s.companies[i].ownership = 41.47
            s.companies[i].set("holders", .array([.object(["name": "X", "pct": 60, "in": 1]), .object(["name": "Y", "pct": 44.88, "in": 1])]))
            s.companies[i].set("cap", .null)
            CapTable.normaliseAll(&s)
        }
        var co = e.state.company(id)!
        XCTAssertEqual(total(co), 100, accuracy: 1e-3)
        XCTAssertEqual(co.ownership, 41.47, accuracy: 1e-3, "you keep what you were shown")
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].ownership = 70
            s.companies[i].set("holders", .array([.object(["name": "Z", "pct": 10, "in": 1])]))
            s.companies[i].set("cap", .null)
            CapTable.normaliseAll(&s)
        }
        co = e.state.company(id)!
        XCTAssertEqual(co.ownership, 70, accuracy: 1e-3)
        XCTAssertEqual(total(co), 100, accuracy: 1e-3)
        XCTAssertTrue(co.value("holders").array.contains { $0["name"].string == "Other shareholders" })
    }

    func testFundingOperationsUseCountsAndSurviveASaveRoundTrip() throws {
        var (e, id) = try company()
        let fc = FinanceContext(countries: e.data.countries, trades: e.data.catalog)
        e.update { s, d, _ in
            for _ in 0..<2 { _ = Funding.sellShares(&s, companyID: id, pct: 20, mode: "primary", data: d, context: fc) }
            for _ in 0..<2 { _ = Funding.sellShares(&s, companyID: id, pct: 10, mode: "secondary", data: d, context: fc) }
        }
        let co = e.state.company(id)!
        XCTAssertEqual(total(co), 100, accuracy: 1e-6)
        XCTAssertEqual(co.value("holders").array.count, 4)
        let terms = CapTable.issueTerms(co, preMoney: 8_000_000, amount: 2_000_000, buyer: "New")
        XCTAssertEqual(terms.buyerPctAfter, 20, accuracy: 0.01)
        XCTAssertEqual(terms.companyProceeds, 2_000_000)
        XCTAssertEqual(terms.personalProceeds, 0)
        XCTAssertEqual(terms.pricePerShare * Double(terms.sharesInIssueBefore), 8_000_000, accuracy: 1)
        let data = try JSONEncoder().encode(e.state)
        let back = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(CapTable.table(back.company(id)!), CapTable.table(co))
        XCTAssertEqual(back.company(id)!.value("cap")["total"].int, CapTable.table(co).total)
    }

    func testBuyBackReturnsTheHoldersSharesToYou() throws {
        var (e, id) = try company()
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            CapTable.issue(&s, i, newShares: CapTable.sharesForPercent(30, total: CapTable.table(s.companies[i]).total), to: "A", paid: 1)
            CapTable.buyFromHolder(&s, i, holder: "A")
        }
        let co = e.state.company(id)!
        XCTAssertEqual(co.ownership, 100, accuracy: 1e-9)
        XCTAssertTrue(co.value("holders").array.isEmpty)
    }
}
