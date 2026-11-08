import SwiftUI
import Charts
import GameCore
import Finance
import Businesses
import Simulation

/// Stats app: key figures first (best, now, weeks, sales), then the net worth trend and what it is made of from the engine's recorded
/// daily history, the change against the past, the economy, and what the run has cost. Every figure is read from the engine and shown
/// once; money goes through the store formatters.
struct StatsView: View {
    @EnvironmentObject var store: GameStore
    @State private var period = 90
    @State private var docItem: DocumentItem?

    private static let periods: [Int] = [30, 90, 365]

    var body: some View {
        if let e = store.engine {
            PhonePageScroll(spacing: Theme.Space.xl) {
                figureTiles(e)
                trendCard(e)
                makeUpCard(e)
                compareCard(e)
                economyCard(e)
                Group {
                    costCard(e)
                    documentsCard(e)
                }
                LedgerSection("More") {
                    VStack(spacing: 0) {
                        activityLink
                        Hairline()
                        goalsLink
                        Hairline()
                        reportsLink
                    }
                }
                if store.gateOpen(.bank) { TrophiesPreview() }
            }
            .centerSheet(item: $docItem) { (item: DocumentItem) in DocumentView(doc: item.doc, close: { docItem = nil }) }
        }
    }

    // MARK: Key figures

