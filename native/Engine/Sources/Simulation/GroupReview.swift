import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// The player's own quarterly review of their group: a calm look at the quarter that just closed, one or two targets for the next, and a
/// grade (Missed, Met, Beat) when that quarter closes. Not the boards of the companies (`ManagerModel` boards, `BoardDecision`): this is the
/// owner holding the group to account.
///
/// It opens after a first full year (`Gates.reviewOpen`) and the first review comes at the first quarter end after that.
/// The figures are sums of the month reports (`Reports`), so they are the books' own. Kept in `rest["qrv"]`:
///   `since` the week the review opened, `hist` graded quarters, `last` the figures of the latest quarter, `act` the targets now running,
///   `offer` the review waiting to be answered.
/// The consequence is mild: a graded quarter moves the credit score by one or two points (loan terms follow it), a miss only while the score
/// is not already low, so a bad run does not turn into a spiral.
public enum ReviewGrade: Int, Codable, Equatable, Sendable {
    case missed = 0, met = 1, beat = 2

    public var word: String { switch self { case .missed: return "Missed"; case .met: return "Met"; case .beat: return "Beat" } }

    /// Average score to a grade: Beat from 1.5, Met from 0.5.
    public static func from(score: Double) -> ReviewGrade { score >= 1.5 ? .beat : (score >= 0.5 ? .met : .missed) }
}

public enum TargetKind: String, Codable, CaseIterable, Sendable {
    case sales, cash, hire, costs

    public var title: String {
        switch self { case .sales: return "Grow sales"; case .cash: return "Protect cash"; case .hire: return "Hire"; case .costs: return "Reduce costs" }
    }
}

/// What the three months showed, from the month reports.
public struct QuarterFigures: Codable, Equatable, Sendable {
    public var sales = 0.0
    public var costs = 0.0
    /// After tax.
    public var profit = 0.0
    /// The account and every company's cash at the quarter end.
    public var cashEnd = 0.0
    public var staff = 0
    public var reputationStart = 0.0
    public var reputationEnd = 0.0
    public var netWorthChange = 0.0
    public var months = 0
    public var bestName = ""
    public var bestProfit = 0.0
    /// Companies that traded in the quarter.
    public var companies = 0

    /// Costs as a share of sales (nil without sales).
    public var costShare: Double? { sales > 0 ? costs / sales : nil }
    /// -1, 0 or +1: how customers' opinion moved (a change under two points is no change).
    public var opinionMove: Int { let d = reputationEnd - reputationStart; return d >= 2 ? 1 : (d <= -2 ? -1 : 0) }
}

/// One target: what it asks for, measured at the quarter end.
public struct ReviewTarget: Codable, Equatable, Sendable, Identifiable {
    public var id: String { kind.rawValue }
    public var kind: TargetKind
    /// Level that counts as Met and level that counts as Beat. For `costs` these are shares of sales (lower is better).
    public var goal = 0.0
    public var stretch = 0.0
    /// The measure when the target was set.
    public var start = 0.0
    /// The measure at the quarter end, once graded.
    public var result: Double? = nil
    public var grade: ReviewGrade? = nil
    /// Words for the popup, written when the target is offered ("Sales of at least £48k", "now £46k").
    public var goalText = ""
    public var stretchText = ""
    public var nowText = ""
    public var resultText = ""

    public var title: String { kind.title }

    public func grade(for value: Double) -> ReviewGrade {
        if kind == .costs { return value <= stretch ? .beat : (value <= goal ? .met : .missed) }
        return value >= stretch ? .beat : (value >= goal ? .met : .missed)
    }
}

/// A closed quarter in the history.
public struct QuarterRecord: Codable, Equatable, Sendable, Identifiable {
    /// The game week the quarter closed in.
    public var id: Int
    public var year: Int
    public var label: String
    public var figures = QuarterFigures()
    public var targets: [ReviewTarget] = []
    public var score: Double? = nil
    public var grade: ReviewGrade? = nil
    /// What the grade did, in words.
    public var note = ""
}

/// The review waiting for the player: the quarter in words and arrows, what the last targets came to, and the targets on offer.
public struct ReviewOffer: Codable, Equatable, Sendable {
    public var label: String
    public var nextLabel: String
    public var figures = QuarterFigures()
    public var previous: QuarterFigures? = nil
    public var graded: QuarterRecord? = nil
    public var options: [ReviewTarget] = []
    /// The month counter of the quarter the targets cover ends in.
    public var nextEnd = 0
    /// Shown again from this week (the player said not now).
    public var deferUntil = 0
}

