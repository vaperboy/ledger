import SwiftUI
import GameCore
import Countries
import Simulation

/// A full screen of reports (used from a company's Finances). The Bank app Statements tab links here.
struct ReportsScreen: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int? = nil
    var body: some View {
        if let e = store.engine {
            ScrollView {
                ReportsContent(engine: e, companyID: companyID)
                    .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .appScreen(title: "Reports", subtitle: companyID == nil ? "Week, month and year for the whole group" : "Week, month and year for this company")
        }
    }
}

/// Weekly, monthly and yearly reports for the whole group, or for one company. Everything is read from the stored reports.
struct ReportsContent: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var companyID: Int? = nil
    @State private var kind: ReportKind = .week
    @State private var chosen: [String: Int] = [:]
    @State private var opened: ReportDest?

    private var format: ReportFormat {
        if let id = companyID, let co = engine.state.company(id) {
            return ReportFormat(short: { store.short($0, in: co) }, money: { store.money($0, in: co) })
        }
        return ReportFormat(short: { store.short($0) }, money: { store.money($0) })
    }

    private func reports() -> [PeriodReport] {
        let all = engine.reports(kind)
        guard let id = companyID else { return all }
        return all.compactMap { $0.filtered(to: id) }
    }

    private func takeRequest() {
        if let req = store.takeReportRequest() {
            kind = req.kind
            chosen[req.kind.rawValue] = req.id
        }
    }

    var body: some View {
        let all = reports()
        let picked = chosen[kind.rawValue]
        let current: PeriodReport? = all.first(where: { $0.id == picked }) ?? all.last
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            SectionTabs(items: ReportKind.allCases, title: { $0.title }, selection: $kind)
                .padding(.horizontal, -Theme.Space.margin)
            if let r = current {
                picker(r, all)
                summaryPage(r, all)
                Color.clear.frame(height: 0).navigationDestination(item: $opened) { (d: ReportDest) in
                    SettingsPage(title: d.title, subtitle: r.title, tab: companyID == nil ? .phone : .company) { detail(d, r, all) }
                }
            } else {
                CardSection("No report yet") {
                    Text("A report is written each time a week, month or year ends. The first one arrives after your first full week.")
                        .font(.system(size: 14)).foregroundStyle(Theme.ivoryMuted)
                }
            }
        }
        .onAppear { takeRequest() }
        .onChange(of: store.appRequest) { _, _ in takeRequest() }
    }

    @ViewBuilder private func detail(_ d: ReportDest, _ r: PeriodReport, _ all: [PeriodReport]) -> some View {
        switch d {
        case .movements: ReportMovements(engine: engine, report: r, companyID: companyID)
        case .bills: ReportBills(engine: engine, report: r, companyID: companyID)
        case .worth: worth(r)
        case .cash: cash(r)
        case .people: people(r)
        case .tax: yearly(r)
        case .companies: companies(r)
        case .happened: happened(r)
        case .line(let key): ReportLineDetail(report: r, history: all, key: key, showCompanies: companyID == nil, format: format)
        }
    }

    private func summaryPage(_ r: PeriodReport, _ all: [PeriodReport]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            hero(r)
            ReportChartCard(reports: Array(all.filter { $0.id <= r.id }.suffix(12)), selectedID: r.id, kind: kind, format: format)
            story(r)
            linesTable(r)
            moreTable(r)
        }
    }

    // MARK: Period picker

    private func picker(_ r: PeriodReport, _ all: [PeriodReport]) -> some View {
        let i = all.firstIndex(where: { $0.id == r.id }) ?? 0
        return Card(padding: 8, radius: Theme.Radius.row) {
            HStack(spacing: 12) {
                stepButton(glyph: Glyph.back, enabled: i > 0, label: "Earlier report") { chosen[kind.rawValue] = all[i - 1].id }
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.title.tidyMoney).font(.serifTitle(22)).foregroundStyle(Theme.ivory)
                    Text(r.range).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                }
                Spacer(minLength: 8)
                stepButton(glyph: Glyph.chevron, enabled: i < all.count - 1, label: "Later report") { chosen[kind.rawValue] = all[i + 1].id }
            }
        }
    }

    private func stepButton(glyph: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button { Haptics.choose(); action() } label: {
            GlyphView(glyph: glyph, size: 14, weight: 2, tint: enabled ? Theme.gold : Theme.ivoryDim.opacity(0.5))
                .frame(width: 36, height: 36)
                .overlay(Circle().strokeBorder(Theme.borderStrong, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain).disabled(!enabled).accessibilityLabel(label)
    }

    // MARK: Hero, story and tables

    private func hero(_ r: PeriodReport) -> some View {
        let f = format
        let net = r.group.pnl.netProfit
        let profitChange = ReportChangeText(now: net, before: r.previous?.pnl.netProfit, isCost: false, format: f)
        let worthChange = r.netWorthChange
        let worthPrev = r.previous?.netWorthChange
        let worthNote = "Change " + f.signed(worthChange) + (r.netWorthShare.map { "  " + f.percent($0) } ?? "")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                OverviewFigureCard(label: "Profit after tax", value: f.short(net),
                                   note: r.previous.map { "\(profitChange.text) vs \($0.title)" } ?? "Nothing earlier to compare with.",
                                   noteTint: profitChange.tint)
                OverviewFigureCard(label: companyID == nil ? "Net worth" : "Your share's value", value: f.short(r.netWorthEnd.total),
                                   note: worthNote, noteTint: Theme.change(worthChange))
            }
            if let p = worthPrev, r.previous != nil {
                Text("Net worth change before: " + f.signed(p)).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            }
            if r.partial {
                Text("This period began part-way through: the game was saved before reports existed.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    private func story(_ r: PeriodReport) -> some View {
        // A company's own report is written on the spot from its figures, in its currency.
        let lines: [String]
        if let id = companyID, let co = engine.state.company(id) {
            lines = ReportSummary.sentences(r, currency: engine.currency(for: co))
        } else {
            lines = r.summary
        }
        return ReportStoryRows(lines: lines)
    }

    private func lineRow(_ key: ReportLineKey, _ r: PeriodReport) -> OverviewRowData {
        let now = key.value(r.group.pnl)
        let before = r.previous.map { key.value($0.pnl) }
        let c = ReportChangeText(now: now, before: before, isCost: key.isCost, format: format)
        return OverviewRowData(id: key.id, glyph: key.glyph, title: key.title, value: format.short(now),
                               valueTint: key.id == "net" && now < 0 ? Theme.loss : Theme.ivory,
                               note: c.text, noteTint: c.tint, action: { opened = .line(key) })
    }

    private func linesTable(_ r: PeriodReport) -> some View {
        let before = r.previous?.pnl.costLines ?? []
        let used = r.group.pnl.costLines.filter { line in
            line.amount != 0 || (before.first(where: { $0.id == line.id })?.amount ?? 0) != 0
        }
        var keys: [ReportLineKey] = [.revenue]
        keys += used.map { ReportLineKey.cost($0) }
        keys += [.costs, .beforeTax]
        if r.group.pnl.tax != 0 || (r.previous?.pnl.tax ?? 0) != 0 { keys.append(.tax) }
        keys.append(.net)
        return OverviewTable(title: "Profit and loss", rows: keys.map { lineRow($0, r) }, emptyText: "Nothing earned or spent in this period.")
    }

    private func moreTable(_ r: PeriodReport) -> some View {
        let f = format
        var rows: [OverviewRowData] = []
        rows.append(OverviewRowData(id: "worth", glyph: Glyph.richList, title: companyID == nil ? "Net worth" : "Value of your share",
                                    subtitle: "Start, end and what moved it", value: f.signed(r.netWorthChange),
                                    valueTint: Theme.change(r.netWorthChange), action: { opened = .worth }))
        rows.append(OverviewRowData(id: "cash", glyph: Glyph.bank, title: "Cash", subtitle: "Where the money went",
                                    value: f.short(r.group.companyCashEnd), action: { opened = .cash }))
        rows.append(OverviewRowData(id: "people", glyph: Glyph.team, title: "Customers and people",
                                    value: f.count(r.group.customers), action: { opened = .people }))
        if companyID == nil && !r.companies.isEmpty {
            rows.append(OverviewRowData(id: "companies", glyph: Glyph.group, title: kind == .year ? "Ranking" : "Companies",
                                        subtitle: "Net profit and change", action: { opened = .companies }))
        }
        if kind == .year {
            rows.append(OverviewRowData(id: "tax", glyph: Glyph.ovCoin, title: "Tax and dividends", value: f.short(r.group.taxPaid), action: { opened = .tax }))
        }
        if !r.group.events.isEmpty {
            rows.append(OverviewRowData(id: "happened", glyph: Glyph.news, title: "What happened", value: "\(min(r.group.events.count, 8))",
                                        action: { opened = .happened }))
        }
        rows.append(OverviewRowData(id: "movements", glyph: Glyph.stats, title: ReportPage.movements.rawValue,
                                    subtitle: "Every movement of money", action: { opened = .movements }))
        rows.append(OverviewRowData(id: "bills", glyph: Glyph.reports, title: ReportPage.bills.rawValue,
                                    subtitle: "What was due and paid", action: { opened = .bills }))
        return OverviewTable(title: "Behind the figures", rows: rows)
    }

    // MARK: Companies

    private func companies(_ r: PeriodReport) -> some View {
        let f = format
        let order = r.ranking + r.companies.map { $0.id }.filter { !r.ranking.contains($0) }
        let rows = order.compactMap { r.company($0) }
        return CardSection(title: kind == .year ? "Ranking" : "Companies", trailing: {
            Text("Net profit  ·  change  ·  tap to open").font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint)
        }) {
            if rows.isEmpty {
                Text("No company has figures for this period.").font(.caption).foregroundStyle(Theme.ivoryFaint)
            }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, c in
                    let before = r.previous?.companies.first(where: { $0.id == c.id })?.pnl.netProfit
                    Button { store.go(.openCompany(c.id)) } label: {
                        HStack(spacing: 10) {
                            if kind == .year { Text("\(i + 1)").font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.ivoryFaint).frame(width: 16) }
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(c.name).font(.system(size: 14)).foregroundStyle(Theme.ivory).lineLimit(1)
                                    if c.id == r.bestCompanyID { Chip(text: "Best", tint: Theme.gain) }
                                    if c.id == r.worstCompanyID { Chip(text: "Weakest", tint: Theme.loss) }
                                }
                                Text("Revenue " + f.short(c.pnl.revenue) + (c.margin.map { " · margin " + String(format: "%.0f%%", $0 * 100) } ?? ""))
                                    .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(f.short(c.pnl.netProfit)).font(.system(size: 14).monospacedDigit()).foregroundStyle(c.pnl.netProfit < 0 ? Theme.loss : Theme.ivory)
                                if let b = before {
                                    Text(f.percent(ReportMath.share(c.pnl.netProfit, b))).font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.change(c.pnl.netProfit - b))
                                }
                            }
                            GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.ivoryDim)
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if i < rows.count - 1 { CardLine() }
                }
            }
        }
    }

    // MARK: Net worth and cash

    private func worth(_ r: PeriodReport) -> some View {
        let f = format
        let a = r.netWorthStart, b = r.netWorthEnd
        func row(_ label: String, _ x: Double, _ y: Double, debt: Bool = false, strong: Bool = false) -> some View {
            let d = y - x
            return ReportTableRow(label: label, first: f.short(x), second: f.short(y), third: f.signed(d), thirdTint: abs(d) < 0.5 ? Theme.ivoryMuted : Theme.change(debt ? -d : d), strong: strong)
        }
        return CardSection(companyID == nil ? "Net worth" : "Value of your share") {
            VStack(spacing: 0) {
                ReportTableHeader(first: "Start", second: "End", third: "Change")
                if companyID == nil {
                    row("Cash and savings", a.cash, b.cash)
                    CardLine()
                    row("Investments", a.investments, b.investments)
                    CardLine()
                    row("Companies", a.companies, b.companies)
                    if a.luxury != 0 || b.luxury != 0 { CardLine(); row("Luxury items", a.luxury, b.luxury) }
                    CardLine()
                    row("Debt and tax owed", a.debt, b.debt, debt: true)
                    CardLine()
                }
                row(companyID == nil ? "Net worth" : "Value", a.total, b.total, strong: true)
            }
        }
    }

    private func cash(_ r: PeriodReport) -> some View {
        let f = format
        let g = r.group
        func line(_ label: String, _ v: Double) -> some View {
            ReportLine(label: label, value: f.signed(v), tint: abs(v) < 0.5 ? Theme.ivoryMuted : Theme.change(v))
        }
        let other = g.companyCashEnd - g.companyCashStart - g.ownerIn + g.ownerOut - g.loansTaken + g.loansRepaid
        return CardSection("Cash") {
            VStack(spacing: 0) {
                if companyID == nil {
                    ReportLine(label: "Your account at start", value: f.short(g.accountStart))
                    ForEach(g.accountFlows.filter { abs($0.amount) >= 0.5 }) { fl in
                        CardLine()
                        line(fl.label, fl.amount)
                    }
                    CardLine()
                    ReportLine(label: "Your account at end", value: f.short(g.accountEnd), strong: true)
                    CardLine().padding(.vertical, 6)
                }
                ReportLine(label: companyID == nil ? "Company cash at start" : "Cash at start", value: f.short(g.companyCashStart))
                if g.ownerIn != 0 { CardLine(); line("Put in by you", g.ownerIn) }
                if g.ownerOut != 0 { CardLine(); line("Paid out to you (dividends, drawings)", -g.ownerOut) }
                if g.loansTaken != 0 { CardLine(); line("Loans taken", g.loansTaken) }
                if g.loansRepaid != 0 { CardLine(); line("Loan principal repaid", -g.loansRepaid) }
                CardLine()
                line("Trading, tax, equipment and other", other)
                CardLine()
                ReportLine(label: companyID == nil ? "Company cash at end" : "Cash at end", value: f.short(g.companyCashEnd), strong: true)
            }
        }
    }

    // MARK: People, year, events

    private func people(_ r: PeriodReport) -> some View {
        let f = format
        let g = r.group
        return CardSection("Customers and people") {
            VStack(spacing: 0) {
                ReportLine(label: "Customers served", value: f.count(g.customers))
                CardLine()
                ReportLine(label: "Capacity used", value: f.share(g.capacityUse))
                CardLine()
                ReportLine(label: companyID == nil ? "Average reputation" : "Reputation",
                           value: String(format: "%.0f → %.0f", g.reputationStart, g.reputationEnd),
                           tint: Theme.change(g.reputationEnd - g.reputationStart))
                CardLine()
                ReportLine(label: "Staff hired / left", value: "\(g.hired) / \(g.left)")
                if companyID == nil {
                    CardLine()
                    ReportLine(label: "Decisions answered", value: "\(g.decisionsAnswered)")
                }
                if g.breakdowns + g.complaints + g.fineCount > 0 {
                    CardLine()
                    ReportLine(label: "Breakdowns / complaints / fines", value: "\(g.breakdowns) / \(g.complaints) / \(g.fineCount)", tint: Theme.caution)
                }
            }
        }
    }

    private func yearly(_ r: PeriodReport) -> some View {
        let f = format
        let g = r.group
        return CardSection("Tax and dividends") {
            VStack(spacing: 0) {
                ReportLine(label: "Tax paid in cash", value: f.short(g.taxPaid))
                CardLine()
                ReportLine(label: "Corporate tax charged", value: f.short(g.pnl.tax))
                if companyID == nil {
                    CardLine()
                    ReportLine(label: "Dividends received", value: f.short(g.dividendsReceived))
                    CardLine()
                    ReportLine(label: "Personal income tax settled", value: f.short(g.personalTax))
                    CardLine()
                    ReportLine(label: "Salary and drawings", value: f.short(g.ownerPay))
                    CardLine()
                    ReportLine(label: "Income tax estimate, \(engine.yearInProgress.year) so far", value: f.short(engine.yearInProgress.personalTaxEstimate))
                    CardLine()
                    ReportLine(label: "Wealth change", value: f.signed(r.netWorthChange) + (r.netWorthShare.map { "  " + f.percent($0) } ?? ""),
                               tint: Theme.change(r.netWorthChange), strong: true)
                }
            }
        }
    }

    @ViewBuilder private func happened(_ r: PeriodReport) -> some View {
        let events = Array(r.group.events.prefix(8))
        if !events.isEmpty {
            CardSection("What happened") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(events.enumerated()), id: \.offset) { _, e in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(Theme.tone(e.tone)).frame(width: 5, height: 5)
                            Text(e.text.tidyMoney).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

/// Where a row of the Reports overview opens.
enum ReportDest: Hashable {
    case movements, bills, worth, cash, people, tax, companies, happened
    case line(ReportLineKey)

    var title: String {
        switch self {
        case .movements: return ReportPage.movements.rawValue
        case .bills: return ReportPage.bills.rawValue
        case .worth: return "Net worth"
        case .cash: return "Cash"
        case .people: return "Customers and people"
        case .tax: return "Tax and dividends"
        case .companies: return "Companies"
        case .happened: return "What happened"
        case .line(let k): return k.title
        }
    }
}
