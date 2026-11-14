import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Events
@testable import Simulation

/// Every first company starts on about the same footing: the same savings, a short grant, only the kit needed to open.
final class StarterBalanceTests: XCTestCase {
    struct Row {
        var trade: String
        var own = 0.0, grant = 0.0, loan = 0.0, kit = 0.0
        var staff = 0
        var nw: [Int: Double] = [:]
        var trophyWeeks: [Int] = []
    }

    static let checkWeeks = [0, 5, 12, 26]

    /// Plays one fresh start on defaults, answering each open question with its first option.
    static func play(_ code: String, _ trade: String) throws -> Row {
        var e = try GameEngine.newGame(countryCode: code, playerName: "T", seed: 7, story: .fresh, tradeID: trade, companyName: "Test Co")
        var r = Row(trade: trade)
        let start = e.state.rest["start"] ?? .null
        r.own = start["own"].double; r.grant = start["grant"].double; r.loan = start["loan"].double
        if let co = e.state.companies.first { r.kit = CompanyFigures.equipmentBookValue(co); r.staff = co.staff.count }
        r.nw[0] = e.netWorth.total
        for w in 1...(checkWeeks.last ?? 0) {
            for _ in 0..<7 {
                _ = e.nextDay()
                for m in e.openDecisions where !m.options.isEmpty { _ = e.answer(messageID: m.id, option: 0) }
            }
            if checkWeeks.contains(w) { r.nw[w] = e.netWorth.total }
        }
        r.trophyWeeks = Trophies.entries(e.state).compactMap { $0.reachedWeek }
        return r
    }

    static func median(_ v: [Double]) -> Double {
        let s = v.sorted()
        guard !s.isEmpty else { return 0 }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    func testEveryStarterStartsOnAboutTheSameFooting() throws {
        for code in ["NO", "LT"] {
            var rows: [Row] = []
            for trade in TradeUnlocks.starterIDs {
                do { rows.append(try Self.play(code, trade)) } catch { XCTFail("\(code) \(trade) did not start: \(error)") }
            }
            let cur = try GameEngine.newGame(countryCode: code, playerName: "T", seed: 7).homeCurrency
            func k(_ v: Double) -> String { String(Int((v / cur.rate).rounded())) }
            var table = ["STARTERS \(code) trade own grant loan kit staff nw0 nw5 nw12 nw26"]
            for r in rows {
                table.append([r.trade, k(r.own), k(r.grant), k(r.loan), k(r.kit), String(r.staff)].joined(separator: " ") + " "
                             + Self.checkWeeks.map { k(r.nw[$0] ?? 0) }.joined(separator: " "))
            }
            print(table.joined(separator: "\n"))
            XCTAssertEqual(Set(rows.map { $0.own }).count, 1, "\(code): every starter brings the same savings")
            for w in [0, 5] {
                let mid = Self.median(rows.compactMap { $0.nw[w] })
                XCTAssertGreaterThan(mid, 0, "\(code) week \(w)")
                for r in rows {
                    let v = r.nw[w] ?? 0
                    XCTAssertEqual(v, mid, accuracy: abs(mid) * 0.3, "\(code) \(r.trade): net worth \(k(v)) at week \(w) against a median of \(k(mid))")
                }
            }
            for r in rows {
                XCTAssertLessThanOrEqual(r.grant, r.own * 0.5 + 100, "\(code) \(r.trade): the grant stays a small share of the savings")
                XCTAssertTrue(r.trophyWeeks.allSatisfy { $0 >= Trophies.quietWeeks }, "\(code) \(r.trade): a trophy in the first weeks \(r.trophyWeeks)")
                XCTAssertLessThan(r.nw[26] ?? 0, (r.nw[0] ?? 0) * 3, "\(code) \(r.trade): half a year on defaults does not triple the start")
            }
        }
    }

    func testTheGrantCountsForNoGoal() throws {
        let e = try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 7, story: .fresh, tradeID: "cafe", companyName: "Test Co")
        let grant = StartGrant.amount(e.state)
        XCTAssertGreaterThan(grant, 0)
        let plain = Valuation.netWorth(e.state, trades: e.data.catalog)
        let goals = Valuation.netWorth(e.state, trades: e.data.catalog, forGoals: true)
        XCTAssertEqual(plain.personal - goals.personal, grant, accuracy: 0.5)
    }

    func testTheGymWaitsForTheSecondCompanyLevel() throws {
        XCTAssertFalse(TradeUnlocks.isStarter("gym"))
        XCTAssertThrowsError(try GameEngine.newGame(countryCode: "NO", playerName: "T", seed: 7, story: .fresh, tradeID: "gym", companyName: "Test Co"))
        let gym = try XCTUnwrap(try TradeCatalog.bundled()["gym"])
        XCTAssertEqual(TradeUnlocks.feature(for: gym), .newCompany)
    }
}
