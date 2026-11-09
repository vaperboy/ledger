import XCTest
import GameCore
import Countries
import Finance
import Businesses
@testable import Simulation
import SaveSystem

/// The quarterly group review and the annual report: when they open, quarter boundaries in the day-by-day engine, grading, the saved
/// history, and a letter that never states a number that is not in the books.
final class GroupReviewTests: XCTestCase {
    func newEngine(seed: Int = 4242) throws -> GameEngine { try GameEngine.newGame(countryCode: "UK", playerName: "Tester", seed: seed) }

    func startCompany(_ e: inout GameEngine, trade: String, fund: Double = 0) throws {
        var id = 0
        e.update { s, data, ctx in
            Ledger.move(&s, .me, 50_000_000, why: "Test funds")
            if case .success(let i) = CompanySetup.create(&s, tradeID: trade, cityID: s.player.cityID, data: data, context: ctx) { id = i }
            let est = CompanySetup.estimate(tradeID: trade, cityID: s.player.cityID, size: 1, state: s, data: data)
            Payments.injectCash(&s, companyID: id, amount: (est?.total ?? 1_000_000) * 1.6 + fund)
            _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        }
        XCTAssertNotEqual(id, 0)
    }

    func twoCompanyGame() throws -> GameEngine {
        var e = try newEngine()
        try startCompany(&e, trade: "cafe", fund: 3_000_000)
        try startCompany(&e, trade: "gym", fund: 6_000_000)
        return e
    }

    func answerPayroll(_ e: inout GameEngine) { for m in e.openDecisions where m.actionID.hasPrefix("pay29") { e.answer(messageID: m.id, option: 0) } }

    /// Plays day by day to `week`; `onDay` runs after every day. Returns the game weeks (the week just closed) in which a review appeared.
    @discardableResult
    func play(_ e: inout GameEngine, toWeek week: Int, onDay: (inout GameEngine) -> Void = { _ in }) -> [Int] {
        var offers: [Int] = []
        var seen = false
        while e.state.week < week && !e.state.isGameOver {
            e.nextDay(); answerPayroll(&e)
            let has = e.state.rest["qrv"]?["offer"].isNull == false
            if has && !seen { offers.append(e.state.week - 1) }   // the week is advanced right after the reports close
            seen = has
            onDay(&e)
            if (e.state.rest["qrv"]?["offer"].isNull ?? true) { seen = false }
        }
        return offers
    }

    // MARK: Opening

    func testNothingForABrandNewPlayerWithOneCompany() throws {
        var e = try newEngine()
        try startCompany(&e, trade: "cafe", fund: 3_000_000)
        let offers = play(&e, toWeek: 27)
        XCTAssertTrue(offers.isEmpty)
        XCTAssertNil(e.reviewOffer)
        XCTAssertTrue(e.annualReports.isEmpty)
        XCTAssertTrue(e.reviewHistory.isEmpty)
    }

    func testRuleIsAFirstYearPlayed() throws {
        var e = try newEngine()
        XCTAssertFalse(Gates.reviewOpen(e.state))
        e.update { s, _, _ in s.week = 51 }
        XCTAssertFalse(Gates.reviewOpen(e.state))
        e.update { s, _, _ in s.week = 52 }
        XCTAssertTrue(Gates.reviewOpen(e.state))
        e.update { s, _, _ in s.week = 3 }
        try startCompany(&e, trade: "cafe")
        try startCompany(&e, trade: "gym")
        XCTAssertFalse(Gates.reviewOpen(e.state))
    }

    // MARK: Quarters, grading, history

