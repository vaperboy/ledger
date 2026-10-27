import SwiftUI
import Charts
import Countries
import Simulation

// The pieces of the Reports overview: a chart of the last periods, the "in short" story rows, and the profit and loss lines as one
// overview table where each row opens its own detail page. Everything is read from the stored reports; money comes through `ReportFormat`.

/// Which line of the profit and loss a table row stands for.
struct ReportLineKey: Hashable, Identifiable {
    var id: String
    var title: String
    var glyph: String
    /// A cost: a rise is bad news.
    var isCost: Bool
    var strong = false

    func value(_ p: ReportPnL) -> Double {
        switch id {
        case "revenue": return p.revenue
        case "costs": return p.costs
        case "pbt": return p.profitBeforeTax
        case "tax": return p.tax
        case "net": return p.netProfit
        default: return p.costLines.first(where: { $0.id == id })?.amount ?? 0
        }
    }

    static let revenue = ReportLineKey(id: "revenue", title: "Revenue", glyph: Glyph.ovCoin, isCost: false, strong: true)
    static let costs = ReportLineKey(id: "costs", title: "Total costs", glyph: Glyph.stats, isCost: true, strong: true)
    static let beforeTax = ReportLineKey(id: "pbt", title: "Profit before tax", glyph: Glyph.market, isCost: false)
    static let tax = ReportLineKey(id: "tax", title: "Corporate tax", glyph: Glyph.bank, isCost: true)
    static let net = ReportLineKey(id: "net", title: "Profit after tax", glyph: Glyph.invest, isCost: false, strong: true)

    static func cost(_ line: ReportPnL.Line) -> ReportLineKey {
        let glyph: String
        switch line.id {
        case "wages": glyph = Glyph.person
        case "rent": glyph = Glyph.home
        case "mkt": glyph = Glyph.news
        case "ins": glyph = Glyph.ovShield
        case "dep": glyph = Glyph.ovCalendar
        case "int": glyph = Glyph.bank
        case "fine": glyph = Glyph.warning
        default: glyph = Glyph.reports
        }
        return ReportLineKey(id: line.id, title: line.label, glyph: glyph, isCost: true)
    }
}

/// How the change of one figure reads: an arrow, the share (or the amount when no share exists), and whether it is good news.
struct ReportChangeText {
    var text: String
    var tint: Color

    init(now: Double, before: Double?, isCost: Bool, format: ReportFormat) {
        guard let before else { text = ""; tint = Theme.ivoryFaint; return }
        let d = now - before
        if abs(d) < 0.5 { text = "– no change"; tint = Theme.ivoryFaint; return }
        let arrow = d > 0 ? "↑ " : "↓ "
        text = arrow + (ReportMath.share(now, before).map { format.percent($0) } ?? format.signed(d))
        tint = Theme.change(isCost ? -d : d)
    }
}

// MARK: Chart

/// What the chart plots.
enum ReportChartMetric: String, CaseIterable, Hashable { case profit = "Profit after tax", worth = "Net worth" }

/// Bars of the last periods (the chosen one marked), from the real report history.
struct ReportHistoryChart: View {
    var reports: [PeriodReport]
    var selectedID: Int
    var metric: ReportChartMetric
    var format: ReportFormat

    private struct Bar: Identifiable { var id: Int; var index: Int; var label: String; var value: Double }

    private func label(_ r: PeriodReport) -> String {
        switch r.kind {
        case .week: return r.title.replacingOccurrences(of: "Week ", with: "W")
        case .month: return String(r.title.prefix(3))
        case .year: return r.title
        }
    }

    private func value(_ r: PeriodReport) -> Double { metric == .profit ? r.group.pnl.netProfit : r.netWorthEnd.total }

    var body: some View {
        let bars = reports.enumerated().map { Bar(id: $0.element.id, index: $0.offset, label: label($0.element), value: value($0.element)) }
        if bars.count >= 2 {
            Chart {
                ForEach(bars) { b in
                    BarMark(x: .value("Period", b.index), y: .value("Amount", b.value), width: .ratio(0.62))
                        .foregroundStyle(b.id == selectedID ? Theme.gold : Theme.gold.opacity(0.32))
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.ivoryFaint.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 0.5))
            }
            .chartXAxis {
                AxisMarks(values: bars.map { $0.index }) { v in
                    AxisValueLabel {
                        if let i = v.as(Int.self), i < bars.count, bars.count <= 8 || i % 2 == bars.count % 2 {
                            Text(bars[i].label).font(.system(size: 9.5)).foregroundStyle(Theme.ivoryFaint)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.hairline)
                    AxisValueLabel { if let d = v.as(Double.self) { Text(format.short(d)).font(.system(size: 9.5)).foregroundStyle(Theme.ivoryFaint) } }
                }
            }
            .frame(height: 150)
            .accessibilityLabel("\(metric.rawValue) over the last \(bars.count) periods")
        } else {
            Text("The chart appears once two reports exist.").font(.caption).foregroundStyle(Theme.ivoryFaint)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        }
    }
}

