import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Energy, the salmon farm, the holding company and the football club: they run, keep the books balanced, and earn realistic money.
final class SpecialTradesTests: XCTestCase {
    static func engine(_ country: String = "NO", seed: Int = 7) throws -> GameEngine {
        var e = try GameEngine.newGame(countryCode: country, playerName: "T", seed: seed)
        e.update { s, _, _ in Ledger.move(&s, .me, 20_000_000_000, why: "Test funds") }
        return e
    }

    static func start(_ e: inout GameEngine, _ trade: String, extra: Double = 0) -> Int {
        var id = 0
        e.update { s, data, ctx in
            guard case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: .limited, data: data, context: ctx) else { return }
            id = i
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.3 + extra)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        return id
    }

    static func play(_ e: inout GameEngine, days: Int) {
        for _ in 0..<days {
            e.nextDay()
            for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
        }
    }

    func testPowerOilSalmonRunWithBalancedBooks() throws {
        for trade in ["power", "oilgas", "salmon"] {
            var e = try Self.engine()
            let id = Self.start(&e, trade, extra: 500_000_000)
            Self.play(&e, days: 52 * 7 * 2)
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(trade): \(Ledger.gaps(e.state))")
            let co = try XCTUnwrap(e.state.company(id))
            XCTAssertEqual(co.status, .open, trade)
            XCTAssertFalse(co.cash.isNaN)
        }
    }

    func testOilDiscoveryIsADecisionAndCanBeSold() throws {
        var e = try Self.engine()
        e.update { s, _, _ in Ledger.move(&s, .me, 200_000_000_000, why: "More test funds") }
        let id = Self.start(&e, "oilgas", extra: 100_000_000_000)
        e.setKnob(companyID: id, knob: "risk", option: 2)
        var hit = false
        for _ in 0..<40 where !hit { hit = e.exploreForOil(companyID: id) == .hit }
        XCTAssertTrue(hit, "a frontier strategy should find something in 60 wells")
        let m = try XCTUnwrap(e.openDecisions.first { $0.actionID == "oil24" })
        let before = try XCTUnwrap(e.state.company(id)).cash
        XCTAssertTrue(e.answer(messageID: m.id, option: 2))
        XCTAssertGreaterThan(try XCTUnwrap(e.state.company(id)).cash, before)
        XCTAssertTrue(e.oilFields(companyID: id).filter { $0.state == "dev" }.count < 60)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testHoldingOwnsCompaniesAndShowsInNetWorth() throws {
        var e = try Self.engine("UK")
        let cafe = Self.start(&e, "cafe")
        let before = e.netWorth.total
        let r = e.createHolding(name: "Test Holding", companies: [cafe])
        guard case .success(let hid) = r else { return XCTFail("holding not created: \(r)") }
        XCTAssertEqual(e.state.company(cafe)?.holdingID, hid)
        Self.play(&e, days: 7)
        // The cafe is counted inside the holding, not twice and not lost.
        let after = e.netWorth
        XCTAssertGreaterThan(after.companies, 0)
        XCTAssertLessThan(abs(after.total - before), before.magnitude * 0.2 + 3_000_000)
        Self.play(&e, days: 52 * 7)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        let o = try XCTUnwrap(e.holdingOverview(companyID: hid))
        XCTAssertEqual(o.subsidiaries.count, 1)
        XCTAssertTrue(e.holdingInvest(holdingID: hid, amount: 1000) || e.state.company(hid)!.cash < 1000)
    }

    func testFootballClubBuyAndPlayASeason() throws {
        var e = try Self.engine("NO")
        let clubs = e.clubsForSale(countryCode: "NO")
        XCTAssertEqual(clubs.count, 16)
        // Make an offer high enough to be accepted for a listed club, or found one.
        var bought = 0
        for c in clubs where !c.isFixed {
            let offer = e.offerForClub(clubID: c.id, multiple: 3)
            if offer.answer == .accept || offer.answer == .counter, let p = offer.price {
                if case .ok(let id) = e.buyClub(clubID: c.id, price: p) { bought = id; break }
            }
        }
        if bought == 0, case .ok(let id) = e.foundClub(countryCode: "NO") { bought = id }
        XCTAssertNotEqual(bought, 0)
        Self.play(&e, days: 52 * 7 * 2)
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(Ledger.gaps(e.state))")
        let sum = try XCTUnwrap(e.clubSummary(companyID: bought))
        XCTAssertGreaterThan(sum.table.count, 10)
        // Legacy value rule: football value plus cash, minus what it owes, plus 80% of what was paid for players.
        let co = try XCTUnwrap(e.state.company(bought))
        let owed = e.state.loans.filter { $0.companyID == bought }.reduce(0) { $0 + $1.balance }
        let expected = (co.value("fm")["val"].double + co.cash).rounded() - owed + co.value("fm")["book"].double * 0.8
        XCTAssertEqual(Valuation.companyValue(co, state: e.state, trades: e.data.catalog), expected.rounded(), accuracy: 1)
        XCTAssertGreaterThanOrEqual(e.state.company(bought)?.value("fm")["hist"].array.count ?? 0, 1, "a season should have finished")
    }

    /// Prints profit and return for the new trades (3 seeds x 3 years). LEDGER_BALANCE=1
    func testPrintBalanceOfSpecialTrades() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_BALANCE"] != nil else { return }
        for (trade, country) in [("power", "NO"), ("power", "UK"), ("oilgas", "NO"), ("oilgas", "UK"), ("salmon", "NO"), ("club", "NO"), ("club", "UK")] {
            var lines: [String] = []
            for seed in [11, 22, 33] {
                var e = try Self.engine(country, seed: seed)
                var id = 0
                var invested = 0.0
                if trade == "club" {
                    let clubs = e.clubsForSale(countryCode: country).filter { !$0.isFixed }
                    let mid = clubs[clubs.count / 2]
                    for c in [mid] + clubs {
                        for _ in 0..<2 {
                            let o = e.offerForClub(clubID: c.id, multiple: 4)
                            if let p = o.price, o.answer == .accept || o.answer == .counter, case .ok(let i) = e.buyClub(clubID: c.id, price: p) { id = i; invested = p; break }
                        }
                        if id != 0 { break }
                    }
                    if id == 0, case .ok(let i) = e.foundClub(countryCode: country) { id = i; invested = e.foundingCost(countryCode: country) ?? 0 }
                } else {
                    id = Self.start(&e, trade, extra: trade == "salmon" ? 100_000_000 : 300_000_000)
                    if trade == "oilgas" { e.update { s, _, _ in Payments.injectCash(&s, companyID: id, amount: 1_500_000_000) }; _ = e.buyOilStake(companyID: id, thousandBarrels: 5000) }
                    invested = e.state.company(id)?.value("inj").double ?? 0
                    let est = CompanySetup.estimate(tradeID: trade, cityID: e.state.player.cityID, form: .limited, size: 1, state: e.state, data: e.data)
                    invested = (est?.total ?? 0)
                }
                guard id != 0 else { lines.append("seed \(seed): not started"); continue }
                var extra = 0.0
                for _ in 0..<(3 * 52 * 7) {
                    e.nextDay()
                    for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
                    if let co = e.state.company(id), co.status.isLive, co.cash < -1_000_000 { let t = -co.cash + 5_000_000; e.update { s, _, _ in Payments.injectCash(&s, companyID: id, amount: t) }; extra += t }
                }
                guard let co = e.state.company(id) else { continue }
                let h = co.monthlyHistory
                let y = (0..<3).map { k -> (Double, Double) in
                    let part = h.dropFirst(12 * k).prefix(12)
                    return (part.reduce(0) { $0 + $1.revenue }, part.reduce(0) { $0 + $1.profit })
                }
                let cur = e.homeCurrency
                let wr = co.books.total["wages"] ?? 0, rv = co.books.total["rev"] ?? 0
                lines.append("seed \(seed): invested \(cur.short(invested)) (+\(cur.short(extra))), rev/profit y1 \(cur.short(y[0].0))/\(cur.short(y[0].1)) y2 \(cur.short(y[1].0))/\(cur.short(y[1].1)) y3 \(cur.short(y[2].0))/\(cur.short(y[2].1)), value \(cur.short(Valuation.companyValue(co, state: e.state, trades: e.data.catalog))), wages/rev \(rv > 0 ? Int(wr / rv * 100) : 0)%, \(co.status.rawValue)")
                XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
            }
            print("PROBE \(trade) \(country)\n  " + lines.joined(separator: "\n  "))
        }
    }
}
