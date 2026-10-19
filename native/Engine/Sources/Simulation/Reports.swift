import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Writes the weekly, monthly and yearly reports. Native addition; see `ReportModels.swift`.
///
/// How it works: when a period starts, a snapshot of the books is kept (`rest["rptBase"]`). When it ends (the seventh day of the
/// last week of the period is over, so all the week's money has been released), the snapshot is compared with the books now and the
/// difference is the report. Then a new snapshot starts the next period. Nothing is estimated: every figure is a difference of
/// something the game already keeps (company books, cash, the ledger totals, net worth).
///
/// Stored in the save, all under keys that older saves simply do not have:
///   `reports`  {"w": [...], "m": [...], "y": [...]}   the last 26 weekly, 36 monthly and 10 yearly reports
///   `rptBase`  {"w": {...}, "m": {...}, "y": {...}}   where each running period started
///   `rptCum`   running totals of the player's account by kind (see `ReportCounters`)
///   `rptSeen`  the newest report of each kind the player has dismissed from Home
public enum Reports {
    // MARK: Snapshots

    struct CompanyMark: Codable, Equatable {
        var id: Int
        var books: [String: Double]
        var cash: Double
        var ownerNet: Double
        var distributed: Double
        var reputation: Double
        var quality: Double
        var value: Double
        var staff: [Int]
    }

    struct LoanMark: Codable, Equatable {
        var id: Int
        var companyID: Int
        var balance: Double
    }

    /// What the weeks of the running period have shown so far (weekly facts that cannot be taken from a difference).
    struct Accumulator: Codable, Equatable {
        struct Trade: Codable, Equatable { var id: Int; var units = 0.0; var util = 0.0; var weeks = 0 }
        var trade: [Trade] = []
        var events: [ReportEvent] = []
    }

    struct Snapshot: Codable, Equatable {
        var week: Int
        var partial = false
        var cash = 0.0
        var savings = 0.0
        var cum: [String: Double] = [:]
        var stats: [String: Double] = [:]
        var nw = ReportNetWorth()
        var loans: [LoanMark] = []
        var companies: [CompanyMark] = []
        var acc = Accumulator()
    }

    static func capture(_ s: GameState, data: GameData) -> Snapshot {
        var snap = Snapshot(week: s.week)
        snap.cash = s.cash
        snap.savings = s.savings
        snap.cum = ReportCounters.totals(s)
        snap.stats = ["taxPaid": s.stats.taxPaid, "dividends": s.stats.dividendsReceived, "wagesPaid": s.stats.wagesPaid, "interest": s.stats.interestPaid]
        let nw = Valuation.netWorth(s, trades: data.catalog)
        var r = ReportNetWorth()
        r.cash = nw.personal; r.investments = nw.investments; r.companies = nw.companies; r.luxury = nw.luxury
        r.debt = nw.debt + nw.pendingTax; r.total = nw.total
        snap.nw = r
        snap.loans = s.loans.map { LoanMark(id: $0.id, companyID: $0.companyID, balance: $0.balance) }
        snap.companies = s.companies.map { co in
            CompanyMark(id: co.id, books: co.books.total, cash: co.cash, ownerNet: co.ownerNetFlow, distributed: co.distributed,
                        reputation: co.reputation, quality: co.quality,
                        value: co.status.isLive ? Valuation.companyValue(co, state: s, trades: data.catalog) * co.ownership / 100 : 0,
                        staff: co.staff.map { $0.id })
        }
        return snap
    }

    // MARK: Storage

