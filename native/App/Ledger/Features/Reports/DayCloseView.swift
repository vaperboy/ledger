import SwiftUI

/// Brief 3.0: the day's close inside the daily report. The profit is the big figure (34 pt bold, counting from 0 in 0.4 s, green or red
/// with sign) and a thin 7-segment bar shows the days of the week, filled up to today, the seventh outlined. Both are shown by
/// `DailyReportPopup`; the report itself is unchanged (owner decision).
struct DayCloseView: View {
    var profit: Double?
    /// Days played in the week so far (1 to 6 on an ordinary day).
    var daysDone: Int
    var instant: Bool
    var format: (Double) -> String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled: Int = 0

    var body: some View {
        let target: Int = min(max(daysDone, 0), 7)
        VStack(alignment: .leading, spacing: 8) {
            if let p = profit {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Profit today").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    CountedFigure(value: p, format: format, tint: Theme.change(p), instant: instant)
                        .font(.system(size: 34, weight: .bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            bar(shown: reduceMotion ? target : filled)
        }
        .onAppear {
            filled = max(0, target - 1)
            Motion.animate(Motion.quick(reduceMotion)) { filled = target }
        }
    }

    private func bar(shown: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { (i: Int) in
                ZStack {
                    Capsule().fill(i < shown ? Theme.gold : Theme.ivoryFaint.opacity(0.18))
                    if i == 6 { Capsule().strokeBorder(Theme.gold.opacity(0.6), lineWidth: 1) }
                }
                .frame(height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Day \(shown) of 7")
    }
}
