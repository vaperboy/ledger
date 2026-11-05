import Foundation
import GameCore
import Countries

/// The facts the week report's one story sentence is chosen from. Pure data: `WeekStory.sentence(_:)` picks the first
/// rule that applies. Built from the stored reports by `GameEngine.weekStoryInput(for:)`.
public struct WeekStoryInput: Equatable, Sendable {
    /// "week", "month" or "year": the word the sentences use.
    public var noun: String
    /// Rule 1: a company whose cash ended the period below zero.
    public var cashBelowZeroCompany: String?
    /// Rule 2: the headline of a bad event of the period and what the period's fines and losses were as a share of its sales.
    public var badEventHeadline: String?
    public var badEventCostShare: Double
    /// Rule 3: the period's profit, the one before (nil in the first period), how many profitable periods ran just before this one,
    /// and whether any earlier period was profitable.
    public var profit: Double
    public var lastWeekProfit: Double?
    public var profitableRunBefore: Int
    public var hadProfitBefore: Bool
    /// Rule 4: the past tense of a goal finished in the period ("You hired your first worker."). nil until the ladder exists.
    public var completedGoalPastTense: String?
    /// Rule 5: the best or the worst period of the last 12 (needs enough history to mean something).
    public var bestOfLast12: Bool
    public var worstOfLast12: Bool
    /// Rule 6: the name of the top seller when it changed since the period before.
    public var topSellerChange: String?
    /// Rule 7: the briefing sentence (what the morning briefing would say about the period).
    public var briefing: String
    /// With several companies: the one that drove the change (named by rules 3, 5 and 7).
    public var drivenBy: String?

    public init(noun: String = "week", cashBelowZeroCompany: String? = nil, badEventHeadline: String? = nil, badEventCostShare: Double = 0,
                profit: Double = 0, lastWeekProfit: Double? = nil, profitableRunBefore: Int = 0, hadProfitBefore: Bool = false,
                completedGoalPastTense: String? = nil, bestOfLast12: Bool = false, worstOfLast12: Bool = false,
                topSellerChange: String? = nil, briefing: String = "", drivenBy: String? = nil) {
        self.noun = noun; self.cashBelowZeroCompany = cashBelowZeroCompany
        self.badEventHeadline = badEventHeadline; self.badEventCostShare = badEventCostShare
        self.profit = profit; self.lastWeekProfit = lastWeekProfit
        self.profitableRunBefore = profitableRunBefore; self.hadProfitBefore = hadProfitBefore
        self.completedGoalPastTense = completedGoalPastTense
        self.bestOfLast12 = bestOfLast12; self.worstOfLast12 = worstOfLast12
        self.topSellerChange = topSellerChange; self.briefing = briefing; self.drivenBy = drivenBy
    }
}

public enum WeekStory {
    public static let maxLength = 110

    /// The one sentence, by the priority order of Part 3.2; never longer than 110 characters.
    public static func sentence(_ i: WeekStoryInput) -> String {
        cap(pick(i))
    }

    private static func pick(_ i: WeekStoryInput) -> String {
        if let c = i.cashBelowZeroCompany { return "\(c) ran out of cash. A bill waits for next week." }
        if let h = i.badEventHeadline, i.badEventCostShare > 0.10 { return oneSentence(h) }
        if let flip = flipSentence(i) { return named(flip, i) }
        if let g = i.completedGoalPastTense, !g.isEmpty { return g }
        if i.bestOfLast12 { return named(i.noun == "week" ? "Your best week yet." : "Your best \(i.noun) yet.", i) }
        if i.worstOfLast12 { return named(worstText(i.noun), i) }
        if let s = i.topSellerChange { return "\(s) is now your best seller." }
        return named(i.briefing, i)
    }

    private static func flipSentence(_ i: WeekStoryInput) -> String? {
        guard let last = i.lastWeekProfit else { return nil }
        if i.profit > 0 && last <= 0 { return i.hadProfitBefore ? "Back in profit." : "First profitable \(i.noun)." }
        if i.profit < 0 && last > 0 {
            let n: Int = i.profitableRunBefore + 1
            return "First loss in \(n) \(i.noun)\(n == 1 ? "" : "s")."
        }
        return nil
    }

