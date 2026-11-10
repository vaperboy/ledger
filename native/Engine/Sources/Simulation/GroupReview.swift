import Foundation
import GameCore
import Countries
import Finance
import Businesses

public enum ReviewGrade: Int, Codable, Equatable, Sendable {
    case missed = 0, met = 1, beat = 2

    public var word: String { switch self { case .missed: return "Missed"; case .met: return "Met"; case .beat: return "Beat" } }

    public static func from(score: Double) -> ReviewGrade { score >= 1.5 ? .beat : (score >= 0.5 ? .met : .missed) }
}

public enum TargetKind: String, Codable, CaseIterable, Sendable {
    case sales, cash, hire, costs

    public var title: String {
        switch self { case .sales: return "Grow sales"; case .cash: return "Protect cash"; case .hire: return "Hire"; case .costs: return "Reduce costs" }
    }
}

public struct QuarterFigures: Codable, Equatable, Sendable {
    public var sales = 0.0
    public var costs = 0.0
    public var profit = 0.0
    public var cashEnd = 0.0
    public var staff = 0
    public var reputationStart = 0.0
    public var reputationEnd = 0.0
    public var netWorthChange = 0.0
    public var months = 0
    public var bestName = ""
    public var bestProfit = 0.0
    public var companies = 0

    public var costShare: Double? { sales > 0 ? costs / sales : nil }
    public var opinionMove: Int { let d = reputationEnd - reputationStart; return d >= 2 ? 1 : (d <= -2 ? -1 : 0) }
}

public struct ReviewTarget: Codable, Equatable, Sendable, Identifiable {
    public var id: String { kind.rawValue }
    public var kind: TargetKind
    public var goal = 0.0
    public var stretch = 0.0
    public var start = 0.0
    public var result: Double? = nil
    public var grade: ReviewGrade? = nil
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

public struct QuarterRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var year: Int
    public var label: String
    public var figures = QuarterFigures()
    public var targets: [ReviewTarget] = []
    public var score: Double? = nil
    public var grade: ReviewGrade? = nil
    public var note = ""
}

public struct ReviewOffer: Codable, Equatable, Sendable {
    public var label: String
    public var nextLabel: String
    public var figures = QuarterFigures()
    public var previous: QuarterFigures? = nil
    public var graded: QuarterRecord? = nil
    public var options: [ReviewTarget] = []
    public var nextEnd = 0
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

public struct ReviewChoice: Equatable, Sendable {
    public var chosen: String
    public var result: String
}

public enum GroupReview {
    static let key = "qrv"
    static let kept = 24

    static func load(_ s: GameState) -> ReviewState { Reports.read(s.rest[key], as: ReviewState.self) ?? ReviewState() }
    static func save(_ s: inout GameState, _ st: ReviewState) { s.rest[key] = Reports.write(st) }

    static func isQuarterEnd(_ week: Int) -> Bool { GameCalendar.isMonthEnd(week: week) && GameCalendar.month(week: week) % 3 == 2 }

    static func label(endMonth: Int) -> String {
        "\(GameCalendar.monthNames[(endMonth - 2) % 12]) to \(GameCalendar.monthNames[endMonth % 12]) \(endMonth / 12)"
    }

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
            for c in r.companies where !c.pnl.isEmpty {
                var e = byCompany[c.id] ?? (c.name, 0)
                e.name = c.name; e.profit += c.pnl.netProfit
                byCompany[c.id] = e
            }
        }
        f.cashEnd = last.group.cashEnd
        f.staff = last.companies.filter { $0.status != "sold" && $0.status != "bust" }.reduce(0) { $0 + $1.staffEnd }
        f.reputationStart = first.group.reputationStart
        f.reputationEnd = last.group.reputationEnd
        f.netWorthChange = last.netWorthEnd.total - first.netWorthStart.total
        f.companies = byCompany.count
        if let best = byCompany.values.max(by: { $0.profit < $1.profit }) { f.bestName = best.name; f.bestProfit = best.profit }
        return f
    }

    static func measure(_ kind: TargetKind, _ f: QuarterFigures) -> Double? {
        switch kind {
        case .sales: return f.sales
        case .cash: return f.cashEnd
        case .hire: return Double(f.staff)
        case .costs: return f.costShare
        }
    }

    static func roundUp(_ x: Double) -> Double {
        guard x > 0 else { return 0 }
        let unit = pow(10, floor(log10(x)) - 2)
        return (x / unit).rounded(.up) * unit
    }

    static func roundDown(_ x: Double) -> Double {
        guard x > 0 else { return 0 }
        let unit = pow(10, floor(log10(x)) - 2)
        return (x / unit).rounded(.down) * unit
    }

    static func percent(_ share: Double) -> String { "\(Int((share * 100).rounded())) percent" }

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

    static func resultText(_ t: ReviewTarget, value: Double?, cur: Currency) -> String {
        guard let v = value else { return "no sales to measure" }
        switch t.kind {
        case .sales, .cash: return cur.short(v)
        case .hire: return "\(Int(v)) on the payroll"
        case .costs: return "\(percent(v)) of sales"
        }
    }

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
        switch g {
        case .beat: s.credit = clamp(s.credit + 2, 0, 100); rec.note = "Your lenders noted a strong quarter, and loan terms are a touch friendlier."
        case .met: s.credit = clamp(s.credit + 1, 0, 100); rec.note = "Your lenders noted that you did what you said you would."
        case .missed:
            if s.credit > 45 { s.credit = clamp(s.credit - 1, 0, 100) }
            rec.note = "Your lenders took a cooler view of the quarter. One quarter changes little, and the next one is a fresh start."
        }
        return rec
    }

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
    var reviewOffer: ReviewOffer? {
        guard state.rest[GroupReview.key]?["offer"].isNull == false else { return nil }
        guard let o = GroupReview.load(state).offer, state.week >= o.deferUntil else { return nil }
        return o
    }

    var reviewHistory: [QuarterRecord] { GroupReview.load(state).hist }

    var reviewTargets: [ReviewTarget] { GroupReview.load(state).act?.targets ?? [] }
    var reviewTargetsLabel: String { GroupReview.load(state).act?.label ?? "" }

    func reviewYearGrade(_ year: Int) -> ReviewGrade? { GroupReview.yearGrade(GroupReview.load(state).hist, year: year) }

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

    mutating func deferReview() {
        update { s, _, _ in
            var st = GroupReview.load(s)
            guard var o = st.offer else { return }
            o.deferUntil = s.week + 1
            st.offer = o
            GroupReview.save(&s, st)
        }
    }

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
