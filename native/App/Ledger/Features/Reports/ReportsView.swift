import SwiftUI
import GameCore
import Countries
import Simulation

/// A full screen of reports (used from a company's Finances). In the Money tab the same content sits inside `FinanceView`.
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
            .ledgerBackground()
            .navigationTitle("Reports")
            .navigationBarTitleDisplayMode(.inline)
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
    @State private var page: ReportPage = .summary

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
        if let req = store.reportRequest {
            kind = req.kind
            chosen[req.kind.rawValue] = req.id
            store.reportRequest = nil
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
                SectionTabs(items: ReportPage.allCases, title: { $0.rawValue }, selection: $page).padding(.horizontal, -Theme.Space.margin)
                switch page {
                case .summary: summaryPage(r, all)
                case .movements: ReportMovements(engine: engine, report: r, companyID: companyID)
                case .bills: ReportBills(engine: engine, report: r, companyID: companyID)
                }
            } else {
                LedgerSection("No report yet") {
                    Text("A report is written each time a week, month or year ends. The first one arrives after your first full week.")
                        .font(.system(size: 14)).foregroundStyle(Theme.ivoryMuted)
                }
            }
        }
        .onAppear { takeRequest() }
        .onChange(of: store.reportRequest) { _, _ in takeRequest() }
    }

    @ViewBuilder private func summaryPage(_ r: PeriodReport, _ all: [PeriodReport]) -> some View {
        Group {
                hero(r)
                summary(r)
                keyFigures(r)
                trend(r, all)
        }
        Group {
                LedgerSection("Profit and loss") {
                    PnLTable(now: r.group.pnl, before: r.previous?.pnl, nowTitle: kind.title == "Week" ? "This week" : "This " + kind.noun,
                             beforeTitle: "Before", format: format)
                }
                if companyID == nil { companies(r) }
                worth(r)
                cash(r)
                people(r)
                if kind == .year { yearly(r) }
                happened(r)
        }
    }

    // MARK: Period picker

    private func picker(_ r: PeriodReport, _ all: [PeriodReport]) -> some View {
        let i = all.firstIndex(where: { $0.id == r.id }) ?? 0
        return HStack(spacing: 12) {
            Button { if i > 0 { chosen[kind.rawValue] = all[i - 1].id; Haptics.choose() } } label: {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(i > 0 ? Theme.gold : Theme.ivoryFaint.opacity(0.4)).frame(width: 36, height: 36)
            }
            .buttonStyle(.plain).disabled(i == 0).accessibilityLabel("Earlier report")
            VStack(alignment: .leading, spacing: 1) {
                Text(r.title.tidyMoney).font(.serifTitle(22)).foregroundStyle(Theme.ivory)
                Text(r.range).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            }
            Spacer(minLength: 8)
            Button { if i < all.count - 1 { chosen[kind.rawValue] = all[i + 1].id; Haptics.choose() } } label: {
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(i < all.count - 1 ? Theme.gold : Theme.ivoryFaint.opacity(0.4)).frame(width: 36, height: 36)
            }
            .buttonStyle(.plain).disabled(i >= all.count - 1).accessibilityLabel("Later report")
        }
    }

    // MARK: Hero and key figures

    private func hero(_ r: PeriodReport) -> some View {
        let f = format
        let net = r.group.pnl.netProfit
        let prevNet = r.previous?.pnl.netProfit
        let nwLabel = companyID == nil ? "Net worth" : "Your share's value"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profit after tax").capsLabel()
                    Text(f.short(net)).font(.hero(34)).foregroundStyle(net < 0 ? Theme.loss : Theme.ivory).minimumScaleFactor(0.5).lineLimit(1)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(nwLabel).capsLabel()
                    Text(f.signed(r.netWorthChange)).font(.hero(34)).foregroundStyle(Theme.change(r.netWorthChange)).minimumScaleFactor(0.5).lineLimit(1)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                if let p = prevNet {
                    DeltaPill(title: "vs " + (r.previous?.title ?? "before"), amount: net - p, share: ReportMath.share(net, p), format: f.short)
                } else {
                    Text("Nothing earlier to compare with.").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                }
                Spacer(minLength: 8)
                if let s = r.netWorthShare, abs(s) >= 0.0005, abs(s) < 10 {
                    Text(f.percent(s)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.change(r.netWorthChange))
                }
            }
            if r.partial {
                Text("This period began part-way through: the game was saved before reports existed.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    private func keyFigures(_ r: PeriodReport) -> some View {
        let f = format
        let g = r.group
        let p = r.previous
        func sub(_ now: Double, _ before: Double?) -> String { before.map { f.percent(ReportMath.share(now, $0)) + " vs before" } ?? "" }
        let items: [KeyFigures.Item] = [
            .init(label: "Revenue", value: f.short(g.pnl.revenue), sub: sub(g.pnl.revenue, p?.pnl.revenue)),
            .init(label: "Costs", value: f.short(g.pnl.costs), sub: sub(g.pnl.costs, p?.pnl.costs)),
            .init(label: "Before tax", value: f.short(g.pnl.profitBeforeTax), tint: g.pnl.profitBeforeTax < 0 ? Theme.loss : Theme.ivory,
                  sub: sub(g.pnl.profitBeforeTax, p?.pnl.profitBeforeTax)),
            .init(label: "Customers", value: f.count(g.customers), sub: p.map { f.percent(ReportMath.share(g.customers, $0.customers)) + " vs before" } ?? ""),
            .init(label: "Capacity used", value: f.share(g.capacityUse)),
            .init(label: "Cash at end", value: f.short(g.cashEnd), tint: g.cashEnd < 0 ? Theme.loss : Theme.ivory),
        ]
        return KeyFigures(items: items, columns: 3)
    }

    private func summary(_ r: PeriodReport) -> some View {
        // A company's own report is written on the spot from its figures, in its currency.
        let lines: [String]
        if let id = companyID, let co = engine.state.company(id) {
            lines = ReportSummary.sentences(r, currency: engine.currency(for: co))
        } else {
            lines = r.summary
        }
        return LedgerSection("In short") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.system(size: 14.5)).foregroundStyle(Theme.ivory).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func trend(_ r: PeriodReport, _ all: [PeriodReport]) -> some View {
        let upto = all.filter { $0.id <= r.id }.suffix(12)
        return LedgerSection(title: "Against earlier \(kind.noun)s", trailing: { ChartKey(items: [("Revenue", Theme.gold), ("Profit", Theme.gain)]) }) {
            if upto.count >= 2 {
                RevenueProfitChart(revenue: upto.map { $0.group.pnl.revenue }, profit: upto.map { $0.group.pnl.netProfit }, format: format.short)
            } else {
                Text("The chart appears once two reports exist.").font(.caption).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    // MARK: Companies

    private func companies(_ r: PeriodReport) -> some View {
        let f = format
        let order = r.ranking + r.companies.map { $0.id }.filter { !r.ranking.contains($0) }
        let rows = order.compactMap { r.company($0) }
        return LedgerSection(title: kind == .year ? "Ranking" : "Companies", trailing: {
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
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.ivoryFaint)
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if i < rows.count - 1 { Hairline() }
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
        return LedgerSection(companyID == nil ? "Net worth" : "Value of your share") {
            VStack(spacing: 0) {
                ReportTableHeader(first: "Start", second: "End", third: "Change")
                if companyID == nil {
                    row("Cash and savings", a.cash, b.cash)
                    Hairline()
                    row("Investments", a.investments, b.investments)
                    Hairline()
                    row("Companies", a.companies, b.companies)
                    if a.luxury != 0 || b.luxury != 0 { Hairline(); row("Luxury items", a.luxury, b.luxury) }
                    Hairline()
                    row("Debt and tax owed", a.debt, b.debt, debt: true)
                    Hairline()
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
        return LedgerSection("Cash") {
            VStack(spacing: 0) {
                if companyID == nil {
                    ReportLine(label: "Your account at start", value: f.short(g.accountStart))
                    ForEach(g.accountFlows.filter { abs($0.amount) >= 0.5 }) { fl in
                        Hairline()
                        line(fl.label, fl.amount)
                    }
                    Hairline()
                    ReportLine(label: "Your account at end", value: f.short(g.accountEnd), strong: true)
                    Hairline().padding(.vertical, 6)
                }
                ReportLine(label: companyID == nil ? "Company cash at start" : "Cash at start", value: f.short(g.companyCashStart))
                if g.ownerIn != 0 { Hairline(); line("Put in by you", g.ownerIn) }
                if g.ownerOut != 0 { Hairline(); line("Paid out to you (dividends, drawings)", -g.ownerOut) }
                if g.loansTaken != 0 { Hairline(); line("Loans taken", g.loansTaken) }
                if g.loansRepaid != 0 { Hairline(); line("Loan principal repaid", -g.loansRepaid) }
                Hairline()
                line("Trading, tax, equipment and other", other)
                Hairline()
                ReportLine(label: companyID == nil ? "Company cash at end" : "Cash at end", value: f.short(g.companyCashEnd), strong: true)
            }
        }
    }

    // MARK: People, year, events

    private func people(_ r: PeriodReport) -> some View {
        let f = format
        let g = r.group
        return LedgerSection("Customers and people") {
            VStack(spacing: 0) {
                ReportLine(label: "Customers served", value: f.count(g.customers))
                Hairline()
                ReportLine(label: "Capacity used", value: f.share(g.capacityUse))
                Hairline()
                ReportLine(label: companyID == nil ? "Average reputation" : "Reputation",
                           value: String(format: "%.0f → %.0f", g.reputationStart, g.reputationEnd),
                           tint: Theme.change(g.reputationEnd - g.reputationStart))
                Hairline()
                ReportLine(label: "Staff hired / left", value: "\(g.hired) / \(g.left)")
                if companyID == nil {
                    Hairline()
                    ReportLine(label: "Decisions answered", value: "\(g.decisionsAnswered)")
                }
                if g.breakdowns + g.complaints + g.fineCount > 0 {
                    Hairline()
                    ReportLine(label: "Breakdowns / complaints / fines", value: "\(g.breakdowns) / \(g.complaints) / \(g.fineCount)", tint: Theme.caution)
                }
            }
        }
    }

    private func yearly(_ r: PeriodReport) -> some View {
        let f = format
        let g = r.group
        return LedgerSection("Tax and dividends") {
            VStack(spacing: 0) {
                ReportLine(label: "Tax paid in cash", value: f.short(g.taxPaid))
                Hairline()
                ReportLine(label: "Corporate tax charged", value: f.short(g.pnl.tax))
                if companyID == nil {
                    Hairline()
                    ReportLine(label: "Dividends received", value: f.short(g.dividendsReceived))
                    Hairline()
                    ReportLine(label: "Personal income tax settled", value: f.short(g.personalTax))
                    Hairline()
                    ReportLine(label: "Salary and drawings", value: f.short(g.ownerPay))
                    Hairline()
                    ReportLine(label: "Income tax estimate, \(engine.yearInProgress.year) so far", value: f.short(engine.yearInProgress.personalTaxEstimate))
                    Hairline()
                    ReportLine(label: "Wealth change", value: f.signed(r.netWorthChange) + (r.netWorthShare.map { "  " + f.percent($0) } ?? ""),
                               tint: Theme.change(r.netWorthChange), strong: true)
                }
            }
        }
    }

    @ViewBuilder private func happened(_ r: PeriodReport) -> some View {
        let events = Array(r.group.events.prefix(8))
        if !events.isEmpty {
            LedgerSection("What happened") {
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
