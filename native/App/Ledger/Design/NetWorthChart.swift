import SwiftUI
import Charts
import Simulation

/// Net worth over a chosen period. The scale fits the period's own low and high (never from zero), so a fortune that moves
/// by a few percent still shows its shape; daily points for short periods, weekly points for the long view.
struct NetWorthChart: View {
    var engine: GameEngine
    var days: Int = 365
    /// The plot height; Home uses a thin 30 pt line.
    var height: CGFloat = 66

    private struct Point: Identifiable { var id: Int; var value: Double }

    var body: some View {
        let series = engine.netWorthSeries(days: days)
        let points: [Point] = series.enumerated().map { (i, v) in Point(id: i, value: v) }
        let lo = series.min() ?? 0, hi = series.max() ?? 0
        // Never zoom in so far that a fraction of a percent looks like a crash: the scale spans at least ±3% of the level.
        let pad = max((hi - lo) * 0.15, (abs(hi) * 0.06 - (hi - lo)) / 2, 1)
        let rising = (series.last ?? 0) >= (series.first ?? 0)
        let tint = rising ? Theme.gold : Theme.loss
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if points.count >= 2 {
                Chart(points) { p in
                    AreaMark(x: .value("Day", p.id), yStart: .value("Low", lo - pad), yEnd: .value("Net worth", p.value))
                        .foregroundStyle(LinearGradient(colors: [tint.opacity(0.20), tint.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Day", p.id), y: .value("Net worth", p.value))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: (lo - pad)...(hi + pad))
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: height)
                .animation(.snappy(duration: 0.3), value: days)
            } else {
                Text("The chart fills in day by day.").font(.caption).foregroundStyle(Theme.ivoryFaint).frame(maxWidth: .infinity, minHeight: height)
            }
        }
    }
}
