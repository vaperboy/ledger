import SwiftUI
import GameCore
import Countries
import Events
import Simulation

/// The popup that appears on the main screen when a week, a month or a year closes. It is read and dismissed with one tap before the next day
/// can run: a natural pause, real figures only, one sheet per closing (a year covers its month and week). "Open in Reports" goes to the detail.
struct ReportDigestSheet: View {
    @EnvironmentObject var store: GameStore
    var digest: ReportDigest

    var body: some View {
        WeekReportShell(digest: digest) { sections }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            header.staggerReveal(0)
            figures.staggerReveal(1)
            list("Major changes", digest.changes, tint: Theme.ivory).staggerReveal(2)
            list("Risks", digest.risks, tint: Theme.caution).staggerReveal(3)
            decisions.staggerReveal(4)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(digest.kind.title + " report").capsLabel()
            Text(digest.range).popupText(.caption)
            Text(headline).popupText(.title)
        }
    }

    /// One plain sentence on how the period went and what moved it, from the digest's own figures (nothing invented).
    private var headline: String {
        let profit: Double = digest.netProfit
        var s: String = profit >= 0 ? "A profit of \(store.short(profit))" : "A loss of \(store.short(abs(profit)))"
        if digest.revenue > 0.5 { s += " on \(store.short(digest.revenue)) of sales" }
        s += "."
        if profit > 0 && digest.cashChange < 0 { s += " Cash still fell by \(store.short(abs(digest.cashChange))): see where the money went." }
        else if profit < 0 && digest.cashChange > 0 { s += " Cash rose anyway, so a loan or a sale is behind it." }
        else if abs(digest.netWorthChange) > 0.5 { s += " Net worth \(digest.netWorthChange > 0 ? "rose" : "fell") by \(store.short(abs(digest.netWorthChange)))." }
        return s
    }

    private var figures: some View {
        let profit: Double = digest.netProfit
        return Card(padding: 12, radius: Theme.Radius.hero) {
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    figure("Revenue", digest.revenue, Theme.ivory) { store.short($0) }
                    figure("Profit", profit, Theme.change(profit)) { signed($0) }.profitGlow(profit)
                }
                HStack(alignment: .top, spacing: 12) {
                    figure("Cash", digest.cashEnd, digest.cashEnd < 0 ? Theme.loss : Theme.ivory) { store.short($0) }
                    figure("Debt", digest.debt, digest.debt > 0.5 ? Theme.loss : Theme.ivory) { store.short($0) }
                }
                HStack(alignment: .top, spacing: 12) {
                    figure("Payroll", digest.payroll, Theme.ivory) { store.short($0) }
                    figure("Taxes paid", digest.taxes, Theme.ivory) { store.short($0) }
                }
                Rectangle().fill(Theme.divider).frame(height: 1)
                HStack {
                    Text("Net worth").popupText(.rowLabel)
                    Spacer()
                    CountedFigure(value: digest.netWorthEnd, format: { (v: Double) -> String in store.short(v) }, tint: Theme.ivory).font(PopupVariant.standard.valueFont)
                    CountedFigure(value: digest.netWorthChange, format: { (v: Double) -> String in signed(v) }, tint: Theme.change(digest.netWorthChange)).font(PopupVariant.standard.valueFont)
                }
            }
        }
    }

    private func figure(_ label: String, _ value: Double, _ tint: Color, _ text: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).popupText(.rowLabel)
            CountedFigure(value: value, format: text, tint: tint).font(PopupVariant.standard.figureFont).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func list(_ title: String, _ lines: [String], tint: Color) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).capsLabel()
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(tint).frame(width: 5, height: 5).offset(y: -2)
                        Text(line.tidyMoney).popupText(.body)
                    }
                }
            }
        }
    }

    private var decisions: some View {
        let answered: String = digest.decisionsAnswered == 1 ? "1 decision answered" : "\(digest.decisionsAnswered) decisions answered"
        let waiting: String = digest.decisionsOpen == 0 ? "none waiting" : "\(digest.decisionsOpen) waiting in the Inbox"
        return VStack(alignment: .leading, spacing: 4) {
            Text("Decisions").capsLabel()
            Text(answered + ", " + waiting).popupText(.body)
        }
    }

    private func signed(_ v: Double) -> String { abs(v) < 0.5 ? store.short(0) : (v > 0 ? "+" : "−") + store.short(abs(v)) }
}