/// The chart in its card, with the choice of what to plot.
struct ReportChartCard: View {
    var reports: [PeriodReport]
    var selectedID: Int
    var kind: ReportKind
    var format: ReportFormat
    @State private var metric: ReportChartMetric = .profit

    var body: some View {
        Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Last \(kind.noun)s".uppercased()).capsLabel()
                SegmentedPill(items: ReportChartMetric.allCases, title: { $0.rawValue }, selection: $metric)
                ReportHistoryChart(reports: reports, selectedID: selectedID, metric: metric, format: format)
            }
        }
    }
}

// MARK: Story

/// "In short": three to five short bordered rows, each with an icon circle.
struct ReportStoryRows: View {
    var lines: [String]

    private func glyph(_ s: String) -> String {
        let t = s.lowercased()
        if t.contains("worth") || t.contains("wealth") { return Glyph.richList }
        if t.contains("did best") || t.contains("did worst") { return Glyph.group }
        if t.contains("% of revenue") || t.contains("costs were") { return Glyph.stats }
        if t.contains("customer") { return Glyph.team }
        return Glyph.market
    }

    var body: some View {
        let shown = Array(lines.prefix(5))
        VStack(alignment: .leading, spacing: 8) {
            Text("IN SHORT").capsLabel()
            ForEach(Array(shown.enumerated()), id: \.offset) { _, s in
                Card(padding: 10, radius: Theme.Radius.row) {
                    HStack(alignment: .top, spacing: 10) {
                        IconCircle(glyph: glyph(s), size: 32)
                        Text(s.tidyMoney).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

// MARK: Line detail

/// One profit and loss line over the last periods, and (for the group) which company it came from.
struct ReportLineDetail: View {
    var report: PeriodReport
    var history: [PeriodReport]
    var key: ReportLineKey
    var showCompanies: Bool
    var format: ReportFormat

    private struct Entry: Identifiable { var id: Int; var name: String; var now: Double; var before: Double? }

    private func entries() -> [Entry] {
        report.companies.compactMap { c in
            let now = key.value(c.pnl)
            let before = report.previous?.companies.first(where: { $0.id == c.id }).map { key.value($0.pnl) }
            return abs(now) < 0.5 && abs(before ?? 0) < 0.5 ? nil : Entry(id: c.id, name: c.name, now: now, before: before)
        }
    }

    var body: some View {
        let now = key.value(report.group.pnl)
        let before = report.previous.map { key.value($0.pnl) }
        let change = ReportChangeText(now: now, before: before, isCost: key.isCost, format: format)
        let past = Array(history.filter { $0.id <= report.id }.suffix(12))
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            OverviewFigureCard(label: key.title, value: format.short(now), note: note(change, before), noteTint: change.tint)
            lineChart(past)
            if showCompanies { byCompany() }
        }
    }

    private func note(_ change: ReportChangeText, _ before: Double?) -> String {
        guard let b = before else { return "Nothing earlier to compare with." }
        return "\(change.text) vs " + format.short(b) + " " + (report.previous?.title ?? "before")
    }

    @ViewBuilder private func lineChart(_ past: [PeriodReport]) -> some View {
        if past.count >= 2 {
            Card(padding: 14, radius: Theme.Radius.hero) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last \(report.kind.noun)s".uppercased()).capsLabel()
                    Chart {
                        ForEach(Array(past.enumerated()), id: \.element.id) { i, r in
                            BarMark(x: .value("Period", i), y: .value("Amount", key.value(r.group.pnl)), width: .ratio(0.62))
                                .foregroundStyle(r.id == report.id ? Theme.gold : Theme.gold.opacity(0.32))
                                .cornerRadius(3)
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { v in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.hairline)
                            AxisValueLabel { if let d = v.as(Double.self) { Text(format.short(d)).font(.system(size: 9.5)).foregroundStyle(Theme.ivoryFaint) } }
                        }
                    }
                    .frame(height: 120)
                }
            }
        }
    }

    @ViewBuilder private func byCompany() -> some View {
        let rows = entries()
        if !rows.isEmpty {
            Card(padding: 14, radius: Theme.Radius.hero) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BY COMPANY").capsLabel()
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, e in
                        if i > 0 { CardLine() }
                        companyRow(e)
                    }
                }
            }
        }
    }

    private func companyRow(_ e: Entry) -> some View {
        let c = ReportChangeText(now: e.now, before: e.before, isCost: key.isCost, format: format)
        return HStack {
            Text(e.name).font(.system(size: 14)).foregroundStyle(Theme.ivory).lineLimit(1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(format.short(e.now)).font(.system(size: 14).monospacedDigit()).foregroundStyle(Theme.ivory)
                if !c.text.isEmpty { Text(c.text).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(c.tint) }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
