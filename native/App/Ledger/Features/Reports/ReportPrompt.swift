import SwiftUI
import GameCore
import Simulation

/// The sheet that appears on Home when a week, a month or a year closes. It is read and dismissed with one tap before the next day
/// can run: a natural pause, real figures only, one sheet per closing (a year covers its month and week). "Open in Reports" goes to the detail.
struct ReportDigestSheet: View {
    @EnvironmentObject var store: GameStore
    var digest: ReportDigest

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    header
                    figures
                    list("Major changes", digest.changes, tint: Theme.ivory)
                    list("Risks", digest.risks, tint: Theme.caution)
                    decisions
                }
                .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            VStack(spacing: 8) {
                QuietButton(title: "Continue", fullWidth: true) { store.dismissReportSheet() }
                    .accessibilityIdentifier("report-continue")
                Button { Haptics.tap(); store.dismissReportSheet(openReports: true) } label: {
                    Text("Open in Reports ›").font(.system(size: 13)).foregroundStyle(Theme.gold).frame(minHeight: 36).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle()).accessibilityIdentifier("report-open")
            }
            .padding(.horizontal, 18).padding(.bottom, 14)
        }
        .background(Theme.page.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(digest.kind.title + " report").capsLabel()
            Text(digest.title).font(.serifTitle(26)).foregroundStyle(Theme.ivory)
            Text(digest.range).font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
        }
    }

    private var figures: some View {
        let profit: Double = digest.netProfit
        return Card(padding: 12, radius: Theme.Radius.hero) {
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    figure("Revenue", store.short(digest.revenue), Theme.ivory)
                    figure("Profit", signed(profit), Theme.change(profit))
                }
                HStack(alignment: .top, spacing: 12) {
                    figure("Cash", store.short(digest.cashEnd), digest.cashEnd < 0 ? Theme.loss : Theme.ivory)
                    figure("Debt", store.short(digest.debt), digest.debt > 0.5 ? Theme.loss : Theme.ivory)
                }
                HStack(alignment: .top, spacing: 12) {
                    figure("Payroll", store.short(digest.payroll), Theme.ivory)
                    figure("Taxes paid", store.short(digest.taxes), Theme.ivory)
                }
                Rectangle().fill(Theme.divider).frame(height: 1)
                HStack {
                    Text("Net worth").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                    Spacer()
                    Text(store.short(digest.netWorthEnd)).font(.system(size: 13.5, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ivory)
                    Text(signed(digest.netWorthChange)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.change(digest.netWorthChange))
                }
            }
        }
    }

    private func figure(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            Text(value).font(.system(size: 18, weight: .medium).monospacedDigit()).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
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
            IconCircle(glyph: Glyph.achievements, size: 56, tint: Theme.gold)
            Text(kindLabel).capsLabel()
            Text(item.title).font(.serifTitle(22)).foregroundStyle(Theme.ivory).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if !item.detail.isEmpty {
                Text(item.detail).font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            if !item.reward.isEmpty {
                Text(item.reward).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.gain).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            QuietButton(title: store.celebrationQueue.count > 1 ? "Next" : "Nice", fullWidth: true) { dismiss() }
                .padding(.top, 4).accessibilityIdentifier("celebration-dismiss")
        }
        .padding(20)
        .frame(maxWidth: 380)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(Theme.gold.opacity(0.6), lineWidth: 1))
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