    static func read<T: Decodable>(_ v: JSONValue?, as: T.Type = T.self) -> T? {
        guard let v, !v.isNull, let d = try? JSONEncoder().encode(v) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    static func write<T: Encodable>(_ x: T) -> JSONValue {
        guard let d = try? JSONEncoder().encode(x), let v = try? JSONDecoder().decode(JSONValue.self, from: d) else { return .null }
        return v
    }

    static func stored(_ s: GameState, _ kind: ReportKind) -> [PeriodReport] {
        (s.rest["reports"]?[kind.storeKey] ?? .null).array.compactMap { read($0, as: PeriodReport.self) }
    }
    static func base(_ s: GameState, _ kind: ReportKind) -> Snapshot? { read(s.rest["rptBase"]?[kind.storeKey], as: Snapshot.self) }

    static func setBase(_ s: inout GameState, _ kind: ReportKind, _ snap: Snapshot) {
        var o = s.rest["rptBase"]?.object ?? [:]
        o[kind.storeKey] = write(snap)
        s.rest["rptBase"] = .object(o)
    }

    static func setReports(_ s: inout GameState, _ kind: ReportKind, _ list: [PeriodReport]) {
        var o = s.rest["reports"]?.object ?? [:]
        for k in ReportKind.allCases where o[k.storeKey] == nil { o[k.storeKey] = .array([]) }
        o[kind.storeKey] = .array(list.suffix(kind.keep).map { write($0) })
        s.rest["reports"] = .object(o)
    }

    // MARK: Opening and closing periods

    /// Start the running periods from now (a new game).
    public static func openBaselines(_ s: inout GameState, data: GameData) {
        var snap = capture(s, data: data)
        snap.week = s.week - 1   // the first period starts with the current week
        for k in ReportKind.allCases { setBase(&s, k, snap) }
        if s.rest["reports"] == nil { setReports(&s, .week, []) }
    }

    /// The week the player has just lived is over. Writes the week's report, and the month's and year's when they end with it.
    public static func closePeriods(_ s: inout GameState, data: GameData, context: FinanceContext) {
        let now = capture(s, data: data)
        let week = weekFacts(s)
        let monthEnds = GameCalendar.isMonthEnd(week: s.week), yearEnds = GameCalendar.isYearEnd(week: s.week)
        let cur = context.homeCurrency(s)
        for kind in ReportKind.allCases {
            let closes: Bool = kind == .week || (kind == .month && monthEnds) || (kind == .year && yearEnds)
            guard var b = base(s, kind) else {
                // A save from before reports (or a game set up half way): the first period has no start, so it is not reported.
                var fresh = now
                fresh.partial = !closes
                setBase(&s, kind, fresh)
                continue
            }
            b.acc.merge(week)
            guard closes else { setBase(&s, kind, b); continue }
            var list = stored(s, kind)
            var report = makeReport(kind, base: b, now: now, state: s, data: data, previous: list.last)
            report.summary = ReportSummary.sentences(report, currency: cur)
            list.append(report)
            setReports(&s, kind, list)
            setBase(&s, kind, now)
        }
    }

    // MARK: Weekly facts

    /// Customers and capacity of each trading company in the week that has just ended, and what was worth telling.
    static func weekFacts(_ s: GameState) -> Accumulator {
        var a = Accumulator()
        for co in s.companies where co.status == .open {
            let lw = co.value("lastW")
            guard !lw.isNull else { continue }
            a.trade.append(.init(id: co.id, units: lw["units"].double.finiteOrZero, util: lw["util"].double.finiteOrZero, weeks: 1))
        }
        var seen = Set<String>()
        func add(_ text: String, _ tone: String, _ co: Int) {
            // Routine paperwork and openings are not news.
            let routine = text.contains(" approved for ") || text.hasPrefix("Welcome") || text.hasSuffix("is open for business!")
            guard !text.isEmpty, !routine, tone == "good" || tone == "bad", seen.insert(text).inserted else { return }
            a.events.append(ReportEvent(text: text, tone: tone, companyID: co, week: s.week))
        }
        for n in (s.rest["rep"]?["ev"].array ?? []) { add(n["t"].string, n["tone"].string, n["co"].int) }
        for m in (s.rest["pend"]?["msgs"].array ?? []) {
            let msg = m["m"]
            add(msg["title"].string, msg["tone"].string, msg["co"].int)
        }
        a.events = a.events.prefix(24).map { $0 }
        return a
    }

    // MARK: Building a report

    static func makeReport(_ kind: ReportKind, base b: Snapshot, now: Snapshot, state s: GameState, data: GameData, previous: PeriodReport?) -> PeriodReport {
        var r = PeriodReport(kind: kind, id: s.week, firstWeek: b.week + 1, lastWeek: s.week, title: "", range: "")
        let firstWeek = max(0, b.week + 1)
        r.firstWeek = firstWeek
        switch kind {
        case .week: r.title = "Week \(s.week + 1)"
        case .month: r.title = GameCalendar.monthString(week: s.week)
        case .year: r.title = "\(GameCalendar.year(week: s.week))"
        }
        r.range = GameCalendar.dateString(week: firstWeek) + " – " + GameCalendar.dateString(week: s.week, dayOffset: 6)
        r.partial = b.partial

        // Companies
        let bases = Dictionary(b.companies.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let baseLoans = Dictionary(b.loans.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var rows: [ReportCompany] = []
        var groupPnL = ReportPnL()
        var loansTaken = 0.0, loansRepaid = 0.0
        func loanFlows(for companyID: Int) -> (taken: Double, repaid: Double) {
            var taken = 0.0, repaid = 0.0
            for l in s.loans where l.companyID == companyID {
                if let old = baseLoans[l.id] { repaid += max(0, old.balance - l.balance) }
                else {
                    let amt = l.originalAmount > 0 ? l.originalAmount : l.balance
                    taken += amt; repaid += max(0, amt - l.balance)
                }
            }
            for old in b.loans where old.companyID == companyID && !s.loans.contains(where: { $0.id == old.id }) { repaid += old.balance }
            return (taken, repaid)
        }
        for co in s.companies {
            let old = bases[co.id]
            var delta: [String: Double] = [:]
            for (k, v) in co.books.total { delta[k] = v - (old?.books[k] ?? 0) }
            let pnl = ReportPnL(booksDelta: delta)
            groupPnL = groupPnL + pnl
            let ownerOut = co.distributed - (old?.distributed ?? 0)
            let ownerIn = (co.ownerNetFlow - (old?.ownerNet ?? 0)) + ownerOut
            let lf = loanFlows(for: co.id)
            var row = ReportCompany(id: co.id, name: co.name, tradeID: co.type, status: co.status.rawValue)
            row.pnl = pnl
            row.cashStart = old?.cash ?? 0; row.cashEnd = co.cash
            row.ownerIn = ownerIn.finiteOrZero; row.ownerOut = ownerOut.finiteOrZero
            row.loansTaken = lf.taken; row.loansRepaid = lf.repaid
            loansTaken += lf.taken; loansRepaid += lf.repaid
            row.reputationStart = old?.reputation ?? co.reputation; row.reputationEnd = co.reputation
            row.qualityStart = old?.quality ?? co.quality; row.qualityEnd = co.quality
            let ids = co.staff.map { $0.id }
            let oldIDs = old?.staff ?? []
            row.hired = ids.filter { !oldIDs.contains($0) }.count
            row.left = oldIDs.filter { !ids.contains($0) }.count
            row.staffEnd = ids.count
            row.valueStart = old?.value ?? 0
            row.valueEnd = now.companies.first { $0.id == co.id }?.value ?? 0
            rows.append(row)
        }
        // Customers and capacity come from the weekly facts gathered while the period ran (including the week that just ended).
        for i in rows.indices {
            if let t = b.acc.trade.first(where: { $0.id == rows[i].id }) {
                rows[i].customers = t.units
                rows[i].tradingWeeks = t.weeks
                rows[i].capacityUse = t.weeks > 0 ? t.util / Double(t.weeks) : nil
            }
            rows[i].events = b.acc.events.filter { $0.companyID == rows[i].id }
        }
        // Rows worth showing: still alive, or something happened in the period.
        let shown = rows.filter { row in
            let alive = !(row.status == "sold" || row.status == "bust")
            let active = !row.pnl.isEmpty || row.cashChange != 0 || row.ownerIn != 0 || row.ownerOut != 0 || row.loansTaken != 0 || row.loansRepaid != 0
            return (alive && (row.tradeID != "hold" || active)) || active
        }
        r.companies = shown

        // Group
        var g = ReportGroup()
        g.pnl = groupPnL
        g.accountStart = b.cash; g.accountEnd = now.cash
        g.savingsStart = b.savings; g.savingsEnd = now.savings
        g.companyCashStart = b.companies.reduce(0) { $0 + $1.cash }
        g.companyCashEnd = now.companies.reduce(0) { $0 + $1.cash }
        g.ownerIn = rows.reduce(0) { $0 + $1.ownerIn }
        g.ownerOut = rows.reduce(0) { $0 + $1.ownerOut }
        g.loansTaken = loansTaken; g.loansRepaid = loansRepaid
        func cum(_ k: String) -> Double { (now.cum[k] ?? 0) - (b.cum[k] ?? 0) }
        func stat(_ k: String) -> Double { (now.stats[k] ?? 0) - (b.stats[k] ?? 0) }
        g.taxPaid = stat("taxPaid"); g.dividendsReceived = stat("dividends"); g.wagesPaid = stat("wagesPaid"); g.interestPaid = stat("interest")
        g.personalTax = -cum(ReportCounters.Key.tax)
        g.ownerPay = cum(ReportCounters.Key.salary) + cum(ReportCounters.Key.drawings)
        g.decisionsAnswered = Int(cum(ReportCounters.Key.answered).rounded())
        let labels: [(String, String)] = [
            (ReportCounters.Key.invested, "Put into your companies"), (ReportCounters.Key.dividends, "Dividends received"),
            (ReportCounters.Key.salary, "Salary from your companies"), (ReportCounters.Key.drawings, "Drawings from your businesses"),
            (ReportCounters.Key.markets, "Shares, crypto and funds"), (ReportCounters.Key.savings, "Savings and deposits"),
            (ReportCounters.Key.tax, "Personal tax"), (ReportCounters.Key.loans, "Loans drawn and instalments paid"),
            (ReportCounters.Key.interest, "Overdraft interest"), (ReportCounters.Key.companies, "Founding and selling companies"),
        ]
        var explained = 0.0
        var flows: [ReportFlow] = []
        for (k, label) in labels {
            let v = cum(k)
            explained += v
            if abs(v) >= 0.5 { flows.append(ReportFlow(id: k, label: label, amount: v)) }
        }
        let rest = (now.cash - b.cash) - explained
        flows.append(ReportFlow(id: "other", label: "Everything else", amount: rest))
        g.accountFlows = flows
        let tradingRows = rows.filter { $0.tradingWeeks > 0 }
        g.customers = tradingRows.reduce(0) { $0 + $1.customers }
        let util = tradingRows.compactMap { $0.capacityUse }
        g.capacityUse = util.isEmpty ? nil : util.reduce(0, +) / Double(util.count)
        let both = rows.filter { bases[$0.id] != nil && $0.status != "sold" && $0.status != "bust" && $0.status != "setup" }
        if !both.isEmpty {
            g.reputationStart = both.reduce(0) { $0 + $1.reputationStart } / Double(both.count)
            g.reputationEnd = both.reduce(0) { $0 + $1.reputationEnd } / Double(both.count)
        }
        g.hired = rows.reduce(0) { $0 + $1.hired }; g.left = rows.reduce(0) { $0 + $1.left }
        var events = b.acc.events
        events = events.enumerated().sorted { a, c in
            let pa = a.element.tone == "bad" ? 0 : 1, pc = c.element.tone == "bad" ? 0 : 1
            return pa != pc ? pa < pc : a.offset < c.offset
        }.map { $0.element }
        g.events = Array(events.prefix(12))
        g.breakdowns = count(events, ["broke down", "breakdown"])
        g.complaints = count(events, ["complaint"])
        g.fineCount = count(events, [" fine"])
        r.group = g
        r.netWorthStart = b.nw
        r.netWorthEnd = now.nw

        // Best, worst, ranking
        let ranked = shown.filter { $0.status != "setup" || !$0.pnl.isEmpty }.filter { !$0.pnl.isEmpty }
            .sorted { $0.pnl.netProfit != $1.pnl.netProfit ? $0.pnl.netProfit > $1.pnl.netProfit : $0.id < $1.id }
        r.ranking = ranked.map { $0.id }
        if let first = ranked.first { r.bestCompanyID = first.id }
        if ranked.count >= 2, let last = ranked.last { r.worstCompanyID = last.id }

        // The period before
        if let p = previous {
            var prev = ReportPrevious(id: p.id, title: p.title)
            prev.pnl = p.group.pnl
            prev.netWorthChange = p.netWorthChange
            prev.customers = p.group.customers
            prev.cashEnd = p.group.cashEnd
            prev.companies = p.companies.map { ReportCompanyPnL(id: $0.id, pnl: $0.pnl) }
            r.previous = prev
        }
        return r
    }

    static func count(_ events: [ReportEvent], _ needles: [String]) -> Int {
        events.filter { e in let t = e.text.lowercased(); return needles.contains { t.contains($0) } }.count
    }
}

extension Reports.Accumulator {
    /// Add one week's facts to the running period. Keeps the most telling events (bad news first) up to 24.
    mutating func merge(_ week: Reports.Accumulator) {
        for t in week.trade {
            if let i = trade.firstIndex(where: { $0.id == t.id }) { trade[i].units += t.units; trade[i].util += t.util; trade[i].weeks += t.weeks }
            else { trade.append(t) }
        }
        let all = events + week.events
        events = all.enumerated().sorted { a, c in
            let pa = a.element.tone == "bad" ? 0 : 1, pc = c.element.tone == "bad" ? 0 : 1
            return pa != pc ? pa < pc : a.offset < c.offset
        }.prefix(24).map { $0.element }
    }
}

extension PeriodReport {
    init(kind: ReportKind, id: Int, firstWeek: Int, lastWeek: Int, title: String, range: String) {
        self.kind = kind; self.id = id; self.firstWeek = firstWeek; self.lastWeek = lastWeek; self.title = title; self.range = range
    }
}

extension ReportCompany {
    init(id: Int, name: String, tradeID: String, status: String) {
        self.id = id; self.name = name; self.tradeID = tradeID; self.status = status
    }
}

extension ReportPrevious {
    init(id: Int, title: String) { self.id = id; self.title = title }
}

// MARK: What the app uses

public extension GameEngine {
    /// Reports of one kind, oldest first.
    func reports(_ kind: ReportKind) -> [PeriodReport] { Reports.stored(state, kind) }

    func latestReport(_ kind: ReportKind) -> PeriodReport? { reports(kind).last }

    /// Start the periods from now. Called when a new game begins.
    mutating func openReportBaselines() {
        let data = self.data
        update { s, _, _ in Reports.openBaselines(&s, data: data) }
    }

    /// Close the week that just ended (and the month and year if they end with it).
    mutating func closeReportPeriods() {
        let data = self.data
        update { s, _, c in Reports.closePeriods(&s, data: data, context: c) }
    }

    /// The report Home should offer now: the newest one the player has not dismissed, yearly before monthly before weekly.
    /// A report with nothing in it (no company yet) is not offered.
    func pendingReportPrompt() -> PeriodReport? {
        let seen = state.rest["rptSeen"] ?? .null
        for kind in [ReportKind.year, .month, .week] {
            if let r = latestReport(kind), r.id > (seen[kind.storeKey].isNull ? -1 : seen[kind.storeKey].int), r.hasActivity { return r }
        }
        return nil
    }

    /// The player has seen or dismissed this report: it, and the shorter reports that closed with it, are not offered again.
    mutating func dismissReportPrompt(_ report: PeriodReport) {
        update { s, _, _ in
            var o = s.rest["rptSeen"]?.object ?? [:]
            let kinds: [ReportKind]
            switch report.kind { case .year: kinds = [.year, .month, .week]; case .month: kinds = [.month, .week]; case .week: kinds = [.week] }
            for k in kinds { o[k.storeKey] = .number(Double(max(report.id, o[k.storeKey]?.int ?? -1))) }
            s.rest["rptSeen"] = .object(o)
        }
    }
}
