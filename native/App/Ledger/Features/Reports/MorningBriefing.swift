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
    @State private var barFill: Double = 0

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
            let list: [Suggestion] = e.suggestions(limit: 8).filter { $0.tone != .neutral }
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
        withAnimation(.easeInOut(duration: total)) { barFill = 1 }
        var elapsed: Double = 0
        for i in 0..<n {
            let at: Double = timeFor(progress: (Double(i) + 0.5) / Double(n)) * total
            let wait: Double = max(0, at - elapsed)
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            if skipped { return }
            elapsed = max(elapsed, at)
            withAnimation(.easeOut(duration: 0.3)) { revealed = i + 1 }
        }
        let rest: Double = max(0, total - elapsed)
        try? await Task.sleep(nanoseconds: UInt64(rest * 1_000_000_000))
        if skipped { return }
        withAnimation(.easeOut(duration: 0.3)) { showContinue = true }
    }

    private func skip(count n: Int) {
        if reduceMotion || skipped || showContinue { return }
        skipped = true
        withAnimation(.easeOut(duration: 0.15)) { revealed = n; barFill = 1 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            withAnimation(.easeOut(duration: 0.3)) { showContinue = true }
        }
    }

    private var loadingBar: some View {
        let fill: Double = reduceMotion ? 1 : barFill
        return ZStack(alignment: .leading) {
            Capsule().fill(Theme.ivoryFaint.opacity(0.18))
            Capsule().fill(Theme.gold).scaleEffect(x: max(fill, 0.001), y: 1, anchor: .leading)
        }
        .frame(height: 2.5)
        .accessibilityHidden(true)
    }

    // MARK: Views

    var body: some View {
        let list: [BriefingLine] = lines
        let total: Int = list.count + 2
        let canContinue: Bool = reduceMotion || showContinue
        GamePopup(title: digest.dateLabel, showsClose: false, dismissOnBackdrop: false, onClose: { store.dismissDailySheet() }) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Morning briefing").capsLabel()
                    headline.modifier(BriefingStep(shown: visible(0)))
                    loadingBar
                    ForEach(list) { (line: BriefingLine) in
                        row(line).modifier(BriefingStep(shown: visible(line.id)))
                    }
                    insightView(insight, compact: list.isEmpty).modifier(BriefingStep(shown: visible(total - 1)))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { skip(count: total) }
                PopupOptionButton(title: "Continue", highlighted: true, identifier: "daily-continue") { store.dismissDailySheet() }
                    .opacity(canContinue ? 1 : 0)
                    .allowsHitTesting(canContinue)
                    .accessibilityHidden(!canContinue)
            }
        }
        .task { await run(count: total) }
    }

    @ViewBuilder private var headline: some View {
        if let n = digest.netWorthChange {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Net worth today").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    CountedFigure(value: n, format: signedText, tint: Theme.change(n), instant: instant)
                        .font(.serifTitle(30)).lineLimit(1).minimumScaleFactor(0.6)
                }
                Spacer(minLength: 8)
                if let c = digest.cashChange {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Cash").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                        CountedFigure(value: c, format: signedText, tint: Theme.change(c), instant: instant)
                            .font(.system(size: 16, weight: .medium).monospacedDigit()).lineLimit(1)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Taken today").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                CountedFigure(value: digest.revenue, format: signedText, tint: Theme.change(digest.revenue), instant: instant)
                    .font(.serifTitle(30)).lineLimit(1).minimumScaleFactor(0.6)
            }
        }
    }

    private func signedText(_ v: Double) -> String {
        abs(v) < 0.5 ? store.short(0) : (v > 0 ? "+" : "−") + store.short(abs(v))
    }

    private func row(_ line: BriefingLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(line.tint).frame(width: 5, height: 5).offset(y: -2)
            Text(line.text.tidyMoney).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func insightView(_ item: BriefingInsight, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if compact { Text("A quiet day: nothing sold, nothing new in the Inbox.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint) }
            Text(item.label).capsLabel()
            Text(item.text).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
            if let title = item.buttonTitle, let action = item.action {
                Button {
                    Haptics.tap()
                    store.dismissDailySheet()
                    store.go(popup: action)
                } label: {
                    Text(title + " ›").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.gold).frame(minHeight: 32).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle()).accessibilityIdentifier("daily-insight-action")
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .overlay(alignment: .leading) { Rectangle().fill(item.tint).frame(width: 2).padding(.vertical, 10) }
    }
}

/// A briefing part: hidden (but taking its space, so nothing jumps) until its turn, then it fades and rises a few points in.
private struct BriefingStep: ViewModifier {
    var shown: Bool
    func body(content: Content) -> some View {
        content.opacity(shown ? 1 : 0).offset(y: shown ? 0 : 6)
    }
}