    private static func worstText(_ noun: String) -> String {
        switch noun {
        case "week": return "Slowest week in three months."
        case "month": return "Weakest month in a year."
        default: return "Weakest year so far."
        }
    }

    /// Adds the company that drove the result when it fits.
    private static func named(_ text: String, _ i: WeekStoryInput) -> String {
        guard let who = i.drivenBy, !who.isEmpty, !text.isEmpty else { return text }
        let both: String = text + " " + who + " drove it."
        return both.count <= maxLength ? both : text
    }

    /// The first sentence of an event headline, ending in a full stop.
    static func oneSentence(_ text: String) -> String {
        let t: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var end: String.Index = t.endIndex
        for (idx, ch) in zip(t.indices, t) where ch == "." || ch == "!" || ch == "?" {
            end = idx
            break
        }
        var first: String = String(t[t.startIndex..<end]).trimmingCharacters(in: .whitespaces)
        if first.isEmpty { first = t }
        if let last = first.last, last != "." && last != "!" && last != "?" { first += "." }
        return first
    }

    private static func cap(_ s: String) -> String {
        if s.count <= maxLength { return s }
        return String(s.prefix(maxLength - 1)) + "…"
    }
}

/// The one thing the report asks the player to do next: a decision waiting, or the best suggestion.
public struct WeekNextStep: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var buttonTitle: String
    public var action: Suggestion.Action
    /// An Inbox item with an expiry: the cliffhanger of Part 3.3 (the later notification step keys off this).
    public var expiresInWeeks: Int?
}

/// One line of the movers list: a sales or cost line and how much it changed against the period before.
public struct WeekMover: Equatable, Sendable {
    public var label: String
    public var change: Double
    /// A cost line: a rise is bad news (red), a fall good.
    public var isCost: Bool
}

/// Everything the week, month or year report shell shows, from the real reports.
public struct WeekRecap: Equatable, Sendable {
    public var kind: ReportKind
    public var sales: Double
    /// Everything that left the books, tax included, so that sales minus costs is the profit.
    public var costs: Double
    public var profit: Double
    /// nil in the first period: the delta line is left out.
    public var previousProfit: Double?
    public var story: String
    /// "Best week so far", "Best month so far", "Net worth passed ..." or nil.
    public var record: String?
    public var next: WeekNextStep?
    public var companyCount: Int
    /// Month and year only: the biggest income and cost changes against the period before (at most 2 + 2).
    public var movers: [WeekMover] = []
    /// Month: the best and the slowest week of the month in one line. Year: the best month in one line.
    public var extremes: String? = nil
    /// Year only: the profit of each month of the year, oldest first (at most 12).
    public var monthStrip: [Double] = []
    /// Year only: tax paid in cash and the change in net worth over the year.
    public var taxPaid: Double = 0
    public var netWorthChange: Double = 0

    public var delta: Double? { previousProfit.map { profit - $0 } }
}

