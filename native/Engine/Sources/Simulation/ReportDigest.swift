import Foundation
import GameCore
import Countries
import Businesses

public struct ReportDigest: Equatable, Sendable {
    public var kind: ReportKind
    public var reportID: Int
    public var title: String
    public var range: String
    public var revenue: Double
    public var netProfit: Double
    public var cashEnd: Double
    public var cashChange: Double
    public var debt: Double
    public var debtChange: Double
    public var payroll: Double
    public var taxes: Double
    public var netWorthEnd: Double
    public var netWorthChange: Double
    public var changes: [String]
    public var risks: [String]
    public var decisionsAnswered: Int
    public var decisionsOpen: Int
    public var includes: [ReportKind]
    public var delegation: String = ""
}

public extension GameEngine {
    func reportDigest(_ r: PeriodReport) -> ReportDigest {
        let cur = homeCurrency
        func amount(_ v: Double) -> String { cur.short(abs(v)).replacingOccurrences(of: "\u{00A0}", with: " ") }
        let g = r.group
        var changes: [String] = []
        if g.hired > 0 || g.left > 0 {
            var parts: [String] = []
            if g.hired > 0 { parts.append("\(g.hired) hired") }
            if g.left > 0 { parts.append("\(g.left) left") }
            changes.append("People: " + parts.joined(separator: ", "))
        }
        if g.loansTaken > 0.5 { changes.append("Borrowed " + amount(g.loansTaken)) }
        if g.loansRepaid > 0.5 { changes.append("Repaid " + amount(g.loansRepaid) + " of loans") }
        if let b = r.best, r.companies.count > 1, let p = r.company(b.id)?.pnl.netProfit { changes.append("Best: \(b.name) (\(p >= 0 ? "+" : "−")\(amount(p)))") }
        if let w = r.worst, r.companies.count > 1, let p = r.company(w.id)?.pnl.netProfit, p < 0 { changes.append("Weakest: \(w.name) (−\(amount(p)))") }
        let rep = g.reputationEnd - g.reputationStart
        if abs(rep) >= 1 { changes.append("Reputation \(rep > 0 ? "up" : "down") \(Int(saturating: abs(rep).rounded())) points") }
        for e in g.events.filter({ $0.tone == "good" }).prefix(2) { changes.append(e.text) }

        var risks: [String] = []
        if r.group.pnl.netProfit < 0 { risks.append("The group made a loss of " + amount(r.group.pnl.netProfit)) }
        if g.cashEnd < 0 { risks.append("Cash is below zero (" + amount(g.cashEnd) + " overdrawn)") }
        let alerts = payrollAlerts()
        if !alerts.isEmpty { risks.append(alerts.count == 1 ? "Payroll is late at \(alerts[0].companyName)" : "Payroll is late at \(alerts.count) companies") }
        if g.breakdowns > 0 { risks.append("\(g.breakdowns) equipment breakdown\(g.breakdowns == 1 ? "" : "s")") }
        if g.fineCount > 0 { risks.append("\(g.fineCount) fine\(g.fineCount == 1 ? "" : "s") paid") }
        if g.complaints > 0 { risks.append("\(g.complaints) customer complaint\(g.complaints == 1 ? "" : "s")") }
        if r.netWorthEnd.debt > r.netWorthStart.debt + 0.5 { risks.append("Debt rose by " + amount(r.netWorthEnd.debt - r.netWorthStart.debt)) }
        for e in g.events.filter({ $0.tone == "bad" }).prefix(2) where !risks.contains(e.text) { risks.append(e.text) }

        let included: [ReportKind]
        switch r.kind { case .year: included = [.month, .week]; case .month: included = [.week]; case .week: included = [] }
        var digest = ReportDigest(kind: r.kind, reportID: r.id, title: r.title, range: r.range,
                            revenue: g.pnl.revenue, netProfit: g.pnl.netProfit, cashEnd: g.cashEnd, cashChange: g.cashEnd - g.cashStart,
                            debt: r.netWorthEnd.debt, debtChange: r.netWorthEnd.debt - r.netWorthStart.debt,
                            payroll: max(g.pnl.wages, g.wagesPaid), taxes: g.taxPaid, netWorthEnd: r.netWorthEnd.total, netWorthChange: r.netWorthChange,
                            changes: Array(changes.prefix(5)), risks: Array(risks.prefix(4)),
                            decisionsAnswered: g.decisionsAnswered, decisionsOpen: openDecisions.count, includes: included)
        digest.delegation = delegationLine(firstWeek: r.firstWeek, lastWeek: r.lastWeek, period: r.kind == .week ? "this week" : r.kind == .month ? "this month" : "this year")
        return digest
    }

    func pendingReportDigest() -> ReportDigest? { pendingReportPrompt().map { reportDigest($0) } }

    func dailyDigest(fresh: [Message]) -> DailyDigest {
        var sales = 0
        var revenue = 0.0
        var best: (name: String, units: Int)?
        var earlierBest = 0.0
        let live = state.companies.filter { $0.status.isLive }
        for d in 0..<max(state.day, 0) {
            let total: Double = live.reduce(0.0) { acc, co in acc + DailyTrade.soldOn(co, week: state.week, day: d)["r"].double }
            earlierBest = max(earlierBest, total)
        }
        for co in live {
            let today = DailyTrade.soldOn(co, week: state.week, day: state.day)
            guard !today.isNull else { continue }
            let units = Int(saturating: today["u"].double.rounded())
            guard units > 0 else { continue }
            sales += units
            revenue += today["r"].double
            if best == nil || units > best!.units { best = (co.name, units) }
        }
        // Decisions and alerts have their own popups and messages are in the inbox, so the day's summary
        // only carries the report lines that have no message of their own, and a count of new messages.
        let feed: [FeedLine] = state.feedToday()
        let good: [String] = feed.filter { $0.tone == "good" }.map { $0.text }
        let bad: [String] = feed.filter { $0.tone == "bad" }.map { $0.text }
        var digest = DailyDigest(dateLabel: GameCalendar.dateString(week: state.week, dayOffset: state.day), sales: sales, revenue: revenue,
                                 bestCompany: live.count > 1 ? best?.name : nil, bestSales: best?.units ?? 0,
                                 wentWell: Array(good.prefix(2)), staffMessages: Array(bad.prefix(3)), decisionsOpen: openDecisions.count)
        let newMessages: Int = fresh.filter { $0.route == .inbox && $0.isOwnerAddressed }.count
        digest.newInboxTitle = newMessages == 0 ? nil : newMessages == 1 ? "1 message" : "\(newMessages) messages"
        digest.bestDayOfWeek = state.day > 1 && revenue > 0 && revenue > earlierBest
        digest.handled = fresh.filter { !$0.handledBy.isEmpty }.map { "\($0.handledBy): \($0.title)" }
        return digest
    }
}

public struct DailyDigest: Equatable, Sendable {
    public var dateLabel: String
    public var sales: Int
    public var revenue: Double
    public var bestCompany: String?
    public var bestSales: Int
    public var wentWell: [String]
    public var staffMessages: [String]
    public var decisionsOpen: Int
    public var cashChange: Double? = nil
    public var netWorthChange: Double? = nil
    public var profit: Double? = nil
    public var handled: [String] = []
    public var newInboxTitle: String? = nil
    public var bestDayOfWeek: Bool = false
    public var isEmpty: Bool { sales == 0 && wentWell.isEmpty && staffMessages.isEmpty }
}
