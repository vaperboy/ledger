import XCTest
import GameCore
import Finance
import Simulation
@testable import Businesses

/// The market event log, the largest payment of the day and the market trend (read-only facts for the app's animations).
final class MarketEventsTests: XCTestCase {
    private func engineWithCafe(weeks: Int = 6, seed: Int = 777) throws -> (GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 400_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: "cafe", cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: "cafe", cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            _ = Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6 + 3_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        for _ in 0..<(weeks * 7) { e.nextDay() }
        return (e, id)
    }

    private func kinds(_ e: GameEngine) -> Set<MarketEvent.Kind> { Set(e.marketEvents(limit: 100).map { $0.kind }) }

    func testLoggingHelperKindsAndNewestFirst() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5)
        e.update { s, _, _ in
            // one kind a week: at most 3 are written in one week
            for (n, k) in MarketEvent.Kind.allCases.enumerated() { s.week = 10 + n; MarketEvents.log(&s, k, title: k.rawValue, detail: "d", companyID: 3, amount: 1.5, tone: "good") }
        }
        let ev = e.marketEvents(limit: 20)
        XCTAssertEqual(ev.count, MarketEvent.Kind.allCases.count)
        XCTAssertEqual(ev.first?.kind, MarketEvent.Kind.allCases.last)   // newest first
        XCTAssertEqual(Set(ev.map { $0.kind }), Set(MarketEvent.Kind.allCases))
        XCTAssertEqual(ev.first?.companyID, 3)
        XCTAssertEqual(e.marketEvents(limit: 2).count, 2)
    }

    func testSupplierPriceChangeFiresAtThreePercent() throws {
        var (e, _) = try engineWithCafe()
        e.update { s, data, _ in
            // let the log's 4-week rests (same fact, same index) pass, whatever the game announced by itself in the weeks before
            s.week += MarketEvents.dedupeWeeks + MarketEvents.supplierCooldown
            var mv = s.rest["mev"] ?? .object([:]); mv["seen"]["eco"] = .null; s.rest["mev"] = mv
            MarketEvents.weekly(&s, data: data)           // remembers the level
        }
        let supplierBefore: Int = e.marketEvents(limit: 100).filter { $0.kind == .supplierPriceChange }.count
        e.update { s, data, _ in
            s.economy.materials *= 1.02
            MarketEvents.weekly(&s, data: data)
        }
        let supplierAfter: Int = e.marketEvents(limit: 100).filter { $0.kind == .supplierPriceChange }.count
        XCTAssertEqual(supplierAfter, supplierBefore, "a 2% move is not announced")
        let before = e.marketEvents(limit: 100).count
        e.update { s, data, _ in s.week += 1; s.economy.materials *= 1.05; MarketEvents.weekly(&s, data: data) }
        let ev = e.marketEvents(limit: 100)
        XCTAssertEqual(ev.count, before + 1)
        XCTAssertEqual(ev.first?.kind, .supplierPriceChange)
        XCTAssertEqual(ev.first?.tone, "bad")
    }

    func testRivalForSaleAndLostShare() throws {
        var (e, id) = try engineWithCafe()
        var key = ""
        e.update { s, data, _ in
            key = Rivals.key(s.company(id)!)
            s.week += MarketEvents.dedupeWeeks   // the same rival's listing / share loss may already have been logged by the game itself
            // no rival is for sale at the baseline (the game may have listed one by itself), so the listing below is a real change
            var mk0 = s.rest["mk"]!
            mk0[key]["riv"] = .array(mk0[key]["riv"].array.map { var r = $0; r["listed"] = .bool(false); return r })
            s.rest["mk"] = mk0
            MarketEvents.weekly(&s, data: data)           // baseline
            var mk = s.rest["mk"]!
            var riv = mk[key]["riv"].array
            XCTAssertFalse(riv.isEmpty)
            riv[0]["listed"] = .bool(true)
            mk[key]["riv"] = .array(riv)
            s.rest["mk"] = mk
            s.week += 1
            MarketEvents.weekly(&s, data: data)           // the listing (one market-wide event a week)
            s.week += 1
            // pretend the first rival had five points more share last week
            let rid = String(riv[0]["id"].int)
            var m = s.rest["mev"]!
            m["seen"]["share"][rid] = .number(m["seen"]["share"][rid].double + 0.05)
            s.rest["mev"] = m
            MarketEvents.weekly(&s, data: data)
        }
        let k = kinds(e)
        XCTAssertTrue(k.contains(.acquisitionOpportunity))
        XCTAssertTrue(k.contains(.competitorLostShare))
        let lost = e.marketEvents(limit: 100).first { $0.kind == .competitorLostShare }
        XCTAssertEqual(lost?.tone, "good")
        XCTAssertLessThan(lost?.amount ?? 0, -0.01)
    }

    func testRecognitionCarriesEmployeeID() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5)
        e.update { s, _, _ in
            MarketEvents.log(&s, .recognition, title: "Anna: promise kept", detail: "x", tone: "good", employeeID: 42)
            MarketEvents.log(&s, .majorContract, title: "c", detail: "x")
        }
        let ev = e.marketEvents(limit: 5)
        XCTAssertNil(ev.first?.employeeID)
        XCTAssertEqual(ev.last?.employeeID, 42)
    }

    func testStartingAbroadYourselfIsNotAMarketEvent() throws {
        var (e, id) = try engineWithCafe()
        e.update { s, data, _ in
            MarketEvents.weekly(&s, data: data)
            let i = s.companyIndex(id)!
            s.companies[i].countryCode = "DE"
            MarketEvents.weekly(&s, data: data)
            MarketEvents.weekly(&s, data: data)
        }
        XCTAssertEqual(e.marketEvents(limit: 100).filter { $0.kind == .newCountry }.count, 0, "your own start is not news; a rival group entering is (RivalGroups)")
    }

    func testMajorContractThreshold() throws {
        var (e, id) = try engineWithCafe()
        e.update { s, _, _ in
            let i = s.companyIndex(id)!
            s.companies[i].set("rv26", .array([.number(1000), .number(1000)]))   // yearly sales 52,000
            let co = s.companies[i]
            MarketEvents.noteContractOffer(&s, company: co, customer: "Acme", worth: 2000)   // under 5 percent
            XCTAssertTrue(MarketEvents.events(s, limit: 10).filter { $0.kind == .majorContract }.isEmpty)
            MarketEvents.noteContractOffer(&s, company: co, customer: "Acme", worth: 3000)   // over 5 percent
        }
        XCTAssertEqual(e.marketEvents(limit: 10).filter { $0.kind == .majorContract }.count, 1)
    }

    func testCompetitorLaunchAndRecognitionAreLoggedByTheirHelperOnly() throws {
        // Both come from random weekly draws (rival offer, store opening) or from a kept promise / finished course, which need long set-ups:
        // the shared logging helper is tested instead, and the hooks are plain calls to it next to the existing notes.
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 9)
        e.update { s, _, _ in
            MarketEvents.log(&s, .competitorLaunch, title: "Rival launches 10% off", detail: "x", companyID: 1, amount: 10, tone: "bad")
            MarketEvents.log(&s, .recognition, title: "Anna: promise kept", detail: "x", tone: "good")
        }
        XCTAssertEqual(kinds(e), [.competitorLaunch, .recognition])
    }

    func testCapDropsTheOldest() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5)
        e.update { s, _, _ in for n in 0..<75 { s.week = 100 + n; MarketEvents.log(&s, .recognition, title: "e\(n)", detail: "") } }   // one a week: the weekly cap of 3 does not bite
        let ev = e.marketEvents(limit: 500)
        XCTAssertEqual(ev.count, 60)
        XCTAssertEqual(ev.first?.title, "e74")
        XCTAssertEqual(ev.last?.title, "e15")
    }

    func testSaveReloadEqualityAndNoInboxSpam() throws {
        var (e, _) = try engineWithCafe(weeks: 3)
        let inbox = e.state.inbox.count
        e.update { s, _, _ in MarketEvents.log(&s, .newCountry, title: "x", detail: "y", companyID: 2, amount: 4, tone: "n"); MarketEvents.notePayment(&s, companyID: 2, amount: 50_000_000, from: "A") }
        XCTAssertEqual(e.state.inbox.count, inbox)
        let loaded = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(e.state))
        XCTAssertEqual(MarketEvents.events(loaded, limit: 100), e.marketEvents(limit: 100))
        XCTAssertEqual(MarketEvents.largestPayment(loaded, companyID: nil)?.amount, 50_000_000)
        XCTAssertEqual(loaded.rest["mev"], e.state.rest["mev"])
    }

    func testDeterministic() throws {
        let (a, _) = try engineWithCafe(weeks: 12, seed: 4242)
        let (b, _) = try engineWithCafe(weeks: 12, seed: 4242)
        XCTAssertEqual(a.marketEvents(limit: 100), b.marketEvents(limit: 100))
        XCTAssertEqual(a.state.rest["mev"], b.state.rest["mev"])
    }

    func testLargestPaymentResetsDaily() throws {
        var (e, id) = try engineWithCafe(weeks: 3)
        XCTAssertNil(e.largestPaymentToday(companyID: 999))
        e.update { s, _, _ in
            MarketEvents.notePayment(&s, companyID: id, amount: 100_000, from: "A")
            MarketEvents.notePayment(&s, companyID: id, amount: 400_000, from: "Big Co")
            MarketEvents.notePayment(&s, companyID: id, amount: 200_000, from: "B")
            MarketEvents.notePayment(&s, companyID: 77, amount: 9_000_000, from: "Other")
        }
        let mine = try XCTUnwrap(e.largestPaymentToday(companyID: id))
        XCTAssertEqual(mine.amount, 400_000); XCTAssertEqual(mine.from, "Big Co"); XCTAssertEqual(mine.companyID, id)
        XCTAssertEqual(e.largestPaymentToday(companyID: nil)?.companyID, 77)
        e.update { s, _, _ in s.day = (s.day + 1) % 7; if s.day == 0 { s.week += 1 } }
        XCTAssertNil(e.largestPaymentToday(companyID: id))
        // real trading books today's takings
        var (t, tid) = try engineWithCafe(weeks: 3)
        var got = false
        for _ in 0..<14 { t.nextDay(); if let p = t.largestPaymentToday(companyID: tid) { XCTAssertGreaterThan(p.amount, 0); got = true } }
        XCTAssertTrue(got)
    }

    func testMarketTrendShape() throws {
        let (e, id) = try engineWithCafe(weeks: 8)
        let t = e.marketTrend(companyID: id)
        XCTAssertEqual(t.points.count, 30)
        XCTAssertTrue(t.points.allSatisfy { $0.isFinite && $0 > 0.5 && $0 < 1.5 })
        let key = Rivals.key(try XCTUnwrap(e.state.company(id)))
        XCTAssertEqual(t.points.last ?? 0, e.state.rest["mk"]?[key]["pi"].double ?? -1, accuracy: 0.05)
        XCTAssertTrue(t.priceIndexChangeThisMonth.isFinite)
        XCTAssertEqual(e.marketTrend(companyID: 123456).points.count, 0)
    }
}