struct ActiveTargets: Codable, Equatable {
    var label: String
    var endMonth: Int
    var targets: [ReviewTarget]
}

struct ReviewState: Codable, Equatable {
    var since: Int? = nil
    var hist: [QuarterRecord] = []
    var last: QuarterFigures? = nil
    var act: ActiveTargets? = nil
    var offer: ReviewOffer? = nil
}

/// What setting the targets told the player.
public struct ReviewChoice: Equatable, Sendable {
    public var chosen: String
    public var result: String
}

public enum GroupReview {
    static let key = "qrv"
    static let kept = 24

    // MARK: Storage

    static func load(_ s: GameState) -> ReviewState { Reports.read(s.rest[key], as: ReviewState.self) ?? ReviewState() }
    static func save(_ s: inout GameState, _ st: ReviewState) { s.rest[key] = Reports.write(st) }

    // MARK: Calendar

    /// A quarter closes with March, June, September and December.
    static func isQuarterEnd(_ week: Int) -> Bool { GameCalendar.isMonthEnd(week: week) && GameCalendar.month(week: week) % 3 == 2 }

    /// "Oct to Dec 2026" for the quarter that ends in month counter `endMonth` (quarters sit inside one calendar year).
    static func label(endMonth: Int) -> String {
        "\(GameCalendar.monthNames[(endMonth - 2) % 12]) to \(GameCalendar.monthNames[endMonth % 12]) \(endMonth / 12)"
    }

    // MARK: Figures

    /// The quarter that ends this week: the sum of its month reports (fewer than three when the game is younger).
    static func figures(_ s: GameState) -> QuarterFigures? {
        let cur = GameCalendar.monthIndex(week: s.week)
        let months = Reports.stored(s, .month).filter { r in let m = GameCalendar.monthIndex(week: r.lastWeek); return m > cur - 3 && m <= cur }
        guard let first = months.first, let last = months.last, GameCalendar.monthIndex(week: last.lastWeek) == cur else { return nil }
        var f = QuarterFigures()
        f.months = months.count
        var byCompany: [Int: (name: String, profit: Double)] = [:]
        for r in months {
            f.sales += r.group.pnl.revenue
            f.costs += r.group.pnl.costs
            f.profit += r.group.pnl.netProfit
            for c in r.companies where c.tradeID != "hold" && !c.pnl.isEmpty {
                var e = byCompany[c.id] ?? (c.name, 0)
                e.name = c.name; e.profit += c.pnl.netProfit
                byCompany[c.id] = e
            }
        }
        f.cashEnd = last.group.cashEnd
        f.staff = last.companies.filter { $0.status != "sold" && $0.status != "bust" && $0.tradeID != "hold" }.reduce(0) { $0 + $1.staffEnd }
        f.reputationStart = first.group.reputationStart
        f.reputationEnd = last.group.reputationEnd
        f.netWorthChange = last.netWorthEnd.total - first.netWorthStart.total
        f.companies = byCompany.count
        if let best = byCompany.values.max(by: { $0.profit < $1.profit }) { f.bestName = best.name; f.bestProfit = best.profit }
        return f
    }

    /// The measure a target is graded on.
    static func measure(_ kind: TargetKind, _ f: QuarterFigures) -> Double? {
        switch kind {
        case .sales: return f.sales
        case .cash: return f.cashEnd
        case .hire: return Double(f.staff)
        case .costs: return f.costShare
        }
    }

    /// Rounds up to three significant figures, so a goal reads as a clean number and is never below the exact one.
    static func roundUp(_ x: Double) -> Double {
        guard x > 0 else { return 0 }
        let unit = pow(10, floor(log10(x)) - 2)
        return (x / unit).rounded(.up) * unit
    }

    /// Rounds down to three significant figures (a floor that is never above the exact figure).
    static func roundDown(_ x: Double) -> Double {
        guard x > 0 else { return 0 }
        let unit = pow(10, floor(log10(x)) - 2)
        return (x / unit).rounded(.down) * unit
    }

    static func percent(_ share: Double) -> String { "\(Int((share * 100).rounded())) percent" }