public extension GameEngine {
    /// The facts for the story sentence of one stored report (the week, month or year that just closed).
    func weekStoryInput(for r: PeriodReport) -> WeekStoryInput {
        let cur = homeCurrency
        func amount(_ v: Double) -> String { cur.short(abs(v)).replacingOccurrences(of: "\u{00A0}", with: " ") }
        let g = r.group
        let profit: Double = g.pnl.netProfit
        let hist: [PeriodReport] = Array(reports(r.kind).filter { $0.id < r.id }.suffix(12))
        let profits: [Double] = hist.map { $0.group.pnl.netProfit }
        var run = 0
        for p in profits.reversed() { if p > 0 { run += 1 } else { break } }

        var input = WeekStoryInput(noun: r.kind.noun)
        input.profit = profit
        input.lastWeekProfit = r.previous?.pnl.netProfit
        input.profitableRunBefore = run
        input.hadProfitBefore = profits.contains { $0 > 0 }
        input.completedGoalPastTense = PlayerGoals.ladderPastTense(state, firstWeek: r.firstWeek, lastWeek: r.lastWeek)
        input.cashBelowZeroCompany = r.companies.first { $0.status == "open" && $0.cashEnd < 0 }?.name
        // BRIEF: an event's own cost is not stored; fines plus refunds and losses of the period stand for what the bad events cost.
        if let bad = g.events.first(where: { $0.tone == "bad" }) {
            let hit: Double = g.pnl.fines + g.pnl.losses
            input.badEventHeadline = bad.text
            input.badEventCostShare = g.pnl.revenue > 0 ? hit / g.pnl.revenue : (hit > 0 ? 1 : 0)
        }
        if profits.count >= 2, profit > 0, let top = profits.max(), profit > top { input.bestOfLast12 = true }
        if profits.count >= 6, let low = profits.min(), profit < low { input.worstOfLast12 = true }
        if r.companies.count > 1 {
            let top = r.companies.max { $0.pnl.revenue < $1.pnl.revenue }
            let before = r.previous?.companies.max { $0.pnl.revenue < $1.pnl.revenue }
            if let top, top.pnl.revenue > 0, let before, before.pnl.revenue > 0, before.id != top.id { input.topSellerChange = top.name }
            input.drivenBy = driver(of: r)
        }
        let lead: String = profit >= 0 ? "A profit of \(amount(profit))" : "A loss of \(amount(profit))"
        input.briefing = g.pnl.revenue > 0.5 ? lead + " on \(amount(g.pnl.revenue)) of sales." : lead + "."
        return input
    }

    /// The company whose profit moved the most against the period before (or the best or worst company when there is no earlier period).
    private func driver(of r: PeriodReport) -> String? {
        if let prev = r.previous {
            var bestMove: (name: String, move: Double)?
            for c in r.companies {
                let before: Double = prev.companies.first { $0.id == c.id }?.pnl.netProfit ?? 0
                let move: Double = c.pnl.netProfit - before
                if bestMove == nil || abs(move) > abs(bestMove!.move) { bestMove = (c.name, move) }
            }
            return bestMove?.name
        }
        return (r.group.pnl.netProfit >= 0 ? r.best : r.worst)?.name
    }

    /// The shell of the week, month or year report. `kind` and `id` name the stored report (the digest's `kind` and `reportID`).
    func weekRecap(kind: ReportKind, id: Int) -> WeekRecap? {
        guard let r = reports(kind).first(where: { $0.id == id }) else { return nil }
        let g = r.group
        let profit: Double = g.pnl.netProfit
        let sales: Double = g.pnl.revenue
        var recap = WeekRecap(kind: kind, sales: sales, costs: max(0, sales - profit), profit: profit, previousProfit: r.previous?.pnl.netProfit,
                              story: WeekStory.sentence(weekStoryInput(for: r)), record: nil, next: weekNextStep(), companyCount: r.companies.count)
        recap.record = recordLine(for: r)
        recap.taxPaid = g.taxPaid
        recap.netWorthChange = r.netWorthChange
        if kind != .week {
            recap.movers = movers(of: r)
            recap.extremes = extremesLine(for: r)
        }
        if kind == .year { recap.monthStrip = monthProfits(in: r) }
        return recap
    }

    /// Income movers (each company's sales, or the group's sales) and cost movers (cost lines), by size of change against the period before.
    private func movers(of r: PeriodReport) -> [WeekMover] {
        guard let prev = r.previous else { return [] }
        var income: [WeekMover] = []
        if r.companies.count > 1 {
            for c in r.companies {
                let before: Double = prev.companies.first { $0.id == c.id }?.pnl.revenue ?? 0
                income.append(WeekMover(label: c.name + " sales", change: c.pnl.revenue - before, isCost: false))
            }
        } else {
            income.append(WeekMover(label: "Sales", change: r.group.pnl.revenue - prev.pnl.revenue, isCost: false))
        }
        var costs: [WeekMover] = []
        let before: [ReportPnL.Line] = prev.pnl.costLines
        for (n, line) in r.group.pnl.costLines.enumerated() where n < before.count {
            costs.append(WeekMover(label: line.label, change: line.amount - before[n].amount, isCost: true))
        }
        let inTop: [WeekMover] = income.filter { abs($0.change) >= 0.5 }.sorted { abs($0.change) > abs($1.change) }
        let coTop: [WeekMover] = costs.filter { abs($0.change) >= 0.5 }.sorted { abs($0.change) > abs($1.change) }
        return Array(inTop.prefix(2)) + Array(coTop.prefix(2))
    }