    func testReviewsComeOnlyAtQuarterEndsAndTargetsAreGradedAtTheNext() throws {
        var e = try twoCompanyGame()
        var chosen: [String] = []
        var creditAtSet: Double = 0
        let offers = play(&e, toWeek: 40) { e in
            guard let o = e.reviewOffer else { return }
            // The review of a quarter that has just closed: pick the first two targets on offer.
            let kinds = Array(o.options.prefix(2).map { $0.kind })
            let r = e.setReviewTargets(kinds)
            XCTAssertNotNil(r)
            chosen.append(o.label)
            creditAtSet = e.state.credit
            XCTAssertNil(e.reviewOffer)
        }
        XCTAssertGreaterThanOrEqual(offers.count, 2, "two quarters in 40 weeks")
        for w in offers { XCTAssertTrue(GameCalendar.isMonthEnd(week: w) && GameCalendar.month(week: w) % 3 == 2, "week \(w) is not a quarter end") }
        XCTAssertEqual(chosen.first, "Oct to Dec 2026")
        XCTAssertGreaterThan(offers[0], 8, "the first review is not in the first weeks")
        let h = e.reviewHistory
        XCTAssertFalse(h.isEmpty)
        let first = h[0]
        XCTAssertEqual(first.label, "Jan to Mar 2027")
        XCTAssertEqual(first.targets.count, 2)
        XCTAssertNotNil(first.grade)
        XCTAssertTrue(first.targets.allSatisfy { $0.grade != nil && $0.result != nil })
        _ = creditAtSet
        // The history is the same after a save.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-review-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try SaveStore(directory: dir)
        try store.save(e.state, summary: store.summary(of: e.state, trades: e.data.catalog))
        let loaded = try store.load()
        let (data, events, marketing) = try GameEngine.loadResources()
        let b = GameEngine(state: loaded, data: data, events: events, marketing: marketing)
        XCTAssertEqual(b.reviewHistory, e.reviewHistory)
        XCTAssertEqual(b.reviewTargets, e.reviewTargets)
        XCTAssertEqual(b.annualReports, e.annualReports)
    }

    func testNotNowKeepsTheReviewForAWeekAndSkippingGradesNothing() throws {
        var e = try twoCompanyGame()
        var deferred = false, skipped = false
        play(&e, toWeek: 40) { e in
            guard let o = e.reviewOffer else { return }
            if !deferred {
                deferred = true
                let week = e.state.week
                e.deferReview()
                XCTAssertNil(e.reviewOffer)
                XCTAssertEqual(GroupReview.load(e.state).offer?.deferUntil, week + 1)
            } else if !skipped {
                skipped = true
                _ = o
                e.skipReview()
            }
        }
        XCTAssertTrue(deferred && skipped)
        XCTAssertTrue(e.reviewHistory.isEmpty, "no targets were set, so nothing was graded")
        XCTAssertTrue(e.reviewTargets.isEmpty)
    }

    func testGradeRules() {
        var t = ReviewTarget(kind: .sales)
        t.goal = 100; t.stretch = 108
        XCTAssertEqual(t.grade(for: 99.9), .missed)
        XCTAssertEqual(t.grade(for: 100), .met)
        XCTAssertEqual(t.grade(for: 108), .beat)
        var c = ReviewTarget(kind: .costs)
        c.goal = 0.80; c.stretch = 0.75
        XCTAssertEqual(c.grade(for: 0.81), .missed)
        XCTAssertEqual(c.grade(for: 0.80), .met)
        XCTAssertEqual(c.grade(for: 0.74), .beat)
        XCTAssertEqual(ReviewGrade.from(score: 0), .missed)
        XCTAssertEqual(ReviewGrade.from(score: 0.5), .met)
        XCTAssertEqual(ReviewGrade.from(score: 1.0), .met)
        XCTAssertEqual(ReviewGrade.from(score: 1.5), .beat)
        XCTAssertEqual(ReviewGrade.from(score: 2), .beat)
    }

