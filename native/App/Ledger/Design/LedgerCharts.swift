import SwiftUI
import Charts

/// Revenue and profit by month on a hairline grid: a champagne line for revenue, a green one for profit, labels at the right.
struct RevenueProfitChart: View {
    var revenue: [Double]
    var profit: [Double]
    var format: (Double) -> String
    var height: CGFloat = 92

    private struct Pt: Identifiable { var id: String; var x: Int; var y: Double; var series: String }

    var body: some View {
        let n = max(revenue.count, profit.count)
        let pts = revenue.enumerated().map { Pt(id: "r\($0.offset)", x: $0.offset + (n - revenue.count), y: $0.element, series: "Revenue") }
            + profit.enumerated().map { Pt(id: "p\($0.offset)", x: $0.offset + (n - profit.count), y: $0.element, series: "Profit") }
        if n >= 2 {
            Chart {
                ForEach(pts) { p in
                    LineMark(x: .value("Month", p.x), y: .value("Amount", p.y), series: .value("Series", p.series))
                        .foregroundStyle(p.series == "Revenue" ? Theme.gold : Theme.gain)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.ivoryFaint.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.hairline)
                    AxisValueLabel { if let d = v.as(Double.self) { Text(format(d)).font(.system(size: 9.5)).foregroundStyle(Theme.ivoryFaint) } }
                }
            }
            .frame(height: height)
        } else {
            Text("Monthly results appear once a month has closed.").font(.caption).foregroundStyle(Theme.ivoryFaint).frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        }
    }
}

/// The key to a two-line chart.
struct ChartKey: View {
    var items: [(String, Color)]
    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                HStack(spacing: 4) { Capsule().fill(it.1).frame(width: 10, height: 2); Text(it.0).font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint) }
            }
        }
    }
}