    private func signedAmount(_ v: Double) -> String {
        let t: String = homeCurrency.short(abs(v)).replacingOccurrences(of: "\u{00A0}", with: " ")
        return (v < 0 ? "-" : "+") + t
    }

    /// Month: best and slowest week (the books keep no per-day profit). Year: the best month.
    private func extremesLine(for r: PeriodReport) -> String? {
        if r.kind == .month {
            let weeks: [PeriodReport] = reports(.week).filter { $0.id >= r.firstWeek && $0.id <= r.lastWeek }
            guard weeks.count >= 2, let best = weeks.max(by: { $0.group.pnl.netProfit < $1.group.pnl.netProfit }),
                  let low = weeks.min(by: { $0.group.pnl.netProfit < $1.group.pnl.netProfit }), best.id != low.id else { return nil }
            return "Best: \(best.title) \(signedAmount(best.group.pnl.netProfit)). Slowest: \(low.title) \(signedAmount(low.group.pnl.netProfit))."
        }
        let months: [PeriodReport] = reports(.month).filter { $0.id >= r.firstWeek && $0.id <= r.lastWeek }
        guard let best = months.max(by: { $0.group.pnl.netProfit < $1.group.pnl.netProfit }) else { return nil }
        return "Best month: \(best.title) \(signedAmount(best.group.pnl.netProfit))."
    }

    private func monthProfits(in r: PeriodReport) -> [Double] {
        let months: [PeriodReport] = reports(.month).filter { $0.id >= r.firstWeek && $0.id <= r.lastWeek }
        return Array(months.suffix(12).map { $0.group.pnl.netProfit })
    }

    private func recordLine(for r: PeriodReport) -> String? {
        let profit: Double = r.group.pnl.netProfit
        let earlier: [Double] = reports(r.kind).filter { $0.id < r.id }.suffix(52).map { $0.group.pnl.netProfit }
        if earlier.count >= 2, profit > 0, let top = earlier.max(), profit > top { return "Best \(r.kind.noun) so far" }
        let million: Double = homeCurrency.scaledPrice(1_000_000)
        if r.netWorthStart.total < million && r.netWorthEnd.total >= million {
            return "Net worth passed " + homeCurrency.short(million).replacingOccurrences(of: "\u{00A0}", with: " ")
        }
        return nil
    }

    /// One thing to do: a blocking Inbox item, one expiring within two weeks, any item with an expiry (the cliffhanger rule makes the
    /// card mandatory then), otherwise the strongest suggestion. The open ladder goal comes first once the ladder exists (not yet).
    func weekNextStep() -> WeekNextStep? {
        let open: [Message] = openDecisions
        if let m = open.first(where: { $0.isAlert }) { return step(for: m) }
        let withExpiry: [Message] = open.filter { $0.expiresWeek != nil }.sorted { ($0.expiresWeek ?? 0) < ($1.expiresWeek ?? 0) }
        if let m = withExpiry.first { return step(for: m) }
        if let s = suggestions(limit: 8).first(where: { $0.tone != .neutral }) {
            return WeekNextStep(title: s.title, detail: s.detail, buttonTitle: s.actionLabel, action: s.action, expiresInWeeks: nil)
        }
        return nil
    }

    private func step(for m: Message) -> WeekNextStep {
        var left: Int?
        var detail: String = WeekStory.oneSentence(m.body)
        if let e = m.expiresWeek {
            let n: Int = max(0, e - state.week)
            left = n
            detail = n == 0 ? "Closes this week." : "Closes in \(n) week\(n == 1 ? "" : "s")."
        }
        return WeekNextStep(title: m.title, detail: detail, buttonTitle: "Open Inbox", action: .openMessage(m.id), expiresInWeeks: left)
    }
}

public extension GameEngine {
    /// Profit of all companies' books so far (revenue less costs, all time). The app takes its difference across a day for "Profit today".
    var groupBooksProfit: Double {
        state.companies.reduce(0) { $0 + Books.profit($1.books.total) }
    }
}