    func testConsequenceIsMildAndHasNoSpiral() throws {
        let e = try twoCompanyGame()
        var s = e.state
        let cur = e.homeCurrency
        var t = ReviewTarget(kind: .sales); t.goal = 1_000_000_000; t.stretch = 2_000_000_000
        let act = ActiveTargets(label: "Q", endMonth: 0, targets: [t])
        var f = QuarterFigures(); f.sales = 10
        s.credit = 60
        let miss = GroupReview.grade(&s, active: act, f: f, cur: cur)
        XCTAssertEqual(miss.grade, .missed)
        XCTAssertEqual(s.credit, 59)
        s.credit = 40
        _ = GroupReview.grade(&s, active: act, f: f, cur: cur)
        XCTAssertEqual(s.credit, 40, "a low score is not pushed lower by a miss")
        var easy = ReviewTarget(kind: .sales); easy.goal = 1; easy.stretch = 5
        s.credit = 60
        XCTAssertEqual(GroupReview.grade(&s, active: ActiveTargets(label: "Q", endMonth: 0, targets: [easy]), f: f, cur: cur).grade, .beat)
        XCTAssertEqual(s.credit, 62)
        s.credit = 99.5
        _ = GroupReview.grade(&s, active: ActiveTargets(label: "Q", endMonth: 0, targets: [easy]), f: f, cur: cur)
        XCTAssertEqual(s.credit, 100)
    }

    func testTargetsAreDerivedFromTheBooks() throws {
        let cur = try newEngine().homeCurrency
        var f = QuarterFigures()
        f.sales = 120_000; f.costs = 90_000; f.cashEnd = 55_000; f.staff = 10
        let o = GroupReview.options(f, cur: cur)
        XCTAssertEqual(Set(o.map { $0.kind }), Set(TargetKind.allCases))
        let sales = o.first { $0.kind == .sales }!
        XCTAssertEqual(sales.goal, 124_000, accuracy: 1)
        XCTAssertEqual(sales.stretch, 130_000, accuracy: 1)
        let cash = o.first { $0.kind == .cash }!
        XCTAssertEqual(cash.goal, 55_000, accuracy: 1)
        let hire = o.first { $0.kind == .hire }!
        XCTAssertEqual(hire.goal, 11)
        XCTAssertEqual(hire.stretch, 12)
        let costs = o.first { $0.kind == .costs }!
        XCTAssertEqual(costs.start, 0.75, accuracy: 0.0001)
        XCTAssertEqual(costs.goal, 0.73, accuracy: 0.0011)
        // No sales: nothing to grow and no cost share.
        f.sales = 0
        XCTAssertEqual(Set(GroupReview.options(f, cur: cur).map { $0.kind }), [.cash, .hire])
    }

    // MARK: The annual report and its letter

    /// Every number in the letter is one of its figures (or the year), and every figure equals the book value it names.
    func assertLetterHonest(_ r: AnnualReport, file: StaticString = #filePath, line: UInt = #line) {
        let allowed = Set(r.figures.flatMap { numbers($0.text) } + [String(r.year)])
        for p in r.letter {
            for n in numbers(p) { XCTAssertTrue(allowed.contains(n), "the letter states \(n), which is not in the books: \(p)", file: file, line: line) }
        }
        for f in r.figures { XCTAssertTrue(r.letter.joined(separator: " ").contains(f.text), "figure \(f.key) is not written in the letter", file: file, line: line) }
    }