    /// Net worth now leads; bankruptcies sit under Companies sold and are not repeated further down.
    private func figureTiles(_ e: GameEngine) -> some View {
        let s = e.state
        let nw: NetWorth = e.netWorth
        let best: Double = max(s.stats.peakNetWorth, nw.total)
        let ofBest: String = best > 0 ? String(format: "%.0f%% of your best", max(0, nw.total) / best * 100) : "No best yet"
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            Figure(label: "Net worth now", value: store.short(nw.total), note: ofBest, tint: nw.total < 0 ? Theme.loss : nil, size: .display, live: nw.total)
            FigureRow(items: [
                KeyFigures.Item(label: "Best net worth", value: store.short(best), sub: "Highest so far"),
                KeyFigures.Item(label: "Weeks played", value: "\(s.week)", sub: "Since you started"),
                KeyFigures.Item(label: "Companies sold", value: "\(s.stats.companiesSold)", tint: s.stats.bankruptcies > 0 ? Theme.loss : Theme.ink,
                                sub: s.stats.bankruptcies > 0 ? "\(s.stats.bankruptcies) bankruptcies" : "No bankruptcies")
            ])
        }
    }

    // MARK: Trend

    private func trendCard(_ e: GameEngine) -> some View {
        let series: [Double] = e.netWorthSeries(days: period)
        return LedgerSection(title: "Net worth", trailing: { trendChange(series) }) {
            NetWorthChart(engine: e, days: period, height: 120)
            SegmentedChoice(items: Self.periods, title: { (d: Int) -> String in d == 30 ? "1M" : d == 90 ? "3M" : "1Y" }, selection: $period)
        }
    }

    @ViewBuilder private func trendChange(_ series: [Double]) -> some View {
        if let first = series.first, let last = series.last, series.count >= 2 {
            let d: Double = last - first
            let sign: String = d > 0 ? "+" : d < 0 ? "\u{2212}" : ""
            Text("\(sign)\(store.short(abs(d)))").textStyle(.body, tint: Theme.change(d), numeric: true, weight: .medium)
        }
    }

    // MARK: What it is made of

    private struct MakeUpPoint: Identifiable {
        var id: String
        var day: Int
        var value: Double
        var series: String
    }

    private func makeUpPoints(_ h: DayHistory) -> [MakeUpPoint] {
        let n: Int = min(period, h.cash.count)
        func pts(_ name: String, _ v: [Double]) -> [MakeUpPoint] {
            let tail: [Double] = Array(v.suffix(n))
            return tail.enumerated().map { MakeUpPoint(id: name + "\($0.offset)", day: $0.offset, value: $0.element, series: name) }
        }
        return pts("Cash", h.cash) + pts("Invested", h.invested) + pts("Companies", h.companies)
    }

    /// Three lines over the chosen period; today's three amounts under the chart (the key names them, so no second legend).
    private func makeUpCard(_ e: GameEngine) -> some View {
        let h: DayHistory = e.dayHistory
        let pts: [MakeUpPoint] = makeUpPoints(h)
        let names: [String] = ["Cash", "Invested", "Companies"]
        let colours: [String: Color] = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($0.element, ChartPalette.color($0.offset)) })
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            ChartFrame(title: "What it is made of", height: 110, isEmpty: h.cash.count < 2, emptyText: "The chart fills in day by day.") {
                Chart(pts) { (p: MakeUpPoint) in
                    LineMark(x: .value("Day", p.day), y: .value("Amount", p.value), series: .value("Series", p.series))
                        .foregroundStyle(colours[p.series] ?? ChartPalette.color(0))
                        .lineStyle(StrokeStyle(lineWidth: ChartPalette.lineWidth, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(ChartPalette.grid)
                        AxisValueLabel { if let d = v.as(Double.self) { Text(store.short(d)).font(ChartPalette.axisFont).foregroundStyle(ChartPalette.axis) } }
                    }
                }
            }
            makeUpNow(e, colours)
        }
    }

    private func makeUpNow(_ e: GameEngine, _ colours: [String: Color]) -> some View {
        let h: DayHistory = e.dayHistory
        return FigureRow(items: [
            KeyFigures.Item(label: "Cash", value: store.short(h.cash.last ?? 0), tint: colours["Cash"] ?? Theme.ink),
            KeyFigures.Item(label: "Invested", value: store.short(h.invested.last ?? 0), tint: colours["Invested"] ?? Theme.ink),
            KeyFigures.Item(label: "Companies", value: store.short(h.companies.last ?? 0), tint: colours["Companies"] ?? Theme.ink)
        ])
    }

    // MARK: Comparison rows

    private func compareCard(_ e: GameEngine) -> some View {
        let h: DayHistory = e.dayHistory
        let rows: [(String, Int)] = [("Past week", 7), ("Past month", 30), ("Past 3 months", 90)]
        return LedgerSection("Against the past") {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { (i: Int, r: (String, Int)) in
                    if i > 0 { Hairline() }
                    compareRow(r.0, change: DayHistory.change(h.netWorth, days: r.1))
                }
            }
        }
    }

    private func compareRow(_ label: String, change: (amount: Double, share: Double?)?) -> some View {
        let amount: Double = change?.amount ?? 0
        let sign: String = amount > 0 ? "+" : amount < 0 ? "\u{2212}" : ""
        let value: String = change == nil ? "Not enough history" : "\(sign)\(store.short(abs(amount)))"
        let share: String = change?.share.map { String(format: "%@%.1f%%", $0 >= 0 ? "+" : "\u{2212}", abs($0) * 100) } ?? ""
        let glyph: String = amount > 0 ? Glyph.arrowIn : amount < 0 ? Glyph.arrowOut : Glyph.minus
        let tint: Color = change == nil ? Theme.inkFaint : Theme.change(amount)
        return LedgerRow(leading: .glyph(glyph), leadingTint: tint, title: label, value: value, valueTint: tint, valueNote: share, valueNoteTint: tint, density: .compact)
    }

    // MARK: Economy

    private func economyCard(_ e: GameEngine) -> some View {
        let eco = e.state.economy
        let phase: String = eco.phase
        return LedgerSection(title: "The economy", trailing: {
            AcctPill(text: phase.capitalized, tone: phase == "boom" ? .good : phase == "recession" ? .bad : phase == "slowdown" ? .warn : .neutral)
        }) {
            if phase == "recession" || phase == "slowdown" {
                Text(phase == "recession" ? "The economy is in recession. Customer demand and rates below show how it reaches you." : "The economy is slowing. Customer demand and rates below show how it reaches you.")
                    .textStyle(.caption, tint: Theme.warn).fixedSize(horizontal: false, vertical: true)
            }
            FigureRow(items: [
                KeyFigures.Item(label: "Customer demand", value: signedPct(eco.demand - 1), tint: Theme.change(eco.demand - 1)),
                KeyFigures.Item(label: "Inflation", value: pct(eco.inflation)),
                KeyFigures.Item(label: "Central bank rate", value: pct(eco.policyRate)),
                KeyFigures.Item(label: "Fuel price", value: signedPct(eco.fuel - 1), tint: Theme.change(1 - eco.fuel))
            ], columns: 2)
        }
    }

    // MARK: Cost

    private struct CostBar: Identifiable {
        var id: String { name }
        var name: String
        var value: Double
    }

    /// The latest documents in the inbox (research reports and similar); each opens in the report viewer.
    @ViewBuilder private func documentsCard(_ e: GameEngine) -> some View {
        let docs: [Message] = Array(e.state.inbox.filter { $0.doc != nil }.suffix(3).reversed())
        if !docs.isEmpty {
            LedgerSection("Documents") {
                VStack(spacing: 0) {
                    ForEach(Array(docs.enumerated()), id: \.element.id) { (i: Int, m: Message) in
                        if let d = m.doc {
                            if i > 0 { Hairline() }
                            LedgerRow(leading: .glyph(Glyph.reports), title: d.title, density: .compact, action: { docItem = DocumentItem(id: m.id, doc: d) })
                                .newMarker(.stats, "m\(m.id)", style: .dot, alignment: .topLeading)
                        }
                    }
                }
            }
        }
    }

    private func costCard(_ e: GameEngine) -> some View {
        let st = e.state.stats
        let bars: [CostBar] = [CostBar(name: "Tax", value: st.taxPaid), CostBar(name: "Wages", value: st.wagesPaid), CostBar(name: "Interest", value: st.interestPaid)]
        let top: Double = max(bars.map { $0.value }.max() ?? 0, 1)
        return ChartFrame(title: "What it has cost", height: 112) {
            Chart(bars) { (b: CostBar) in
                BarMark(x: .value("Paid", b.value), y: .value("Kind", b.name), height: .fixed(14))
                    .foregroundStyle(ChartPalette.color(0))
                    .cornerRadius(3)
                    .annotation(position: .trailing, alignment: .center) {
                        Text(store.short(b.value)).font(ChartPalette.axisFont).foregroundStyle(ChartPalette.axis)
                    }
            }
            .chartXScale(domain: 0...(top * 1.45))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in AxisValueLabel().font(ChartPalette.axisFont).foregroundStyle(ChartPalette.axis) }
            }
        }
    }

    // MARK: Links

    private var activityLink: some View {
        NavigationLink {
            ActivityView().appScreen(title: "Activity", subtitle: PhonePage.activity.note)
        } label: {
            LedgerRow(leading: .glyph(Glyph.list), title: "Activity", subtitle: PhonePage.activity.note, chevron: true, identifier: "stats-activity")
        }
        .buttonStyle(AcctPressStyle())
    }

    private var goalsLink: some View {
        NavigationLink {
            GoalsView().appScreen(title: "Goals", subtitle: PhonePage.goals.note)
        } label: {
            LedgerRow(leading: .glyph(Glyph.goals), title: "Goals", subtitle: PhonePage.goals.note, chevron: true, identifier: "stats-goals")
        }
        .buttonStyle(AcctPressStyle())
    }

    private var reportsLink: some View {
        NavigationLink {
            ReportsScreen()
        } label: {
            LedgerRow(leading: .glyph(Glyph.reports), title: "Reports", subtitle: PhonePage.reports.note, chevron: true, identifier: "stats-reports")
        }
        .buttonStyle(AcctPressStyle())
    }

    private func pct(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }
    private func signedPct(_ x: Double) -> String { String(format: "%@%.0f%%", x >= 0 ? "+" : "\u{2212}", abs(x) * 100) }
}