/// A reward popup: a trophy, a milestone or a finished ladder goal. One at a time, from the queue the store holds after a day;
/// it says what the goal changed, arrives with a calm animation (none under Reduce Motion) and a light haptic.
struct CelebrationPopup: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var item: Celebration
    @State private var shown = false
    /// Goal complete: the card turns green, the check draws itself, the reward fades in.
    @State private var goalShown = false
    @State private var checkDrawn: CGFloat = 0
    /// Goal complete: after `celebrate` (1.5 s) the card slides up and out with `move`.
    @State private var leaving = false

    /// A trophy or a net-worth milestone fills the screen; Reduce Motion keeps the card.
    private var fullScreen: Bool { !reduceMotion && (item.kind == "trophy" || (item.kind == "milestone" && item.art == "milestone.networth")) }

    var body: some View {
        Group {
            if fullScreen {
                FullScreenCelebration(kicker: kindLabel, title: item.title, detail: item.detail, reward: item.reward, onClaim: { dismiss() }) { badge }
            } else {
                GamePopup(title: kindLabel, showsClose: false, dismissOnBackdrop: false, variant: .reward, category: .compact, tone: .investment, icon: "trophy", onClose: { }) {
                    card
                }
            }
        }
        .offset(y: leaving ? -900 : 0)
        .onAppear {
            if item.kind == "goal" {
                Motion.animate(Motion.quick(reduceMotion)) { goalShown = true }
                Motion.animate(Motion.reveal(reduceMotion)) { checkDrawn = 1 }
                let id: Int = item.id
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(Motion.celebrateSeconds * 1_000_000_000))
                    guard store.celebrationQueue.first?.id == id else { return }
                    Motion.animate(Motion.move(reduceMotion)) { leaving = true }
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    if store.celebrationQueue.first?.id == id { store.dismissCelebration() }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var card: some View {
        VStack(spacing: PopupSpace.block) {
            badge
            Text(item.title).popupText(.figure, variant: .reward).multilineTextAlignment(.center)
            if !item.detail.isEmpty {
                Text(item.detail).popupText(.subtitle).multilineTextAlignment(.center)
            }
            if !item.reward.isEmpty {
                Text(item.reward).popupText(.rowValue).multilineTextAlignment(.center)
                    .opacity(item.kind != "goal" || goalShown || reduceMotion ? 1 : 0)
            }
            dismissButton
        }
        .frame(maxWidth: .infinity)
    }

    /// The way out once nothing is left to claim here: the pulsing Claim for a trophy or milestone (already paid), else Nice, Next or Done.
    @ViewBuilder private var dismissButton: some View {
        if dismissTitle == "Claim" {
            ClaimButton(title: "Claim", identifier: "celebration-dismiss") { dismiss() }.padding(.top, 4)
        } else {
            Button(dismissTitle) { dismiss() }
                .buttonStyle(ImportantButtonStyle()).padding(.top, 4).accessibilityIdentifier("celebration-dismiss")
        }
    }

    /// A finished goal: the week report tells it in a line instead of this popup.
    static func foldsIntoReport(_ item: Celebration) -> Bool { item.kind == "goal" }

    /// A goal closes with "Nice"; a trophy or milestone (nothing to take) with the pulsing Claim.
    private var dismissTitle: String { item.kind == "goal" ? "Nice" : "Claim" }

    private var trophyEntry: Trophies.Entry? {
        guard item.kind == "trophy", let e = store.engine else { return nil }
        return Trophies.entries(e.state).first(where: { $0.name == item.title })
    }

    /// The earned trophy's art in a large gold ring; a drawn gold medal when nothing maps to the title.
    @ViewBuilder private var badge: some View {
        if item.kind == "goal" {
            GoalCheckMark(progress: reduceMotion ? 1 : checkDrawn)
                .stroke(Theme.gain, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                .frame(width: 34, height: 26).padding(14)
                .overlay(Circle().strokeBorder(Theme.gain, lineWidth: 2))
                .accessibilityHidden(true)
        } else if let entry = trophyEntry {
            ThumbnailView(kind: .trophy, key: ArtLibrary.trophyKey(id: entry.id, group: entry.group), size: fullScreen ? 168 : 112, shape: .round, glyph: Glyph.achievements)
                .padding(6)
                .overlay(Circle().strokeBorder(Theme.gold, lineWidth: fullScreen ? 5 : 3))
                .padding(8)
        } else {
            GoldRingMark(glyph: Glyph.achievements, size: fullScreen ? 150 : (item.kind == "trophy" ? 96 : 64))
        }
    }

    private var kindLabel: String {
        switch item.kind {
        case "trophy": return "Trophy earned"
        case "milestone": return "Milestone reached"
        default: return "Goal reached"
        }
    }

    private func dismiss() {
        Motion.run(reduceMotion) { store.dismissCelebration() }
    }
}

/// A check mark that draws itself as `progress` goes from 0 to 1.
struct GoalCheckMark: Shape {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.1))
        p.addLine(to: CGPoint(x: rect.width * 0.38, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p.trimmedPath(from: 0, to: max(0.001, min(progress, 1)))
    }
}