    /// The targets a review can offer, with thresholds from the quarter's own books. A target that makes no sense now (sales of nothing) is left out.
    static func options(_ f: QuarterFigures, cur: Currency) -> [ReviewTarget] {
        var out: [ReviewTarget] = []
        if f.sales > 0 {
            var t = ReviewTarget(kind: .sales)
            t.start = f.sales; t.goal = roundUp(f.sales * 1.03); t.stretch = roundUp(f.sales * 1.08)
            t.nowText = cur.short(f.sales); t.goalText = "Sales of at least \(cur.short(t.goal))"; t.stretchText = "\(cur.short(t.stretch)) beats it"
            out.append(t)
        }
        do {
            var t = ReviewTarget(kind: .cash)
            let base = f.cashEnd
            t.start = base
            t.goal = base > 0 ? roundDown(base) : 0
            t.stretch = base > 0 ? roundUp(base * 1.1) : cur.scaledPrice(5000)
            t.nowText = cur.short(base); t.goalText = "Cash not below \(cur.short(t.goal))"; t.stretchText = "\(cur.short(t.stretch)) beats it"
            out.append(t)
        }
        do {
            var t = ReviewTarget(kind: .hire)
            let n = f.staff
            t.start = Double(n)
            t.goal = Double(n + max(1, Int((Double(n) * 0.05).rounded()))); t.stretch = Double(n + max(2, Int((Double(n) * 0.12).rounded())))
            t.nowText = "\(n) on the payroll"; t.goalText = "A team of at least \(Int(t.goal))"; t.stretchText = "\(Int(t.stretch)) beats it"
            out.append(t)
        }
        if let share = f.costShare, share > 0.2, f.costs > 0 {
            var t = ReviewTarget(kind: .costs)
            t.start = share; t.goal = (share - 0.02 + 0.00001); t.stretch = (share - 0.05 + 0.00001)
            t.goal = floor(t.goal * 1000) / 1000; t.stretch = floor(t.stretch * 1000) / 1000
            t.nowText = "\(percent(share)) of sales"; t.goalText = "Costs at \(percent(t.goal)) of sales or less"; t.stretchText = "\(percent(t.stretch)) beats it"
            out.append(t)
        }
        return out
    }

    /// The target's result in words, in the same form as its goal.
    static func resultText(_ t: ReviewTarget, value: Double?, cur: Currency) -> String {
        guard let v = value else { return "no sales to measure" }
        switch t.kind {
        case .sales, .cash: return cur.short(v)
        case .hire: return "\(Int(v)) on the payroll"
        case .costs: return "\(percent(v)) of sales"
        }
    }

    // MARK: Grading

    /// Grades the running targets against the quarter that has just closed and applies the consequence. Returns the quarter's record.
    static func grade(_ s: inout GameState, active: ActiveTargets, f: QuarterFigures, cur: Currency) -> QuarterRecord {
        var rec = QuarterRecord(id: s.week, year: GameCalendar.year(week: s.week), label: active.label)
        rec.figures = f
        var scored: [Double] = []
        for var t in active.targets {
            let v = measure(t.kind, f)
            t.result = v
            let g: ReviewGrade = v.map { t.grade(for: $0) } ?? .missed
            t.grade = g
            t.resultText = resultText(t, value: v, cur: cur)
            scored.append(Double(g.rawValue))
            rec.targets.append(t)
        }
        guard !scored.isEmpty else { return rec }
        let score = scored.reduce(0, +) / Double(scored.count)
        let g = ReviewGrade.from(score: score)
        rec.score = score; rec.grade = g
        // A small move of the credit score, which the banks price loans on. A miss costs only while the score is not already low.
        switch g {
        case .beat: s.credit = clamp(s.credit + 2, 0, 100); rec.note = "Your lenders noted a strong quarter, and loan terms are a touch friendlier."
        case .met: s.credit = clamp(s.credit + 1, 0, 100); rec.note = "Your lenders noted that you did what you said you would."
        case .missed:
            if s.credit > 45 { s.credit = clamp(s.credit - 1, 0, 100) }
            rec.note = "Your lenders took a cooler view of the quarter. One quarter changes little, and the next one is a fresh start."
        }
        return rec
    }

    // MARK: The quarter end

