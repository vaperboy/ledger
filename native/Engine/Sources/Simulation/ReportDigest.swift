import Foundation
import GameCore
import Countries

/// What the report sheet shows when a week, a month or a year closes: the figures a player reads at a glance, taken from the
/// stored report (real books only), plus the risks and decisions that exist right now. Nothing here is invented: a line
/// appears only when its figure is there, and the sheet links to the Reports app for the detail.
public struct ReportDigest: Equatable, Sendable {
    public var kind: ReportKind
    public var reportID: Int
    public var title: String
    public var range: String
    public var revenue: Double
    public var netProfit: Double
    public var cashEnd: Double
    public var cashChange: Double
    /// Private loans and tax assessed, at the end of the period.
    public var debt: Double
    public var debtChange: Double
    public var payroll: Double
    public var taxes: Double
    public var netWorthEnd: Double
    public var netWorthChange: Double
    /// Major changes, most important first (hires and leavers, loans, best and worst company, reputation).
    public var changes: [String]
    public var risks: [String]
    public var decisionsAnswered: Int
    public var decisionsOpen: Int
    /// The shorter periods that closed together with this one (a month ends with its last week): shown here once, not again.
    public var includes: [ReportKind]
}

public extension GameEngine {
    /// The digest of one stored report. Money is in the home currency's accounting unit; the app formats it.
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
        if abs(rep) >= 1 { changes.append("Reputation \(rep > 0 ? "up" : "down") \(Int(abs(rep).rounded())) points") }
        for e in g.events.filter({ $0.tone == "good" }).prefix(2) { changes.append(e.text) }

        var risks: [String] = []
        if r.group.pnl.netProfit < 0 { risks.append("The group made a loss of " + amount(r.group.pnl.netProfit)) }
        if g.cashEnd < 0 { risks.append("Cash is below zero (" + amount(g.cashEnd) + " overdrawn)") }
        let alerts = payrollAlerts()
        if !alerts.isEmpty { risks.append(alerts.count == 1 ? "Payroll waits for you at \(alerts[0].companyName)" : "Payroll waits for you at \(alerts.count) companies") }
        if g.breakdowns > 0 { risks.append("\(g.breakdowns) equipment breakdown\(g.breakdowns == 1 ? "" : "s")") }
        if g.fineCount > 0 { risks.append("\(g.fineCount) fine\(g.fineCount == 1 ? "" : "s") paid") }
        if g.complaints > 0 { risks.append("\(g.complaints) customer complaint\(g.complaints == 1 ? "" : "s")") }
        if r.netWorthEnd.debt > r.netWorthStart.debt + 0.5 { risks.append("Debt rose by " + amount(r.netWorthEnd.debt - r.netWorthStart.debt)) }
        for e in g.events.filter({ $0.tone == "bad" }).prefix(2) where !risks.contains(e.text) { risks.append(e.text) }

        let included: [ReportKind]
        switch r.kind { case .year: included = [.month, .week]; case .month: included = [.week]; case .week: included = [] }
        return ReportDigest(kind: r.kind, reportID: r.id, title: r.title, range: r.range,
                            revenue: g.pnl.revenue, netProfit: g.pnl.netProfit, cashEnd: g.cashEnd, cashChange: g.cashEnd - g.cashStart,
                            debt: r.netWorthEnd.debt, debtChange: r.netWorthEnd.debt - r.netWorthStart.debt,
                            payroll: max(g.pnl.wages, g.wagesPaid), taxes: g.taxPaid, netWorthEnd: r.netWorthEnd.total, netWorthChange: r.netWorthChange,
                            changes: Array(changes.prefix(5)), risks: Array(risks.prefix(4)),
                            decisionsAnswered: g.decisionsAnswered, decisionsOpen: openDecisions.count, includes: included)
    }

    /// The report sheet to show now, or nil: the one pending report the player has not yet dismissed (see `pendingReportPrompt`).
    /// A year covers the month and the week that closed with it, so only one sheet is ever offered for a day.
    func pendingReportDigest() -> ReportDigest? { pendingReportPrompt().map { reportDigest($0) } }

    /// The digest of the day just played. `fresh` is the messages that arrived with it (`DayOutcome.newMessages`).
    func dailyDigest(fresh: [Message]) -> DailyDigest {
        var sales = 0
        var revenue = 0.0
        var best: (name: String, units: Int)?
        let live = state.companies.filter { $0.status.isLive }
        for co in live {
            let log = co.value("dl")
            guard !log["w"].isNull, log["w"].int == state.week else { continue }
            let today = log["days"][String(state.day)]
            guard !today.isNull else { continue }
            let units = Int(today["u"].double.rounded())
            guard units > 0 else { continue }
            sales += units
            revenue += today["r"].double
            if best == nil || units > best!.units { best = (co.name, units) }
        }
        let good: [String] = fresh.filter { $0.tone == "good" }.map { $0.title }
        let asks: [String] = fresh.filter { $0.status == "open" }.map { $0.title }
        let bad: [String] = fresh.filter { $0.status != "open" && $0.tone == "bad" }.map { $0.title }
        return DailyDigest(dateLabel: GameCalendar.dateString(week: state.week, dayOffset: state.day), sales: sales, revenue: revenue,
                           bestCompany: live.count > 1 ? best?.name : nil, bestSales: best?.units ?? 0,
                           wentWell: Array(good.prefix(2)), staffMessages: Array((asks + bad).prefix(3)), decisionsOpen: openDecisions.count)
    }
}

/// The short popup shown after an ordinary day: what the day's trade did and which messages need a look. Real figures only:
/// a line appears only when there is something behind it, and a day with nothing to say has `isEmpty == true`.
public struct DailyDigest: Equatable, Sendable {
    public var dateLabel: String
    /// Customers served today across all open companies.
    public var sales: Int
    public var revenue: Double
    public var bestCompany: String?
    public var bestSales: Int
    /// Good news from today's messages.
    public var wentWell: [String]
    /// Today's messages that need a look (asks and bad news), most important first.
    public var staffMessages: [String]
    public var decisionsOpen: Int
    public var isEmpty: Bool { sales == 0 && wentWell.isEmpty && staffMessages.isEmpty }
}
