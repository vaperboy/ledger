import SwiftUI
import GameCore
import Countries
import Events
import Simulation

/// One "what changed" line of the day bar.
private struct BriefingLine: Identifiable {
    var id: Int
    var text: String
    var tint: Color
}

/// The insight of the day: one real thing worth knowing, with an optional button that opens the screen it is about.
private struct BriefingInsight {
    var label: String
    var text: String
    var tint: Color
    var buttonTitle: String?
    var action: Suggestion.Action?
}

/// What happened today, in one line on Home under the net worth: it never blocks the next day. A tap opens the day (figures, what
/// changed, the insight with its button) and the close button puts it away. Week, month and year closings keep their own report popup;
/// on those days there is no bar.
struct DayReportBar: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open: Bool = false

    var body: some View {
        if let digest = store.dailySheet {
            card(digest)
                .transition(.opacity)
                .onChange(of: digest.dateLabel) { _, _ in open = false }
        }
    }

    private func card(_ digest: DailyDigest) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                Button {
                    Haptics.tap()
                    Motion.animate(Motion.quick(reduceMotion)) { open.toggle() }
                } label: {
                    HStack(spacing: Theme.Space.s) {
                        Text(summary(digest)).textStyle(.caption, tint: Theme.ink).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: Theme.Space.xs)
                        Image(systemName: open ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkFaint)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(open ? "Hide today" : "Show today")
                .accessibilityIdentifier("day-bar")
                Button { Haptics.tap(); store.dismissDailySheet() } label: {
                    Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkFaint)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Dismiss")
                .accessibilityIdentifier("day-bar-dismiss")
            }
            if open { details(digest) }
        }
        .padding(.horizontal, Theme.Space.m)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(Theme.inset))
    }

    /// The closed line: the day, its change in net worth and the first thing worth knowing (a finished goal, sales, or a quiet day).
    private func summary(_ digest: DailyDigest) -> String {
        var parts: [String] = [digest.dateLabel]
        if let n = digest.netWorthChange { parts.append("net worth " + signedText(n)) }
        if let g = store.dayGoals.first { parts.append("goal reached: " + g) }
        else if digest.sales > 0 { parts.append("\(digest.sales) sale\(digest.sales == 1 ? "" : "s")") }
        else { parts.append("a quiet day") }
        return parts.joined(separator: " · ").tidyMoney
    }

    private func details(_ digest: DailyDigest) -> some View {
        let list: [BriefingLine] = lines(digest)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            DayCloseView(profit: digest.profit, daysDone: store.engine?.state.day ?? 0, instant: true, format: signedText,
                         newInboxTitle: digest.newInboxTitle, bestDay: digest.bestDayOfWeek, briefing: list.first?.text)
            ForEach(list) { (line: BriefingLine) in row(line) }
            insightView(insight(digest), compact: list.isEmpty)
        }
        .padding(.bottom, Theme.Space.m)
    }

    // MARK: Content from real data

    private func lines(_ digest: DailyDigest) -> [BriefingLine] {
        if digest.isEmpty && store.dayGoals.isEmpty { return [] }
        var out: [(String, Color)] = []
        for g in store.dayGoals.prefix(1) { out.append(("Goal reached: " + g, Theme.gain)) }
        if digest.sales > 0 {
            out.append(("\(digest.sales) sale\(digest.sales == 1 ? "" : "s"), \(store.short(digest.revenue)) taken", Theme.gain))
        }
        if let best = digest.bestCompany { out.append(("Busiest: \(best) with \(digest.bestSales)", Theme.gain)) }
        for h in digest.handled.prefix(1) { out.append((h, Theme.gold)) }
        for w in digest.wentWell.prefix(1) { out.append((w, Theme.gain)) }
        for m in digest.staffMessages.prefix(1) { out.append((m, Theme.caution)) }
        if digest.decisionsOpen > 0 {
            out.append(("\(digest.decisionsOpen) decision\(digest.decisionsOpen == 1 ? "" : "s") waiting in the Inbox", Theme.ivoryMuted))
        }
        var result: [BriefingLine] = []
        for (i, item) in out.prefix(4).enumerated() { result.append(BriefingLine(id: i + 1, text: item.0, tint: item.1)) }
        return result
    }

    private func insight(_ digest: DailyDigest) -> BriefingInsight {
        if store.engine != nil {
            let list: [Suggestion] = store.suggestionsNow.filter { $0.tone != .neutral }
            if let s = list.first {
                let label: String = s.tone == .good ? "Opportunity" : "Needs your attention"
                let tint: Color = s.tone == .bad ? Theme.loss : s.tone == .warn ? Theme.caution : Theme.gain
                return BriefingInsight(label: label, text: s.title.tidyMoney, tint: tint, buttonTitle: s.actionLabel, action: s.action)
            }
        }
        if let best = digest.bestCompany, digest.bestSales > 0 {
            return BriefingInsight(label: "Biggest mover", text: "\(best) led the day with \(digest.bestSales) sales.", tint: Theme.gold, buttonTitle: nil, action: nil)
        }
        let day: Int = store.engine?.state.day ?? 0
        let left: Int = max(1, 7 - day)
        let when: String = left == 1 ? "today" : "in \(left) days"
        return BriefingInsight(label: "Coming up", text: "The week closes \(when) and the weekly report follows.", tint: Theme.gold, buttonTitle: nil, action: nil)
    }

    // MARK: Views

    private func signedText(_ v: Double) -> String {
        abs(v) < 0.5 ? store.short(0) : (v > 0 ? "+" : "−") + store.short(abs(v))
    }

    private func row(_ line: BriefingLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(line.tint).frame(width: 5, height: 5).offset(y: -2)
            Text(line.text.tidyMoney).popupText(.body)
        }
    }

    private func insightView(_ item: BriefingInsight, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if compact { Text("A quiet day: nothing sold, nothing new in the Inbox.").popupText(.subtitle) }
            Text(item.label).textStyle(.label, tint: item.tint)
            Text(item.text).popupText(.body).fixedSize(horizontal: false, vertical: true)
            if let title = item.buttonTitle, let action = item.action {
                Button {
                    Haptics.tap()
                    store.go(popup: action)
                } label: {
                    Text(title + " ›").popupText(.effect).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle()).accessibilityIdentifier("daily-insight-action")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
