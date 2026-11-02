import SwiftUI
import GameCore
import Countries
import Simulation

/// The popup that appears on the main screen when a week, a month or a year closes. It is read and dismissed with one tap before the next day
/// can run: a natural pause, real figures only, one sheet per closing (a year covers its month and week). "Open in Reports" goes to the detail.
struct ReportDigestSheet: View {
    @EnvironmentObject var store: GameStore
    var digest: ReportDigest

    var body: some View {
        GamePopup(title: digest.title, showsClose: false, onClose: { store.dismissReportSheet() }) {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .vertical) {
                    sections
                    ContainedScroll { sections }
                }
                .frame(maxHeight: 420)
                VStack(spacing: 4) {
                    QuietButton(title: "Continue", fullWidth: true) { store.dismissReportSheet() }
                        .accessibilityIdentifier("report-continue")
                    Button { Haptics.tap(); store.dismissReportSheet(openReports: true) } label: {
                        Text("Open in Reports ›").font(.system(size: 13)).foregroundStyle(Theme.gold).frame(minHeight: 36).contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle()).accessibilityIdentifier("report-open")
                }
            }
        }
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

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { dismiss() }
            card
                .padding(.horizontal, 28)
                .scaleEffect(shown || reduceMotion ? 1 : 0.92)
                .opacity(shown ? 1 : 0)
        }
        .onAppear {
            Haptics.tap()
            withAnimation(Motion.arrive(reduceMotion)) { shown = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var card: some View {
        VStack(spacing: 10) {
            GoldRingMark(glyph: Glyph.achievements, size: 64)
            Text(kindLabel).capsLabel()
            Text(item.title).font(.serifTitle(22)).foregroundStyle(Theme.ivory).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if !item.detail.isEmpty {
                Text(item.detail).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            if !item.reward.isEmpty {
                Text(item.reward).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.gain).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            claimArea
            QuietButton(title: dismissTitle, fullWidth: true) { dismiss() }
                .padding(.top, 4).accessibilityIdentifier("celebration-dismiss")
        }
        .padding(20)
        .frame(maxWidth: 380)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(Theme.gold.opacity(0.6), lineWidth: 1))
    }

    // MARK: Claiming in place

    /// A finished goal or today's mission carries a reward that is claimed with one tap, here, not by going to Goals.
    private var canClaim: Bool { claimedText == nil && (item.kind == "mission" || item.kind == "goal") }

    private var dismissTitle: String {
        if canClaim { return "Later" }
        return store.celebrationQueue.count > 1 ? "Next" : "Nice"
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
            Button("Claim reward") { claim() }
                .buttonStyle(ImportantButtonStyle()).accessibilityIdentifier("celebration-claim")
        }
    }

    private func claim() {
        var text: String?
        if item.kind == "mission" {
            let cur: Currency? = store.engine?.homeCurrency
            if let r = store.act({ $0.claimDailyGoal() }) ?? nil { text = "Daily goal reward: " + (cur?.tidyShort(r) ?? "") + " is yours." }
        } else if let step = (store.engine?.firstStepRewards ?? []).first(where: { $0.title == item.title && $0.done && !$0.claimed }) {
            text = store.act({ $0.claimFirstStep(id: step.id) }) ?? nil
        }
        if let text {
            Haptics.success()
            withAnimation(Motion.arrive(reduceMotion)) { claimedText = text.tidyText; burst = true }
        } else {
            Haptics.warning()
            withAnimation(Motion.standard(reduceMotion)) { claimedText = "Already claimed." }
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
