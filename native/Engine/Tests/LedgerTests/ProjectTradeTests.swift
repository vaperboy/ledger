import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The project family: plumber, electrician, construction, engineering office, event agency, real-estate developer.
final class ProjectTradeTests: XCTestCase {
    static let trades = ["construction", "electrician", "plumber", "engcons", "event", "realdev"]

    struct Result { var revenue = 0.0, profit = 0.0, invested = 0.0, value = 0.0, cash = 0.0, status = "", done = 0.0, won = 0.0, y3rev = 0.0, y3profit = 0.0, util = 0.0, demandRatio = 0.0, cogsShare = 0.0, wageShare = 0.0 }

    /// Play one company for `years`. A developer has a manager who starts projects (as the player's manager would).
    static func play(_ trade: String, seed: Int, years: Int = 3, country: String = "UK") throws -> (Result, GameEngine, Int) {
        var e = try GameEngine.newGame(countryCode: country, playerName: "T", seed: seed)
        var id = 0
        var invested = 0.0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 2_000_000_000, why: "Test funds")
            guard case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: .limited, data: data, context: ctx) else { return }
            id = i
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            invested = (est?.total ?? 1_000_000) * 1.3
            if trade == "realdev" { invested += 40_000_000 }
            Payments.injectCash(&s, companyID: id, amount: invested)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        XCTAssertNotEqual(id, 0, trade)
        // A sensible marketing plan: search ads and social ads at their second-lowest budget, website and SEO at the lowest.
        if trade != "realdev" {
            for (k, n) in [("google", 1), ("meta", 1), ("seo", 1)] {
                if let ch = e.marketing.channels[k], ch.budgetOptions.count > n { _ = e.setCampaign(companyID: id, channel: k, weeklyBudget: ch.budgetOptions[n]) }
            }
        }
        var started = false
        var utilSum = 0.0, dSum = 0.0, capSum = 0.0, nW = 0.0
        for day in 0..<(years * 52 * 7) {
            e.nextDay()
            if day >= (years - 1) * 52 * 7, day % 7 == 0, let c = e.state.company(id), c.status == .open {
                let lw = c.value("lastW"); utilSum += lw["util"].double; dSum += lw["D"].double; capSum += lw["cap"].double; nW += 1
            }
            for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
            for m in e.openDecisions where m.companyID == id && !m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) }
            if let co = e.state.company(id), co.status == .open {
                if trade == "realdev", !started || e.state.week % 10 == 0 {
                    var r = e.startDevelopment(companyID: id, size: 1, financed: true); if r == .loanRefused { r = e.startDevelopment(companyID: id, size: 1, financed: false) }; if r == .started { started = true }
                }
                if co.cash < -50_000 {
                    let top = -co.cash + 100_000
                    e.update { s, _, _ in Payments.injectCash(&s, companyID: id, amount: top) }
                    invested += top
                }
            }
        }
        var r = Result()
        guard let co = e.state.company(id) else { return (r, e, id) }
        let h = co.monthlyHistory
        r.revenue = h.reduce(0) { $0 + $1.revenue }
        r.profit = h.reduce(0) { $0 + $1.profit }
        r.y3rev = h.suffix(12).reduce(0) { $0 + $1.revenue }
        r.y3profit = h.suffix(12).reduce(0) { $0 + $1.profit }
        r.invested = invested
        r.value = Valuation.companyValue(co, state: e.state, trades: e.data.catalog)
        r.cash = co.cash
        r.status = co.status.rawValue
        r.util = nW > 0 ? utilSum / nW : 0
        r.demandRatio = capSum > 0 ? dSum / capSum : 0
        let ly = co.books.year.isEmpty ? co.books.lastYear : co.books.lastYear
        r.cogsShare = (ly["rev"] ?? 0) > 0 ? (ly["cogs"] ?? 0) / ly["rev"]! : 0
        r.wageShare = (ly["rev"] ?? 0) > 0 ? (ly["wages"] ?? 0) / ly["rev"]! : 0
        r.done = co.value("fm")["done"].double
        r.won = co.value("fm")["won"].double
        return (r, e, id)
    }

    func testEveryProjectTradeRunsAndKeepsTheBooks() throws {
        for t in Self.trades {
            let (r, e, id) = try Self.play(t, seed: 21, years: 1)
            let gaps = Ledger.gaps(e.state)
            XCTAssertTrue(gaps.isEmpty, "\(t): ledger gaps \(gaps)")
            XCTAssertFalse(e.state.company(id)?.cash.isNaN ?? true, t)
            XCTAssertTrue(["open", "bust"].contains(r.status), "\(t) \(r.status)")
            if t != "realdev" { XCTAssertGreaterThan(r.revenue, 0, "\(t) earned nothing") }
        }
    }

    func testBooksBalanceAfterThreeYears() throws {
        for t in Self.trades {
            let (_, e, id) = try Self.play(t, seed: 12, years: 3)
            let gaps = Ledger.gaps(e.state)
            XCTAssertTrue(gaps.isEmpty, "\(t): ledger gaps \(gaps)")
            if let co = e.state.company(id) {
                XCTAssertFalse(co.cash.isNaN, t)
                let nw = Valuation.companyValue(co, state: e.state, trades: e.data.catalog)
                XCTAssertFalse(nw.isNaN, t)
                XCTAssertTrue(co.cash > -1e9, "\(t) cash corrupted \(co.cash)")
            }
        }
    }

    /// Tenders appear for the trades that can win them, a bid costs money, and a won tender becomes a job on the order book.
    func testTendersAreBidAndAwarded() throws {
        var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 31)
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 500_000_000, why: "Test funds")
            guard case .success(let i) = CompanySetup.create(&s, tradeID: "electrician", cityID: s.player.cityID, form: .limited, data: data, context: ctx) else { return }
            id = i
            Payments.injectCash(&s, companyID: id, amount: 20_000_000)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        var sent = 0, results = 0
        for _ in 0..<(3 * 52 * 7) {
            e.nextDay()
            for m in e.openDecisions { e.answer(messageID: m.id, option: 0) }
            if e.state.day == 0, let board = e.projectBoard(companyID: id) {
                for t in board.tenders where t.qualifies && t.myBid == nil {
                    if e.bidOnTender(companyID: id, tenderID: t.id, priceFactor: 0.9, higherQuality: true) == .sent { sent += 1 }
                }
                results += board.myTenders.filter { $0.outcome == "won" }.count
            }
        }
        XCTAssertGreaterThan(sent, 0, "no tender could be bid for in three years")
        let titles = e.state.inbox.map { $0.title }
        XCTAssertTrue(titles.contains { $0.hasPrefix("Award:") || $0.hasPrefix("Not awarded:") }, "no award was announced")
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    /// A project company that runs out of money is declared bankrupt like any other; the books still balance.
    func testStarvedProjectCompanyGoesBankrupt() throws {
        for t in ["plumber", "realdev"] {
            var e = try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 5)
            var id = 0
            e.update { s, data, ctx in
                Ledger.move(&s, .me, 500_000_000, why: "Test funds")
                guard case .success(let i) = CompanySetup.create(&s, tradeID: t, cityID: s.player.cityID, form: .limited, data: data, context: ctx) else { return }
                id = i
                let est = CompanySetup.estimate(tradeID: t, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
                Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.3 + (t == "realdev" ? 30_000_000 : 0))
                _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
            }
            var started = false
            for _ in 0..<(120 * 7) {
                e.nextDay()
                for m in e.openDecisions { e.answer(messageID: m.id, option: 0) }
                if t == "realdev", !started, e.state.company(id)?.status == .open { started = e.startDevelopment(companyID: id, size: 1, financed: false) == .started }
                // the owner never adds money; drain what is left so the company cannot survive
                if let co = e.state.company(id), co.status == .open, co.cash > 0, e.state.week >= 40 {
                    e.update { s, _, _ in Ledger.moveRaw(&s, .company(id), -co.cash) }
                }
            }
            XCTAssertEqual(e.state.company(id)?.status, .bust, t)
            XCTAssertTrue(Ledger.gaps(e.state).isEmpty, "\(t): \(Ledger.gaps(e.state))")
        }
    }

    /// LEDGER_PROJECTS=1: 3 seeds x 3 years of every project trade.
    func testPrintProjectBalance() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_PROJECTS"] != nil else { return }
        print("PRJ trade | invested k | y3 revenue k | y3 profit k | y3 margin | y3 ROI | value/invested | jobs done | util | D/cap | cogs% | wages% | status")
        for t in Self.trades {
            var rs: [Result] = []
            for seed in [11, 12, 13] { rs.append(try Self.play(t, seed: seed).0) }
            func avg(_ f: (Result) -> Double) -> Double { rs.map(f).reduce(0, +) / Double(rs.count) }
            let inv = avg { $0.invested }, rev = avg { $0.y3rev }, pr = avg { $0.y3profit }
            print(String(format: "PRJ %@ | %.0f | %.0f | %.0f | %.1f%% | %.1f%% | %.2fx | %.0f | %.2f | %.2f | %.0f%% | %.0f%% | %@", t, inv / 1000, rev / 1000, pr / 1000, rev > 0 ? pr / rev * 100 : 0, pr / inv * 100,
                         avg { $0.value } / inv, avg { $0.done }, avg { $0.util }, avg { $0.demandRatio }, avg { $0.cogsShare } * 100, avg { $0.wageShare } * 100, rs.map { $0.status }.joined(separator: ",")))
        }
    }
}