    /// Called when a week has closed (after the reports): records when the review opened, and at a quarter end grades the last targets and
    /// prepares the next review.
    static func close(_ s: inout GameState, context: FinanceContext) {
        guard GameCalendar.isMonthEnd(week: s.week) else { return }
        var st = load(s)
        let opened = Gates.reviewOpen(s)
        defer { if opened && st.since == nil { st.since = s.week }; if st != load(s) { save(&s, st) } }
        guard let since = st.since, since < s.week, isQuarterEnd(s.week), let f = figures(s) else { return }
        let cur = context.homeCurrency(s)
        let endMonth = GameCalendar.monthIndex(week: s.week)
        var graded: QuarterRecord? = nil
        if let act = st.act, act.endMonth == endMonth {
            let rec = grade(&s, active: act, f: f, cur: cur)
            st.hist.append(rec)
            graded = rec
        }
        st.act = nil
        if st.hist.count > kept { st.hist.removeFirst(st.hist.count - kept) }
        var offer = ReviewOffer(label: label(endMonth: endMonth), nextLabel: label(endMonth: endMonth + 3))
        offer.figures = f; offer.previous = st.last; offer.graded = graded
        offer.options = options(f, cur: cur); offer.nextEnd = endMonth + 3
        st.offer = offer
        st.last = f
    }
}

public extension GameEngine {
    /// The review to show now: nil when none is waiting or the player said not now for a while.
    var reviewOffer: ReviewOffer? {
        guard state.rest[GroupReview.key]?["offer"].isNull == false else { return nil }   // cheap for the popup layer, which asks on every redraw
        guard let o = GroupReview.load(state).offer, state.week >= o.deferUntil else { return nil }
        return o
    }

    /// Graded quarters, oldest first.
    var reviewHistory: [QuarterRecord] { GroupReview.load(state).hist }

    /// The targets running for the quarter in progress.
    var reviewTargets: [ReviewTarget] { GroupReview.load(state).act?.targets ?? [] }
    var reviewTargetsLabel: String { GroupReview.load(state).act?.label ?? "" }

    /// The grade of a calendar year: the average of its graded quarters (nil when none was graded).
    func reviewYearGrade(_ year: Int) -> ReviewGrade? { GroupReview.yearGrade(GroupReview.load(state).hist, year: year) }

    /// How the board and lenders see the group, in words, from the last four graded quarters. Nil before the first grade.
    var reviewStanding: (words: String, trend: Int)? {
        let h = reviewHistory.filter { $0.score != nil }
        guard !h.isEmpty else { return nil }
        let recent = h.suffix(4).compactMap { $0.score }
        let avg = recent.reduce(0, +) / Double(recent.count)
        let words = avg >= 1.3 ? "Your board and lenders think well of how you run the group."
            : (avg >= 0.7 ? "Your board and lenders see a steady hand." : "Your board and lenders are watching and want to see more follow-through.")
        var trend = 0
        if h.count >= 2, let a = h[h.count - 1].score, let b = h[h.count - 2].score { trend = a > b ? 1 : (a < b ? -1 : 0) }
        return (words, trend)
    }

    /// Sets one or two targets for the next quarter from the review on offer.
    @discardableResult
    mutating func setReviewTargets(_ kinds: [TargetKind]) -> ReviewChoice? {
        var out: ReviewChoice?
        update { s, _, _ in
            var st = GroupReview.load(s)
            guard let o = st.offer, (1...2).contains(kinds.count), Set(kinds).count == kinds.count else { return }
            let picked = kinds.compactMap { k in o.options.first { $0.kind == k } }
            guard picked.count == kinds.count else { return }
            st.act = ActiveTargets(label: o.nextLabel, endMonth: o.nextEnd, targets: picked)
            st.offer = nil
            GroupReview.save(&s, st)
            let names = picked.map { $0.title }.joined(separator: " and ")
            var lines = picked.map { "\($0.title): \($0.goalText.prefix(1).lowercased() + $0.goalText.dropFirst())" }
            lines.append("They are graded when \(o.nextLabel) closes.")
            out = ReviewChoice(chosen: names, result: lines.joined(separator: "\n"))
        }
        return out
    }

    /// Not now: the review comes back next week (and lapses when the next quarter closes).
    mutating func deferReview() {
        update { s, _, _ in
            var st = GroupReview.load(s)
            guard var o = st.offer else { return }
            o.deferUntil = s.week + 1
            st.offer = o
            GroupReview.save(&s, st)
        }
    }

    /// No targets this quarter: nothing is graded and nothing changes.
    mutating func skipReview() {
        update { s, _, _ in
            var st = GroupReview.load(s)
            st.offer = nil
            GroupReview.save(&s, st)
        }
    }
}

extension GroupReview {
    static func yearGrade(_ hist: [QuarterRecord], year: Int) -> ReviewGrade? {
        let scores = hist.filter { $0.year == year }.compactMap { $0.score }
        guard !scores.isEmpty else { return nil }
        return ReviewGrade.from(score: scores.reduce(0, +) / Double(scores.count))
    }
}
