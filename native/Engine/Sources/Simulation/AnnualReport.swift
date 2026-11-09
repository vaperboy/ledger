import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// The annual report and the shareholder letter: written once at year end from the year's report (`Reports`), so every figure is the books'
/// own, and kept in the save (`rest["yrp"]`, the last twelve years). It opens with the same gate as the quarterly review (`Gates.reviewOpen`).
/// The letter is templated: each sentence is chosen by what actually happened, and a number only enters it through `Figure`, which holds the
/// value it came from, so the letter can never state a figure that is not in the report.
public struct AnnualReport: Codable, Equatable, Sendable, Identifiable {
    public var id: Int { year }
    public var year: Int
    /// The game week the year closed in.
    public var week: Int
    /// The book did not cover twelve months (the game started part way through the year).
    public var partYear = false
    public var author = ""
    /// Sales and profit after tax, and the year before (nil when there is no earlier year).
    public var sales = 0.0
    public var profit = 0.0
    public var salesBefore: Double? = nil
    public var profitBefore: Double? = nil
    /// Company tax and VAT paid in cash, and the player's own income tax.
    public var taxPaid = 0.0
    public var netWorthStart = 0.0
    public var netWorthEnd = 0.0
    public var customers = 0.0
    public var staffEnd = 0
    public var best: Highlight? = nil
    public var mover: Mover? = nil
    public var companies: [Row] = []
    public var quarters: [QuarterLine] = []
    public var yearGrade: ReviewGrade? = nil
    public var letter: [String] = []
    public var closing = ""
    /// Every number the letter mentions, with where it came from.
    public var figures: [Figure] = []

    public var netWorthChange: Double { netWorthEnd - netWorthStart }

    public struct Highlight: Codable, Equatable, Sendable { public var name: String; public var profit: Double }
    /// The company whose profit moved most against the year before.
    public struct Mover: Codable, Equatable, Sendable { public var name: String; public var change: Double }
    public struct Row: Codable, Equatable, Sendable, Identifiable {
        public var id: Int
        public var name: String
        public var sales: Double
        public var profit: Double
    }
    public struct QuarterLine: Codable, Equatable, Sendable { public var label: String; public var grade: ReviewGrade? }
    /// A number in the letter: `key` names the book figure it equals, `text` is how the letter wrote it.
    public struct Figure: Codable, Equatable, Sendable { public var key: String; public var value: Double; public var text: String }
}

public enum AnnualReports {
    static let key = "yrp"
    static let kept = 12

    static func stored(_ s: GameState) -> [AnnualReport] { (s.rest[key] ?? .null).array.compactMap { Reports.read($0, as: AnnualReport.self) } }

    /// Writes the year's report when the year closes (after the quarterly review, so the December grade counts).
    static func close(_ s: inout GameState, context: FinanceContext) {
        guard GameCalendar.isYearEnd(week: s.week), Gates.reviewOpen(s) else { return }
        guard let yr = Reports.stored(s, .year).last, yr.id == s.week, yr.hasActivity else { return }
        let year = GameCalendar.year(week: s.week)
        var list = stored(s)
        guard !list.contains(where: { $0.year == year }) else { return }
        let hist = GroupReview.load(s).hist
        let report = make(yr, year: year, author: s.player.name, hist: hist, cur: context.homeCurrency(s))
        list.append(report)
        s.rest[key] = .array(list.suffix(kept).map { Reports.write($0) })
        s.addMessage(from: "Annual report", title: "Your annual report for \(year) is ready",
                     body: "The group's year in one page, with a letter in your name. Open Stats, then Annual reports.", tone: "good", sev: 1)
    }

    /// The report of a closed year from its year report. Pure: the same inputs give the same words.
    static func make(_ yr: PeriodReport, year: Int, author: String, hist: [QuarterRecord], cur: Currency) -> AnnualReport {
        var r = AnnualReport(year: year, week: yr.id)
        r.author = author
        r.partYear = (yr.lastWeek - yr.firstWeek + 1) < 50
        let g = yr.group
        r.sales = g.pnl.revenue
        r.profit = g.pnl.netProfit
        if let p = yr.previous, p.pnl.revenue > 0 || !p.pnl.isEmpty { r.salesBefore = p.pnl.revenue; r.profitBefore = p.pnl.netProfit }
        r.taxPaid = g.taxPaid + g.personalTax
        r.netWorthStart = yr.netWorthStart.total
        r.netWorthEnd = yr.netWorthEnd.total
        r.customers = g.customers
        let live = yr.companies.filter { $0.status != "sold" && $0.status != "bust" && $0.tradeID != "hold" }
        r.staffEnd = live.reduce(0) { $0 + $1.staffEnd }
        let trading = yr.companies.filter { $0.tradeID != "hold" && !$0.pnl.isEmpty }
        r.companies = trading.sorted { $0.pnl.netProfit > $1.pnl.netProfit }.prefix(8).map { AnnualReport.Row(id: $0.id, name: $0.name, sales: $0.pnl.revenue, profit: $0.pnl.netProfit) }
        if let b = r.companies.first { r.best = AnnualReport.Highlight(name: b.name, profit: b.profit) }
        if let prev = yr.previous {
            var best: (name: String, change: Double)? = nil
            for c in trading {
                guard let old = prev.companies.first(where: { $0.id == c.id }) else { continue }
                let d = c.pnl.netProfit - old.pnl.netProfit
                if abs(d) >= 1, best == nil || abs(d) > abs(best!.change) { best = (c.name, d) }
            }
            if let b = best { r.mover = AnnualReport.Mover(name: b.name, change: b.change) }
        }
        let qs = hist.filter { $0.year == year }
        r.quarters = qs.map { AnnualReport.QuarterLine(label: $0.label, grade: $0.grade) }
        r.yearGrade = GroupReview.yearGrade(hist, year: year)
        writeLetter(&r, cur: cur)
        return r
    }

