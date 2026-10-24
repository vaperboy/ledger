import XCTest
import GameCore
import Countries
import Finance
import Businesses
import Simulation
import SaveSystem

/// Weekly, monthly and yearly reports: they must come from the books, add up, be the same every time, and survive a save.
final class ReportsTests: XCTestCase {
    func newEngine(seed: Int = 4242) throws -> GameEngine { try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed) }

    func startCompany(_ e: inout GameEngine, trade: String, fund: Double = 0) throws -> Int {
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 50_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, form: .limited, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, form: .limited, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6 + fund)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        XCTAssertNotEqual(id, 0)
        return id
    }

    /// What the books and the account said at the end of the seventh day, just before the week is reported.
    struct Frozen {
        var booksTotal: [Int: [String: Double]] = [:]
        var cash = 0.0, companyCash = 0.0, netWorth = 0.0
        var week = 0
    }

    /// Play whole weeks. Returns the books as they stood at the end of the last week (before its report was written).
    @discardableResult
    func play(_ e: inout GameEngine, weeks: Int) -> Frozen {
        var f = Frozen()
        for _ in 0..<weeks {
            while e.state.day != 6 && !e.state.isGameOver { e.nextDay(); answerPayroll(&e) }
            f = Frozen(booksTotal: Dictionary(e.state.companies.map { ($0.id, $0.books.total) }, uniquingKeysWith: { a, _ in a }),
                       cash: e.state.cash, companyCash: e.state.companies.reduce(0) { $0 + $1.cash }, netWorth: e.netWorth.total, week: e.state.week)
            e.nextDay()
            answerPayroll(&e)
            if e.state.isGameOver { break }
        }
        return f
    }
    func answerPayroll(_ e: inout GameEngine) { for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) } }

    func twoCompanyGame(seed: Int = 4242) throws -> GameEngine {
        var e = try newEngine(seed: seed)
        _ = try startCompany(&e, trade: "cafe", fund: 3_000_000)
        _ = try startCompany(&e, trade: "gym", fund: 6_000_000)
        return e
    }

    func json<T: Encodable>(_ x: T) throws -> String {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        return String(data: try enc.encode(x), encoding: .utf8) ?? ""
    }

    // MARK: Reconciliation

    func testWeeklyReportsAddUpToTheBooks() throws {
        var e = try twoCompanyGame()
        let f = play(&e, weeks: 20)
        let weeks = e.reports(.week)
        XCTAssertEqual(weeks.count, 20)
        XCTAssertEqual(weeks.map { $0.id }, Array(0..<20))
        // Group: the lines of all weeks equal the books of all companies since the start.
        var sum = ReportPnL()
        for w in weeks { sum = sum + w.group.pnl }
        var books = ReportPnL()
        for (_, b) in f.booksTotal { books = books + ReportPnL(booksDelta: b) }
        XCTAssertEqual(sum.revenue, books.revenue, accuracy: 0.01)
        XCTAssertEqual(sum.costs, books.costs, accuracy: 0.01)
        XCTAssertEqual(sum.tax, books.tax, accuracy: 0.01)
        XCTAssertEqual(sum.netProfit, books.netProfit, accuracy: 0.01)
        XCTAssertGreaterThan(sum.revenue, 0, "the companies should have traded")
        // And the same with the game's own definition of profit.
        let own = f.booksTotal.values.reduce(0) { $0 + Books.profit($1) }
        XCTAssertEqual(sum.profitBeforeTax, own, accuracy: 0.01)
        // Per company.
        for (id, b) in f.booksTotal {
            let mine = weeks.compactMap { $0.company(id) }.reduce(ReportPnL()) { $0 + $1.pnl }
            XCTAssertEqual(mine.revenue, b["rev"] ?? 0, accuracy: 0.01)
            XCTAssertEqual(mine.profitBeforeTax, Books.profit(b), accuracy: 0.01)
        }
        // The group is the sum of its companies.
        for w in weeks {
            let parts = w.companies.reduce(ReportPnL()) { $0 + $1.pnl }
            XCTAssertEqual(parts.revenue, w.group.pnl.revenue, accuracy: 0.01)
            XCTAssertEqual(parts.costs, w.group.pnl.costs, accuracy: 0.01)
            XCTAssertEqual(w.group.pnl.netProfit, w.group.pnl.revenue - w.group.pnl.costs - w.group.pnl.tax, accuracy: 0.001)
        }
        XCTAssertTrue(Ledger.gaps(e.state).isEmpty)
    }

    func testCashAndNetWorthChainAndMatchTheState() throws {
        var e = try twoCompanyGame()
        let f = play(&e, weeks: 14)
        let weeks = e.reports(.week)
        for (a, b) in zip(weeks, weeks.dropFirst()) {
            XCTAssertEqual(a.group.accountEnd, b.group.accountStart, accuracy: 0.001)
            XCTAssertEqual(a.group.companyCashEnd, b.group.companyCashStart, accuracy: 0.001)
            XCTAssertEqual(a.netWorthEnd.total, b.netWorthStart.total, accuracy: 0.001)
            XCTAssertEqual(b.previous?.id, a.id)
        }
        let last = try XCTUnwrap(weeks.last)
        XCTAssertEqual(last.group.accountEnd, f.cash, accuracy: 0.01)
        XCTAssertEqual(last.group.companyCashEnd, f.companyCash, accuracy: 0.01)
        XCTAssertEqual(last.netWorthEnd.total, f.netWorth, accuracy: 0.5)
        XCTAssertEqual(last.id, f.week)
        for w in weeks {
            // The account's movements explain its change exactly; the net worth parts add up to the total.
            XCTAssertEqual(w.group.accountFlows.reduce(0) { $0 + $1.amount }, w.group.accountEnd - w.group.accountStart, accuracy: 0.01)
            let n = w.netWorthEnd
            XCTAssertEqual(n.cash + n.investments + n.companies + n.luxury - n.debt, n.total, accuracy: 0.5)
            XCTAssertEqual(w.netWorthChange, w.netWorthEnd.total - w.netWorthStart.total, accuracy: 0.0001)
        }
    }

    func testMonthsAndYearsAreTheSumOfTheirWeeks() throws {
        var e = try twoCompanyGame()
        play(&e, weeks: 26)
        let weeks = e.reports(.week), months = e.reports(.month), years = e.reports(.year)
        XCTAssertGreaterThanOrEqual(months.count, 5)
        XCTAssertEqual(years.count, 1, "the first year of the game ends in December")
        for p in months + years {
            let inside = weeks.filter { $0.id >= p.firstWeek && $0.id <= p.lastWeek }
            XCTAssertEqual(inside.count, p.lastWeek - p.firstWeek + 1, "\(p.title): all weeks present")
            let sum = inside.reduce(ReportPnL()) { $0 + $1.group.pnl }
            XCTAssertEqual(sum.revenue, p.group.pnl.revenue, accuracy: 0.01, p.title)
            XCTAssertEqual(sum.costs, p.group.pnl.costs, accuracy: 0.01, p.title)
            XCTAssertEqual(sum.tax, p.group.pnl.tax, accuracy: 0.01, p.title)
            XCTAssertEqual(inside.reduce(0) { $0 + $1.group.customers }, p.group.customers, accuracy: 0.01, p.title)
            XCTAssertEqual(inside.first?.group.accountStart ?? 0, p.group.accountStart, accuracy: 0.01, p.title)
            XCTAssertEqual(inside.last?.group.accountEnd ?? 0, p.group.accountEnd, accuracy: 0.01, p.title)
            XCTAssertEqual(inside.first?.netWorthStart.total ?? 0, p.netWorthStart.total, accuracy: 0.5, p.title)
            XCTAssertEqual(inside.last?.netWorthEnd.total ?? 0, p.netWorthEnd.total, accuracy: 0.5, p.title)
        }
        for (a, b) in zip(months, months.dropFirst()) { XCTAssertEqual(a.lastWeek + 1, b.firstWeek) }
        let y = try XCTUnwrap(years.first)
        XCTAssertEqual(y.title, "2026")
        XCTAssertFalse(y.summary.isEmpty)
    }

    func testReportsAreBounded() throws {
        var e = try newEngine()
        _ = try startCompany(&e, trade: "kiosk")
        play(&e, weeks: 60)
        XCTAssertEqual(e.reports(.week).count, 26)
        XCTAssertEqual(e.reports(.week).last?.id, 59)
        XCTAssertLessThanOrEqual(e.reports(.month).count, 36)
        XCTAssertGreaterThanOrEqual(e.reports(.month).count, 12)
        XCTAssertEqual(e.reports(.year).count, 1)
    }

    func testPlayerMoneyIsClassified() throws {
        var e = try newEngine()
        let id = try startCompany(&e, trade: "cafe")
        let before = ReportCounters.totals(e.state)[ReportCounters.Key.invested] ?? 0
        XCTAssertTrue(e.putMoneyInto(companyID: id, amount: 1_000_000))
        let after = ReportCounters.totals(e.state)[ReportCounters.Key.invested] ?? 0
        XCTAssertEqual(after - before, -1_000_000, accuracy: 0.5)
        XCTAssertEqual(ReportCounters.key(forLabel: "Dividend from Café"), ReportCounters.Key.dividends)
        XCTAssertEqual(ReportCounters.key(forLabel: "Bought ACME"), ReportCounters.Key.markets)
        XCTAssertEqual(ReportCounters.key(forLabel: "Annual tax assessment (income, gains, wealth)"), ReportCounters.Key.tax)
        XCTAssertEqual(ReportCounters.key(forLabel: "something new"), ReportCounters.Key.other)
        // The owner's money shows in the report of the week it moved, on both sides.
        play(&e, weeks: 1)
        let w = try XCTUnwrap(e.reports(.week).last)
        XCTAssertLessThan(w.group.accountFlows.first { $0.id == ReportCounters.Key.invested }?.amount ?? 0, -999_000)
        XCTAssertGreaterThan(w.group.ownerIn, 1_000_000)
    }

    /// Not a pass/fail test: prints a sample year and month for reading (LEDGER_REPORT_SAMPLE=1).
    func testPrintSample() throws {
        guard ProcessInfo.processInfo.environment["LEDGER_REPORT_SAMPLE"] != nil else { return }
        var e = try twoCompanyGame()
        play(&e, weeks: 26)
        let y = e.reports(.year)[0]
        print("YEAR", y.title, y.range, y.summary)
        for c in y.companies { print("CO", c.name, c.pnl.revenue, c.pnl.costs, c.pnl.tax, c.customers, c.capacityUse as Any, c.hired, c.left, c.reputationStart, c.reputationEnd, c.ownerIn, c.ownerOut, c.loansTaken, c.valueStart, c.valueEnd, c.operatingAndOther) }
        print("G", y.group.taxPaid, y.group.dividendsReceived, y.group.personalTax, y.group.events.map { $0.text }, y.group.breakdowns, y.group.complaints, y.group.decisionsAnswered, y.group.accountFlows.map { "\($0.label)=\($0.amount)" })
        let m = e.reports(.month)[2]
        print("MONTH", m.title, m.range, m.summary, m.previous?.title as Any)
        print("NW", y.netWorthStart, y.netWorthEnd)
    }

    // MARK: Determinism, summary, saves

    func testSameSeedGivesTheSameReports() throws {
        var a = try twoCompanyGame(seed: 77), b = try twoCompanyGame(seed: 77)
        play(&a, weeks: 18); play(&b, weeks: 18)
        // The engine sums some floating point numbers in dictionary order, so two runs agree to the last few bits, not always exactly.
        for k in ReportKind.allCases { XCTAssertTrue(try close(a.reports(k), b.reports(k)), "\(k)") }
        var c = try twoCompanyGame(seed: 78)
        play(&c, weeks: 18)
        XCTAssertFalse(try close(a.reports(.week), c.reports(.week)))
    }

    /// Writing a report is a pure function of the state: the same state gives exactly the same report, byte for byte.
    func testReportsArePureFunctionsOfTheState() throws {
        var e = try twoCompanyGame()
        play(&e, weeks: 6)
        while e.state.day != 6 { e.nextDay(); answerPayroll(&e) }
        var x = e, y = e
        x.closeReportPeriods(); y.closeReportPeriods()
        XCTAssertEqual(x.state, y.state)
        for k in ReportKind.allCases { XCTAssertEqual(try json(x.reports(k)), try json(y.reports(k))) }
        XCTAssertEqual(x.reports(.week).count, 7)
    }

    func close<T: Encodable>(_ a: T, _ b: T) throws -> Bool {
        func same(_ x: JSONValue, _ y: JSONValue) -> Bool {
            switch (x, y) {
            case (.number(let p), .number(let q)): return abs(p - q) <= 1e-6 * max(1, abs(p), abs(q))
            case (.array(let p), .array(let q)): return p.count == q.count && zip(p, q).allSatisfy { same($0, $1) }
            case (.object(let p), .object(let q)): return Set(p.keys) == Set(q.keys) && p.allSatisfy { same($0.value, q[$0.key]!) }
            default: return x == y
            }
        }
        let ja = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(a))
        let jb = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(b))
        return same(ja, jb)
    }

    func testSummaryIsWrittenFromTheNumbers() throws {
        var e = try twoCompanyGame()
        play(&e, weeks: 10)
        let cur = e.homeCurrency
        for w in e.reports(.week) where w.hasActivity {
            XCTAssertTrue((3...5).contains(w.summary.count), "\(w.title): \(w.summary)")
            XCTAssertTrue(w.summary.allSatisfy { $0.hasSuffix(".") && $0.count > 15 }, "\(w.summary)")
            let figure = cur.short(abs(w.group.pnl.netProfit)).replacingOccurrences(of: "\u{00A0}", with: " ")
            XCTAssertTrue(w.summary[0].contains(figure) || w.summary[0].contains("No company"), "\(w.summary[0]) should name \(figure)")
            if let b = w.best, w.worst != nil { XCTAssertTrue(w.summary.joined().contains(b.name)) }
        }
        let withPrev = try XCTUnwrap(e.reports(.week).last(where: { $0.previous != nil && abs($0.previous!.pnl.netProfit) >= 1 }))
        XCTAssertTrue(withPrev.summary[0].contains("last week"), withPrev.summary[0])
    }

    func testPromptsAreOfferedOnceAndDismissed() throws {
        var e = try twoCompanyGame()
        XCTAssertNil(e.pendingReportPrompt())
        play(&e, weeks: 4)
        let p = try XCTUnwrap(e.pendingReportPrompt())
        XCTAssertEqual(p.kind, .month, "week 4 closes the first month (October) as well as the week")
        e.dismissReportPrompt(p)
        XCTAssertNil(e.pendingReportPrompt())
        play(&e, weeks: 1)
        XCTAssertEqual(e.pendingReportPrompt()?.kind, .week)
    }

    func testSaveRoundTripKeepsReportsAndPlayContinuesTheSame() throws {
        var e = try twoCompanyGame()
        play(&e, weeks: 9)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-reports-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaveStore(directory: dir)
        try store.save(e.state, summary: store.summary(of: e.state, trades: e.data.catalog))
        let loaded = try store.load()
        XCTAssertEqual(loaded, e.state)
        let (data, events, marketing) = try GameEngine.loadResources()
        var b = GameEngine(state: loaded, data: data, events: events, marketing: marketing)
        for k in ReportKind.allCases { XCTAssertEqual(try json(b.reports(k)), try json(e.reports(k))) }
        XCTAssertEqual(b.reports(.week).count, 9)
        play(&e, weeks: 8); play(&b, weeks: 8)
        for k in ReportKind.allCases { XCTAssertTrue(try close(b.reports(k), e.reports(k)), "\(k) after loading") }
        XCTAssertEqual(b.reports(.week).count, 17)
    }

    func testOldSaveWithoutReportsLoadsWithEmptyListsAndStartsReporting() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "save_cafe_week15", withExtension: "json", subdirectory: "Golden"))
        var s = try LegacyImporter.importText(String(contentsOf: url))
        XCTAssertNil(s.rest["reports"])
        let (data, events, marketing) = try GameEngine.loadResources()
        var e = GameEngine(state: s, data: data, events: events, marketing: marketing)
        for k in ReportKind.allCases { XCTAssertTrue(e.reports(k).isEmpty) }
        XCTAssertNil(e.pendingReportPrompt())
        let gapsBefore = Ledger.gaps(e.state).count
        play(&e, weeks: 4)
        // The first week end only starts the books; there is nothing earlier to compare with, and nothing is invented.
        XCTAssertEqual(e.reports(.week).count, 3)
        XCTAssertEqual(e.reports(.week).first?.id, 16)
        XCTAssertEqual(Ledger.gaps(e.state).count, gapsBefore, "playing does not add gaps to the books")
        // Saving it and reading it back keeps what was written.
        s = e.state
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-reports-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaveStore(directory: dir)
        try store.save(s, summary: store.summary(of: s, trades: data.catalog))
        XCTAssertEqual(try store.load().rest["reports"], s.rest["reports"])
    }

    func testVersionOneEnvelopeIsMigrated() throws {
        var e = try newEngine()
        play(&e, weeks: 1)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-reports-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaveStore(directory: dir)
        try store.save(e.state, summary: store.summary(of: e.state, trades: e.data.catalog))
        // Rewrite the file the way the previous app version wrote it: envelope version 1, no report fields.
        let file = dir.appendingPathComponent("current.ledgersave")
        var env = try XCTUnwrap(try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file)).object as [String: JSONValue]?)
        env["version"] = .number(1)
        var st = env["state"]?.object ?? [:]
        for k in ["reports", "rptBase", "rptCum", "rptSeen"] { st[k] = nil }
        env["state"] = .object(st)
        try JSONEncoder().encode(JSONValue.object(env)).write(to: file)
        let old = try store.load()
        XCTAssertEqual(old.rest["reports"]?["w"].array.count, 0)
        XCTAssertEqual(old.rest["reports"]?["y"].array.count, 0)
        let (data, events, marketing) = try GameEngine.loadResources()
        let again = GameEngine(state: old, data: data, events: events, marketing: marketing)
        XCTAssertTrue(again.reports(.week).isEmpty)
        // A save from a newer app is still refused.
        env["version"] = .number(Double(NativeSaveFormat.currentVersion + 1))
        try JSONEncoder().encode(JSONValue.object(env)).write(to: file)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("current.previous.ledgersave"))
        XCTAssertThrowsError(try store.load())
    }
}
