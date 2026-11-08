import SwiftUI
import Simulation

/// Net worth over a chosen period. The scale fits the period's own low and high (never from zero), so a fortune that moves
/// by a few percent still shows its shape; daily points for short periods, weekly points for the long view. The line is drawn once on
/// first appearance; a new day only extends it (see `LiveSparkline`).
struct NetWorthChart: View {
    var engine: GameEngine
    var days: Int = 365
    /// The plot height; Home uses a thin 30 pt line.
    var height: CGFloat = 66
    /// A series to draw instead of the live one (Home keeps the chart of the day before while the daily report is waiting).
    var frozen: [Double]? = nil

    /// The scale spans the low and high, padded: never so tight that a fraction of a percent looks like a crash (at least ±3% of the level).
    private static func scale(_ series: [Double]) -> (Double, Double) {
        let lo = series.min() ?? 0, hi = series.max() ?? 0
        let pad = max((hi - lo) * 0.15, (abs(hi) * 0.06 - (hi - lo)) / 2, 1)
        return (lo - pad, hi + pad)
    }

    var body: some View {
        let series: [Double] = frozen ?? engine.netWorthSeries(days: days)
        let rising = (series.last ?? 0) >= (series.first ?? 0)
        let tint = rising ? Theme.gold : Theme.loss
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if series.count >= 2 {
                LiveSparkline(values: series, tint: tint, filled: true, range: Self.scale)
                    .frame(height: height)
                    .drawsItself()
                    .accessibilityHidden(true)
            } else {
                Text("The chart fills in day by day.").textStyle(.caption, tint: Theme.inkFaint).frame(maxWidth: .infinity, minHeight: height)
            }
        }
    }
}
