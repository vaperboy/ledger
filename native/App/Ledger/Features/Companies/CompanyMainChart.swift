import SwiftUI
import Charts
import Simulation

/// The one graph on a company overview: revenue, profit or cash by month, with a range switch.
struct CompanyMainChart: View {
    enum Metric: String, CaseIterable, Hashable { case revenue = "Revenue", profit = "Profit", cash = "Cash" }
    enum Span: String, CaseIterable, Hashable {
        case half = "6 months", year = "1 year", all = "2 years"
        var months: Int { self == .half ? 6 : (self == .year ? 12 : 24) }
    }

    var health: CompanyHealth
    var format: (Double) -> String
    @Environment(\.outsidePalette) private var P
    @State private var metric: Metric = .cash
    @State private var span: Span = .year

    private struct Pt: Identifiable { var id: Int; var y: Double }

    private func series(_ m: Metric) -> [Double] {
        switch m {
        case .revenue: return health.revenueSeries
        case .profit: return health.profitSeries
        case .cash: return health.cashSeries
        }
    }

    private var values: [Double] { Array(series(metric).suffix(span.months)) }

    var body: some View {
        let v: [Double] = values
        let pts: [Pt] = v.enumerated().map { (i: Int, y: Double) -> Pt in Pt(id: i, y: y) }
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SegmentedPill(items: Metric.allCases, title: { (m: Metric) -> String in m.rawValue }, selection: $metric)
            if v.count >= 2 {
                caption(v)
                Chart {
                    ForEach(pts) { (p: Pt) in
                        AreaMark(x: .value("Month", p.id), y: .value("Amount", p.y))
                            .foregroundStyle(tint.opacity(ChartPalette.areaOpacity))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Month", p.id), y: .value("Amount", p.y))
                            .foregroundStyle(tint)
                            .lineStyle(StrokeStyle(lineWidth: ChartPalette.lineWidth, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                    }
                    RuleMark(y: .value("Zero", 0)).foregroundStyle(ChartPalette.zero).lineStyle(StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { (axis: AxisValue) in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(ChartPalette.grid)
                        AxisValueLabel {
                            if let d = axis.as(Double.self) { Text(format(d)).font(ChartPalette.axisFont).foregroundStyle(ChartPalette.axis) }
                        }
                    }
                }
                .frame(height: 160)
                .accessibilityLabel("\(metric.rawValue) by month")
                SegmentedPill(items: Span.allCases, title: { (s: Span) -> String in s.rawValue }, selection: $span)
            } else {
                Text("The graph appears once a month has closed.").textStyle(.caption, tint: P.inkFaint)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tint: Color {
        switch metric {
        case .revenue: return ChartPalette.color(0, in: P)
        case .profit: return ChartPalette.color(2, in: P)
        case .cash: return ChartPalette.color(1, in: P)
        }
    }

    private func caption(_ v: [Double]) -> some View {
        let last: Double = v[v.count - 1]
        let first: Double = v[0]
        let change: Double = last - first
        let up: Bool = change >= 0
        return HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(format(last)).textStyle(.figure, numeric: true)
            Text((up ? "up " : "down ") + format(abs(change)) + " over " + span.rawValue.lowercased())
                .textStyle(.caption, tint: up ? P.gain : P.loss)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
