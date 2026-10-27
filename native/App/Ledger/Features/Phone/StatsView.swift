import SwiftUI
import Charts
import GameCore
import Finance
import Simulation

/// Stats app: tiles and charts. A grid of figure tiles first (best, now, weeks, sales), then the net worth trend and what it is made
/// of from the engine's recorded daily history, comparison rows against the past, the economy as four tiles, and what the run has cost
/// as a bar chart. Every figure is read from the engine; money goes through the store formatters.
struct StatsView: View {
    @EnvironmentObject var store: GameStore
    @State private var period = 90

    private static let periods: [Int] = [30, 90, 365]

    var body: some View {
        if let e = store.engine {
            PhonePageScroll(spacing: 14) {
                figureTiles(e)
                trendCard(e)
                makeUpCard(e)
                compareCard(e)
                economyCard(e)
                costCard(e)
                activityLink
                TrophiesPreview()
            }
        }
    }

    // MARK: Figure tiles

    private func figureTiles(_ e: GameEngine) -> some View {
        let s = e.state
        let nw: NetWorth = e.netWorth
        let best: Double = max(s.stats.peakNetWorth, nw.total)
        let ofBest: String = best > 0 ? String(format: "%.0f%% of your best", max(0, nw.total) / best * 100) : "No best yet"
        let columns: [GridItem] = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            StatsTile(glyph: Glyph.richList, label: "Best net worth", value: store.short(best), sub: "Highest so far")
            StatsTile(glyph: Glyph.stats, label: "Net worth now", value: store.short(nw.total), sub: ofBest, tint: nw.total < 0 ? Theme.loss : Theme.ivory)
            StatsTile(glyph: Glyph.ovCalendar, label: "Weeks played", value: "\(s.week)", sub: "Since you started")
            StatsTile(glyph: Glyph.building, label: "Companies sold", value: "\(s.stats.companiesSold)", sub: s.stats.bankruptcies > 0 ? "\(s.stats.bankruptcies) bankruptcies" : "No bankruptcies")
        }
    }

    // MARK: Trend

    private func trendCard(_ e: GameEngine) -> some View {
        let series: [Double] = e.netWorthSeries(days: period)
        return Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Net worth").capsLabel()
                    Spacer()
                    trendChange(series)
                }
                NetWorthChart(engine: e, days: period, height: 120)
                SegmentedPill(items: Self.periods, title: { $0 == 30 ? "1M" : $0 == 90 ? "3M" : "1Y" }, selection: $period)
            }
        }
    }

    @ViewBuilder private func trendChange(_ series: [Double]) -> some View {
        if let first = series.first, let last = series.last, series.count >= 2 {
            let d: Double = last - first
            let sign: String = d > 0 ? "+" : d < 0 ? "\u{2212}" : ""
            Text("\(sign)\(store.short(abs(d)))").font(.system(size: 13, weight: .medium).monospacedDigit()).foregroundStyle(Theme.change(d))
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

    private func makeUpCard(_ e: GameEngine) -> some View {
        let h: DayHistory = e.dayHistory
        let pts: [MakeUpPoint] = makeUpPoints(h)
        let colours: [String: Color] = ["Cash": Theme.gold, "Invested": Theme.gain, "Companies": Theme.slateBlue]
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("What it is made of").capsLabel()
                    Spacer()
                    ChartKey(items: [("Cash", Theme.gold), ("Invested", Theme.gain), ("Companies", Theme.slateBlue)])
                }
                if h.cash.count >= 2 {
                    Chart(pts) { (p: MakeUpPoint) in
                        LineMark(x: .value("Day", p.day), y: .value("Amount", p.value), series: .value("Series", p.series))
                            .foregroundStyle(colours[p.series] ?? Theme.gold)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.hairline)
                            AxisValueLabel { if let d = v.as(Double.self) { Text(store.short(d)).font(.system(size: 9.5)).foregroundStyle(Theme.ivoryFaint) } }
                        }
                    }
                    .frame(height: 110)
                } else {
                    Text("The chart fills in day by day.").font(.caption).foregroundStyle(Theme.ivoryFaint)
                }
                makeUpNow(e)
            }
        }
    }

    private func makeUpNow(_ e: GameEngine) -> some View {
        let h: DayHistory = e.dayHistory
        return StatStrip(cells: [
            .init(label: "Cash", value: store.short(h.cash.last ?? 0)),
            .init(label: "Invested", value: store.short(h.invested.last ?? 0)),
            .init(label: "Companies", value: store.short(h.companies.last ?? 0))
        ])
    }

    // MARK: Comparison rows

    private func compareCard(_ e: GameEngine) -> some View {
        let h: DayHistory = e.dayHistory
        let rows: [(String, Int)] = [("Past week", 7), ("Past month", 30), ("Past 3 months", 90)]
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Against the past").capsLabel().padding(.bottom, 6)
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    if i > 0 { CardLine() }
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
        return RowLine(glyph: glyph, tint: change == nil ? Theme.ivoryFaint : Theme.change(amount), title: label,
                       trailing: value, trailingSub: share, trailingTint: change == nil ? Theme.ivoryFaint : Theme.change(amount))
    }

    // MARK: Economy

    private func economyCard(_ e: GameEngine) -> some View {
        let eco = e.state.economy
        let phase: String = eco.phase
        let columns: [GridItem] = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("The economy").capsLabel()
                Spacer()
                Chip(text: phase.capitalized, tint: phaseTint(phase))
            }
            .padding(.horizontal, 2)
            if phase == "recession" || phase == "slowdown" {
                Text(phase == "recession" ? "The economy is in recession. Customer demand and rates below show how it reaches you." : "The economy is slowing. Customer demand and rates below show how it reaches you.")
                    .font(.system(size: 13)).foregroundStyle(Theme.caution).fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(columns: columns, spacing: 10) {
                StatsTile(glyph: Glyph.market, label: "Customer demand", value: signedPct(eco.demand - 1), tint: Theme.change(eco.demand - 1), compact: true)
                StatsTile(glyph: Glyph.cost, label: "Inflation", value: pct(eco.inflation), compact: true)
                StatsTile(glyph: Glyph.bank, label: "Central bank rate", value: pct(eco.policyRate), compact: true)
                StatsTile(glyph: Glyph.ovCoin, label: "Fuel price", value: signedPct(eco.fuel - 1), tint: Theme.change(1 - eco.fuel), compact: true)
            }
        }
    }

    // MARK: Cost

    private struct CostBar: Identifiable {
        var id: String { name }
        var name: String
        var value: Double
    }

    private func costCard(_ e: GameEngine) -> some View {
        let st = e.state.stats
        let bars: [CostBar] = [CostBar(name: "Tax", value: st.taxPaid), CostBar(name: "Wages", value: st.wagesPaid), CostBar(name: "Interest", value: st.interestPaid)]
        let top: Double = max(bars.map { $0.value }.max() ?? 0, 1)
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What it has cost").capsLabel()
                Chart(bars) { (b: CostBar) in
                    BarMark(x: .value("Paid", b.value), y: .value("Kind", b.name), height: .fixed(14))
                        .foregroundStyle(Theme.gold.opacity(0.85))
                        .cornerRadius(3)
                        .annotation(position: .trailing, alignment: .center) {
                            Text(store.short(b.value)).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
                        }
                }
                .chartXScale(domain: 0...(top * 1.45))
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in AxisValueLabel().font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted) }
                }
                .frame(height: 112)
                CardLine()
                HStack {
                    Text("Bankruptcies").font(.system(size: 13.5)).foregroundStyle(Theme.ivoryMuted)
                    Spacer()
                    Text("\(st.bankruptcies)").font(.system(size: 14, weight: .medium).monospacedDigit()).foregroundStyle(st.bankruptcies > 0 ? Theme.loss : Theme.ivory)
                }
            }
        }
    }

    // MARK: Activity link

    private var activityLink: some View {
        NavigationLink {
            ActivityView().appScreen(title: "Activity", subtitle: PhonePage.activity.note)
        } label: {
            Card(padding: 12, radius: Theme.Radius.row) {
                RowLine(glyph: Glyph.list, title: "Activity", subtitle: PhonePage.activity.note, chevron: true)
            }
        }
        .buttonStyle(.plain)
    }

    private func pct(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }
    private func signedPct(_ x: Double) -> String { String(format: "%@%.0f%%", x >= 0 ? "+" : "\u{2212}", abs(x) * 100) }
    private func phaseTint(_ p: String) -> Color { p == "boom" ? Theme.gain : p == "recession" ? Theme.loss : p == "slowdown" ? Theme.caution : Theme.ivoryMuted }
}

/// A figure tile: a small icon circle, a grey label, a serif figure and an optional grey line, in its own bordered card.
struct StatsTile: View {
    var glyph: String
    var label: String
    var value: String
    var sub: String = ""
    var tint: Color = Theme.ivory
    var compact = false

    var body: some View {
        Card(padding: 12, radius: Theme.Radius.card) {
            VStack(alignment: .leading, spacing: 6) {
                IconCircle(glyph: glyph, size: compact ? 28 : 32)
                Text(label).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(1).minimumScaleFactor(0.8)
                Text(value.tidyText).font(.hero(compact ? 20 : 24)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6)
                if !sub.isEmpty { Text(sub.tidyText).font(.system(size: 11)).foregroundStyle(Theme.ivoryMuted).lineLimit(2) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
