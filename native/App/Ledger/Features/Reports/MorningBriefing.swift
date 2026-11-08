import SwiftUI
import GameCore
import Countries
import Events
import Simulation

/// One "what changed" line of the morning briefing.
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

/// The morning briefing after an ordinary day: the day's change in net worth and cash counts up, two or three lines say what changed and why,
/// then one insight of the day (a suggestion, the busiest company or the week's close) with an optional button. The parts arrive one after
/// the other and Continue fades in at about 1.4 s; one tap on the card finishes the reveal at once and Continue follows 0.4 s later.
/// Under Reduce Motion everything is there at once. A quiet day shows the compact version (two lines) with the same pacing.
struct DailyReportPopup: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var digest: DailyDigest
    @State private var revealed: Int = 0
    @State private var showContinue: Bool = false
    @State private var skipped: Bool = false

    // MARK: Content from real data

    private var lines: [BriefingLine] {
        if digest.isEmpty { return [] }
        var out: [(String, Color)] = []
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
        for (i, item) in out.prefix(3).enumerated() { result.append(BriefingLine(id: i + 1, text: item.0, tint: item.1)) }
        return result
    }

    private var insight: BriefingInsight {
        if let e = store.engine {
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

    // MARK: Pacing

    private var instant: Bool { reduceMotion || skipped }

    private func visible(_ index: Int) -> Bool { reduceMotion || revealed > index }

    private static let barDuration: Double = 1.6

    /// The time (0...1 of the bar) at which the eased bar has reached `p`: the inverse of a smooth ease-in-out.
    private func timeFor(progress p: Double) -> Double {
        var lo: Double = 0
        var hi: Double = 1
        for _ in 0..<20 {
            let mid: Double = (lo + hi) / 2
            let v: Double = mid * mid * (3 - 2 * mid)
            if v < p { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    private func run(count n: Int) async {
        if reduceMotion { return }
        let total: Double = Self.barDuration
        var elapsed: Double = 0
        for i in 0..<n {
            let at: Double = timeFor(progress: (Double(i) + 0.5) / Double(n)) * total
            let wait: Double = max(0, at - elapsed)
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            if skipped { return }
            elapsed = max(elapsed, at)
            Motion.animate(Motion.quickAnimation) { revealed = i + 1 }
        }
        let rest: Double = max(0, total - elapsed)
        try? await Task.sleep(nanoseconds: UInt64(rest * 1_000_000_000))
        if skipped { return }
        Motion.animate(Motion.quickAnimation) { showContinue = true }
    }

    private func skip(count n: Int) {
        if reduceMotion || skipped || showContinue { return }
        skipped = true
        Motion.animate(Motion.tapAnimation) { revealed = n }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            Motion.animate(Motion.quickAnimation) { showContinue = true }
        }
    }

    // MARK: Views

    var body: some View {
        let list: [BriefingLine] = lines
        let total: Int = list.count + 2
        let canContinue: Bool = reduceMotion || showContinue
        GamePopup(title: digest.dateLabel, showsClose: false, dismissOnBackdrop: false, category: .medium, tone: .info, onClose: { store.dismissDailySheet() }) {
            VStack(alignment: .leading, spacing: PopupSpace.block) {
                VStack(alignment: .leading, spacing: PopupSpace.block) {
                    Text("Morning briefing").textStyle(.label, tint: Theme.inkFaint)
                    headline.modifier(BriefingStep(shown: visible(0)))
                    ForEach(list) { (line: BriefingLine) in
                        row(line).modifier(BriefingStep(shown: visible(line.id)))
                    }
                    insightView(insight, compact: list.isEmpty).modifier(BriefingStep(shown: visible(total - 1)))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { skip(count: total) }
            }
            // Continue is pinned and in the layout from the start (only faded), so the card never reflows when it appears.
            .popupFooter {
                PopupOptionButton(title: "Continue", highlighted: true, identifier: "daily-continue") { store.dismissDailySheet() }
                    .opacity(canContinue ? 1 : 0)
                    .allowsHitTesting(canContinue)
                    .accessibilityHidden(!canContinue)
            }
        }
        .task { await run(count: total) }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 10) {
            headlineFigures
            DayCloseView(profit: digest.profit, daysDone: store.engine?.state.day ?? 0, instant: instant, format: { (v: Double) -> String in store.short(v) },
                         newInboxTitle: digest.newInboxTitle, bestDay: digest.bestDayOfWeek, briefing: lines.first?.text)
        }
    }

    @ViewBuilder private var headlineFigures: some View {
        if let n = digest.netWorthChange {
            VStack(alignment: .leading, spacing: 2) {
                Text("Net worth today").popupText(.rowLabel)
                ArrowAmount(gain: n, format: { (v: Double) -> String in store.short(v) }, live: true, instant: instant, font: PopupVariant.report.figureFont, arrowSide: 18)
                    .lineLimit(2).minimumScaleFactor(0.8)
                if let c = digest.cashChange {
                    HStack(spacing: Theme.Space.xs) {
                        Text("Cash").popupText(.caption)
                        ArrowAmount(gain: c, format: { (v: Double) -> String in store.short(v) }, live: true, instant: instant, step: .caption, weight: .medium).lineLimit(1)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Taken today").popupText(.rowLabel)
                ArrowAmount(gain: digest.revenue, format: { (v: Double) -> String in store.short(v) }, live: true, instant: instant, font: PopupVariant.report.figureFont, arrowSide: 18)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
        }
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
                    store.dismissDailySheet()
                    store.go(popup: action)
                } label: {
                    Text(title + " ›").popupText(.effect).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle()).accessibilityIdentifier("daily-insight-action")
            }
        }
        .padding(Theme.Space.m).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(Theme.inset))
    }
}

/// A briefing part: hidden (but taking its space, so nothing jumps) until its turn, then it fades and rises a few points in.
private struct BriefingStep: ViewModifier {
    var shown: Bool
    func body(content: Content) -> some View {
        content.opacity(shown ? 1 : 0).offset(y: shown ? 0 : 6)
    }
}