    // MARK: The letter

    private static func fig(_ r: inout AnnualReport, _ key: String, _ value: Double, _ cur: Currency) -> String {
        let text = cur.short(value)
        r.figures.append(AnnualReport.Figure(key: key, value: value, text: text))
        return text
    }

    private static let countWords = ["no", "one", "two", "three", "four"]

    static func writeLetter(_ r: inout AnnualReport, cur: Currency) {
        let yearName = r.partYear ? "The part of \(r.year) in this book" : "\(r.year)"
        var paras: [String] = []
        // The result.
        let sales = fig(&r, "sales", r.sales, cur)
        var p1: String
        if abs(r.profit) < 0.5 {
            p1 = "\(yearName) ended close to break-even on sales of \(sales)."
        } else if r.profit > 0 {
            p1 = "\(yearName) was a year in the black: the group made \(fig(&r, "profit", r.profit, cur)) after tax on sales of \(sales)."
        } else {
            p1 = "\(yearName) was a loss-making year: the group lost \(fig(&r, "profit", -r.profit, cur)) after tax on sales of \(sales)."
        }
        if let pb = r.profitBefore {
            if r.profit > pb + 0.5 { p1 += " That is better than the year before." }
            else if r.profit < pb - 0.5 { p1 += " That is weaker than the year before." }
            else { p1 += " That matches the year before." }
        }
        if let sb = r.salesBefore, sb > 0 {
            if r.sales > sb { p1 += " Sales grew." } else if r.sales < sb { p1 += " Sales fell." }
        }
        paras.append(p1)
        // The companies.
        var p2: [String] = []
        if r.companies.count >= 2, let b = r.best {
            p2.append(b.profit > 0 ? "\(b.name) was the strongest company, earning \(fig(&r, "best", b.profit, cur))."
                      : "No company made a profit; \(b.name) came closest.")
        } else if let b = r.best {
            p2.append("The year rested on one company, \(b.name).")
        }
        if let m = r.mover, r.companies.count >= 2 {
            p2.append("The biggest change was at \(m.name), where profit went \(m.change > 0 ? "up" : "down") by \(fig(&r, "mover", abs(m.change), cur)) on the year before.")
        }
        if !p2.isEmpty { paras.append(p2.joined(separator: " ")) }
        // Money.
        var p3: [String] = []
        if abs(r.netWorthChange) >= 0.5 {
            p3.append("My net worth \(r.netWorthChange > 0 ? "rose" : "fell") by \(fig(&r, "networth", abs(r.netWorthChange), cur)), to \(fig(&r, "networthEnd", r.netWorthEnd, cur)).")
        }
        if r.taxPaid >= 0.5 { p3.append("Tax paid over the year came to \(fig(&r, "tax", r.taxPaid, cur)).") }
        if !p3.isEmpty { paras.append(p3.joined(separator: " ")) }
        // Discipline.
        let graded = r.quarters.filter { $0.grade != nil }.count
        if graded > 0, let yg = r.yearGrade {
            let n = countWords[min(graded, 4)]
            switch yg {
            case .beat: paras.append("I set targets for \(n) quarters of the year, and on balance the group beat them.")
            case .met: paras.append("I set targets for \(n) quarters of the year, and on balance the group met them.")
            case .missed: paras.append("I set targets for \(n) quarters of the year, and on balance the group fell short of them.")
            }
        } else {
            paras.append("I set no quarterly targets this year, and I mean to hold the group to some next year.")
        }
        // Outlook.
        if r.profit < -0.5 { paras.append("The first job next year is to bring costs back in line and get the group out of the red.") }
        else if let pb = r.profitBefore, r.profit < pb - 0.5 { paras.append("Next year I want to understand what slipped before I grow any further.") }
        else { paras.append("Next year I want to keep cash healthy and grow where the books support it.") }
        r.letter = paras
        r.closing = r.author
    }
}

public extension GameEngine {
    /// Annual reports, newest first (the archive).
    var annualReports: [AnnualReport] { AnnualReports.stored(state).reversed() }
}