    func numbers(_ text: String) -> [String] {
        let re = try! NSRegularExpression(pattern: "[0-9]+(?:\\.[0-9]+)?")
        let ns = text.replacingOccurrences(of: ",", with: "") as NSString
        return re.matches(in: ns as String, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    func value(_ r: AnnualReport, _ key: String) -> Double? { r.figures.first { $0.key == key }?.value }

    func testFirstYearEndWritesAReportFromTheBooks() throws {
        var e = try twoCompanyGame()
        play(&e, toWeek: 14)
        let yr = try XCTUnwrap(e.latestReport(.year))
        let r = try XCTUnwrap(e.annualReports.first)
        XCTAssertEqual(e.annualReports.count, 1)
        XCTAssertEqual(r.year, 2026)
        XCTAssertTrue(r.partYear)
        XCTAssertEqual(r.sales, yr.group.pnl.revenue, accuracy: 0.001)
        XCTAssertEqual(r.profit, yr.group.pnl.netProfit, accuracy: 0.001)
        XCTAssertEqual(r.taxPaid, yr.group.taxPaid + yr.group.personalTax, accuracy: 0.001)
        XCTAssertEqual(r.netWorthChange, yr.netWorthChange, accuracy: 0.001)
        XCTAssertEqual(r.best?.name, yr.best?.name)
        XCTAssertGreaterThan(r.sales, 0)
        XCTAssertEqual(value(r, "sales"), r.sales)
        assertLetterHonest(r)
        XCTAssertEqual(r.closing, "Tester")
        XCTAssertTrue(e.state.inbox.contains { $0.title == "Your annual report for 2026 is ready" })
        // The quarter that closed in December is already in the review history's world: a review waits, nothing graded yet.
        XCTAssertNil(r.yearGrade)
        XCTAssertTrue(r.letter.contains { $0.contains("no quarterly targets") })
    }

    func testSecondYearReportComparesAndCountsTheGrades() throws {
        var e = try twoCompanyGame()
        play(&e, toWeek: 66) { e in
            if let o = e.reviewOffer { e.setReviewTargets([o.options[0].kind]) }
        }
        let list = e.annualReports
        XCTAssertEqual(list.count, 2, "2026 and 2027 are archived, newest first")
        XCTAssertEqual(list.map { $0.year }, [2027, 2026])
        let r = list[0]
        XCTAssertFalse(r.partYear)
        XCTAssertNotNil(r.profitBefore)
        XCTAssertEqual(r.quarters.count, 4)
        XCTAssertNotNil(r.yearGrade)
        XCTAssertEqual(r.yearGrade, e.reviewYearGrade(2027))
        XCTAssertEqual(r.profitBefore!, list[1].profit, accuracy: 0.001, "last year's profit is last year's report")
        assertLetterHonest(r)
        assertLetterHonest(list[1])
        XCTAssertTrue(r.letter.contains { $0.contains("I set targets for four quarters") })
        // The December grade is in the year it closes.
        XCTAssertEqual(r.quarters.last?.label, "Oct to Dec 2027")
    }

    // MARK: The letter on its own

    func syntheticYear(sales: Double, costs: Double, tax: Double = 0, before: (Double, Double)? = nil) -> PeriodReport {
        var yr = PeriodReport(kind: .year, id: 60, firstWeek: 9, lastWeek: 60, title: "2027", range: "")
        var a = ReportCompany(id: 1, name: "Alpha Cafe", tradeID: "cafe", status: "open")
        a.pnl.revenue = sales * 0.7; a.pnl.wages = costs * 0.7; a.pnl.tax = tax * 0.7; a.staffEnd = 4
        var b = ReportCompany(id: 2, name: "Beta Gym", tradeID: "gym", status: "open")
        b.pnl.revenue = sales * 0.3; b.pnl.wages = costs * 0.3; b.pnl.tax = tax * 0.3; b.staffEnd = 2
        yr.companies = [a, b]
        yr.group.pnl = a.pnl + b.pnl
        yr.group.taxPaid = tax
        yr.netWorthStart.total = 100_000; yr.netWorthEnd.total = 100_000 + (sales - costs - tax)
        if let (ps, pc) = before {
            var prev = ReportPrevious(id: 8, title: "2026")
            var pa = ReportPnL(); pa.revenue = ps * 0.5; pa.wages = pc * 0.5
            var pb = ReportPnL(); pb.revenue = ps * 0.5; pb.wages = pc * 0.5
            prev.pnl = pa + pb
            prev.companies = [ReportCompanyPnL(id: 1, pnl: pa), ReportCompanyPnL(id: 2, pnl: pb)]
            yr.previous = prev
        }
        return yr
    }

    func letter(_ yr: PeriodReport, hist: [QuarterRecord] = []) throws -> AnnualReport {
        AnnualReports.make(yr, year: 2027, author: "Tester", hist: hist, cur: try newEngine().homeCurrency)
    }

    func testLetterFollowsWhatHappenedAndStatesNoOtherNumber() throws {
        // A profit, better than the year before.
        let good = try letter(syntheticYear(sales: 400_000, costs: 300_000, tax: 10_000, before: (300_000, 280_000)))
        XCTAssertTrue(good.letter[0].contains("in the black"))
        XCTAssertTrue(good.letter[0].contains("better than the year before"))
        XCTAssertTrue(good.letter[0].contains("Sales grew"))
        XCTAssertEqual(value(good, "profit"), 90_000)
        XCTAssertEqual(value(good, "sales"), 400_000)
        XCTAssertEqual(value(good, "tax"), 10_000)
        XCTAssertEqual(value(good, "networth"), 90_000)
        assertLetterHonest(good)
        // A loss, weaker than the year before.
        let bad = try letter(syntheticYear(sales: 200_000, costs: 260_000, before: (300_000, 250_000)))
        XCTAssertTrue(bad.letter[0].contains("loss-making"))
        XCTAssertFalse(bad.letter.joined().contains("in the black"))
        XCTAssertTrue(bad.letter[0].contains("weaker than the year before"))
        XCTAssertTrue(bad.letter[0].contains("Sales fell"))
        XCTAssertEqual(value(bad, "profit"), 60_000, "a loss is written as an amount lost, never as a negative profit")
        XCTAssertTrue(bad.letter.last!.contains("out of the red"))
        assertLetterHonest(bad)
        // Break-even, no year before: no comparison is invented, no company is called a biggest mover.
        let flat = try letter(syntheticYear(sales: 100_000, costs: 100_000))
        XCTAssertTrue(flat.letter[0].contains("break-even"))
        XCTAssertFalse(flat.letter[0].contains("year before"))
        XCTAssertNil(flat.mover)
        assertLetterHonest(flat)
        // Grades: the letter reports what the history says.
        func q(_ label: String, _ g: ReviewGrade) -> QuarterRecord { var x = QuarterRecord(id: 1, year: 2027, label: label); x.score = Double(g.rawValue); x.grade = g; return x }
        let graded = try letter(syntheticYear(sales: 400_000, costs: 300_000), hist: [q("Jan to Mar 2027", .beat), q("Apr to Jun 2027", .beat), q("Jul to Sep 2027", .met)])
        XCTAssertEqual(graded.yearGrade, .beat)
        XCTAssertTrue(graded.letter.joined(separator: " ").contains("I set targets for three quarters of the year, and on balance the group beat them"))
        assertLetterHonest(graded)
        let missed = try letter(syntheticYear(sales: 400_000, costs: 300_000), hist: [q("Jan to Mar 2027", .missed)])
        XCTAssertEqual(missed.yearGrade, .missed)
        XCTAssertTrue(missed.letter.joined().contains("fell short"))
    }

    func testBiggestMoverAndBestCompanyAreFromTheBooks() throws {
        var yr = syntheticYear(sales: 400_000, costs: 300_000, before: (300_000, 280_000))
        // Alpha: now 280k revenue, 210k costs = 70k; before 150k - 140k = 10k, so +60k. Beta: now 30k; before 10k, so +20k.
        let r = try letter(yr)
        XCTAssertEqual(r.best?.name, "Alpha Cafe")
        XCTAssertEqual(r.best?.profit ?? 0, 70_000, accuracy: 0.01)
        XCTAssertEqual(r.mover?.name, "Alpha Cafe")
        XCTAssertEqual(r.mover?.change ?? 0, 60_000, accuracy: 0.01)
        XCTAssertEqual(value(r, "mover") ?? 0, 60_000, accuracy: 0.01)
        yr.previous = nil
        XCTAssertNil(try letter(yr).mover)
    }
}
