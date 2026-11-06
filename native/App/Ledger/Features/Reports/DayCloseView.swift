import SwiftUI

/// The day's close inside the daily report. The profit is the big figure (34 pt bold, counting from 0 in 0.4 s, green or red
/// with sign) and a thin 7-segment bar shows the days of the week, filled up to today, the seventh outlined. Both are shown by
/// `DailyReportPopup`.
struct DayCloseView: View {
    var profit: Double?
    /// Days played in the week so far (1 to 6 on an ordinary day).
    var daysDone: Int
    var instant: Bool
    var format: (Double) -> String
    /// The third line, in priority: a new Inbox item, the week's best day, the briefing's first sentence, else "A quiet day."
    var newInboxTitle: String? = nil
    var bestDay: Bool = false
    var briefing: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled: Int = 0

    var body: some View {
        let target: Int = min(max(daysDone, 0), 7)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let p = profit {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text("Profit today").popupText(.rowLabel)
                    CountedFigure(value: p, format: format, tint: Theme.change(p), instant: instant)
                        .font(PopupVariant.report.figureFont).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            Text(priorityLine).popupText(.subtitle).lineLimit(1)
            bar(shown: reduceMotion ? target : filled)
        }
        .padding(Theme.Space.s)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(Theme.warn.opacity(lostMoney ? 0.14 : 0)))
        .onAppear {
            filled = max(0, target - 1)
            Motion.animate(Motion.quick(reduceMotion)) { filled = target }
        }
    }

    /// Amber tint when the day lost money.
    private var lostMoney: Bool { (profit ?? 0) < -0.5 }

    /// One line, at most 70 characters.
    private var priorityLine: String {
        var line: String = "A quiet day."
        if let t = newInboxTitle, !t.isEmpty { line = "New in Inbox: " + t }
        else if bestDay { line = "Best day this week" }
        else if let b = briefing, !b.isEmpty { line = b }
        return line.count > 70 ? String(line.prefix(69)) + "\u{2026}" : line
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
