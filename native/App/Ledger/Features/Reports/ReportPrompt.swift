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
            Text(digest.range).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
            Text(headline).font(.serifTitle(17)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
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
                    Text("Net worth").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                    Spacer()
                    CountedFigure(value: digest.netWorthEnd, format: { (v: Double) -> String in store.short(v) }, tint: Theme.ivory).font(.system(size: 13.5, weight: .medium).monospacedDigit())
                    CountedFigure(value: digest.netWorthChange, format: { (v: Double) -> String in signed(v) }, tint: Theme.change(digest.netWorthChange)).font(.system(size: 12).monospacedDigit())
                }
            }
        }
    }

    private func figure(_ label: String, _ value: Double, _ tint: Color, _ text: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            CountedFigure(value: value, format: text, tint: tint).font(.system(size: 18, weight: .medium).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
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
                        Text(line.tidyMoney).font(.system(size: 13)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
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
            Text(answered + ", " + waiting).font(.system(size: 13)).foregroundStyle(Theme.ivory)
        }
    }

    private func signed(_ v: Double) -> String { abs(v) < 0.5 ? store.short(0) : (v > 0 ? "+" : "−") + store.short(abs(v)) }
}

/// A reward popup: a trophy, an ambition milestone, a finished first step or the day's mission. One at a time, from the queue the
/// store holds after a day; it shows the real reward, arrives with a calm animation (none under Reduce Motion) and a light haptic.
struct CelebrationPopup: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var item: Celebration
    @State private var shown = false
    /// Set once the reward has been claimed right here: what the player got. The card then shows a small celebration of its own.
    @State private var claimedText: String?
    @State private var burst = false
    /// Goal complete (brief 9.3): the card turns green, the check draws itself, the reward fades in.
    @State private var goalShown = false
    @State private var checkDrawn: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().contentShape(Rectangle())
            card
                .padding(.horizontal, 28)
                .scaleEffect(shown || reduceMotion ? 1 : 0.92)
                .opacity(shown ? 1 : 0)
        }
        .onAppear {
            Haptics.tap()
            Motion.animate(Motion.arrive(reduceMotion)) { shown = true }
            if item.kind == "goal" {
                Motion.animate(Motion.quick(reduceMotion)) { goalShown = true }
                Motion.animate(Motion.reveal(reduceMotion)) { checkDrawn = 1 }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var card: some View {
        VStack(spacing: 10) {
            badge
            Text(kindLabel).capsLabel()
            Text(item.title).font(.serifTitle(22)).foregroundStyle(Theme.ivory).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if !item.detail.isEmpty {
                Text(item.detail).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            if !item.reward.isEmpty {
                Text(item.reward).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.gain).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .opacity(item.kind != "goal" || goalShown || reduceMotion ? 1 : 0)
            }
            claimArea
            if !canClaim {
                Button(dismissTitle) { dismiss() }
                    .buttonStyle(ImportantButtonStyle()).padding(.top, 4).accessibilityIdentifier("celebration-dismiss")
            }
        }
        .padding(20)
        .frame(maxWidth: 380)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(Theme.surface))
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(Theme.gain.opacity(item.kind == "goal" && (goalShown || reduceMotion) ? 0.16 : 0)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(Theme.gold.opacity(0.6), lineWidth: 1))
    }

    // MARK: Claiming in place

    /// A finished goal or today's mission carries a reward that is claimed with one tap, here, not by going to Goals.
    private var canClaim: Bool { claimedText == nil && (item.kind == "mission" || (item.kind == "goal" && claimableStep != nil)) }

    /// A first-step reward that is finished and not yet taken under this title. A ladder goal has none (the engine paid its reward when it
    /// finished), so it is closed with "Nice" instead of a claim button that could only say "Already claimed.".
    private var claimableStep: PlayerGoals.FirstStep? {
        (store.engine?.firstStepRewards ?? []).first(where: { $0.title == item.title && $0.done && !$0.claimed })
    }

    /// Claiming is the only way out: a goal or mission is claimed here, a trophy or milestone (already paid) is claimed with one tap.
    private var dismissTitle: String {
        if claimedText != nil { return store.celebrationQueue.count > 1 ? "Next" : "Done" }
        if item.kind == "goal" { return "Nice" }
        return "Claim"
    }

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
            ThumbnailView(kind: .trophy, key: ArtLibrary.trophyKey(id: entry.id, group: entry.group), size: 112, shape: .round, glyph: Glyph.achievements)
                .padding(6)
                .overlay(Circle().strokeBorder(Theme.gold, lineWidth: 3))
                .padding(8)
        } else {
            GoldRingMark(glyph: Glyph.achievements, size: item.kind == "trophy" ? 96 : 64)
        }
    }

    @ViewBuilder private var claimArea: some View {
        if let done = claimedText {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 36)).foregroundStyle(Theme.gold)
                    .scaleEffect(burst || reduceMotion ? 1 : 0.4)
                    .symbolEffect(.bounce, value: burst)
                Text(done).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.gain)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .transition(.scale.combined(with: .opacity))
            .accessibilityElement(children: .combine)
        } else if canClaim {
            Button("Claim") { claim() }
                .buttonStyle(ImportantButtonStyle()).accessibilityIdentifier("celebration-claim")
        }
    }

    private func claim() {
        var text: String?
        if item.kind == "mission" {
            let cur: Currency? = store.engine?.homeCurrency
            if let r = store.act({ $0.claimDailyGoal() }) ?? nil { text = "Daily goal reward: " + (cur?.tidyShort(r) ?? "") + " is yours." }
        } else if let step = claimableStep {
            text = store.act({ $0.claimFirstStep(id: step.id) }) ?? nil
        }
        if let text {
            Haptics.success()
            Motion.animate(Motion.arrive(reduceMotion)) { claimedText = text.tidyText; burst = true }
        } else {
            Haptics.warning()
            Motion.animate(Motion.standard(reduceMotion)) { claimedText = "Already claimed." }
        }
    }

    private var kindLabel: String {
        switch item.kind {
        case "trophy": return "Trophy earned"
        case "milestone": return "Milestone reached"
        case "mission": return "Mission done"
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
