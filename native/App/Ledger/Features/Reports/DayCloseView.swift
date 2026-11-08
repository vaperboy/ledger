import SwiftUI

/// The day's close inside the daily report: a thin 7-segment bar of the week (filled up to today, the seventh outlined), the day's
/// profit on one line (counting from 0, a green up or red down arrow) and one priority line. Shown by `DailyReportPopup`.
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
            bar(shown: reduceMotion ? target : filled)
            if let p = profit {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text("Profit today").popupText(.body)
                    Spacer(minLength: Theme.Space.s)
                    ArrowAmount(gain: p, format: format, live: true, instant: instant, step: .headline).lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
            Text(priorityLine).popupText(.subtitle).lineLimit(2)
        }
        .onAppear {
            filled = max(0, target - 1)
            Motion.animate(Motion.quick(reduceMotion)) { filled = target }
        }
    }

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
                    Capsule().fill(i < shown ? Theme.ink.opacity(0.85) : Theme.line)
                    if i == 6 { Capsule().strokeBorder(Theme.inkFaint, lineWidth: 1) }
                }
                .frame(height: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Day \(shown) of 7")
    }
}
