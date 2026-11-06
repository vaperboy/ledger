import SwiftUI
import GameCore
import Events
import Simulation

/// The career strip under the net worth on Home: the logo badge inside a ring that fills towards the next rank, the rank title with
/// its percentage (counting up), the next short goal, the play streak and today's mission. Tap the ring or the text for Goals; the
/// small chart button opens Insights (Pro). Unboxed, near the bottom of Home. A missed day never shows a loss: the streak starts again.
struct HomeRankStrip: View {
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CosmeticKeys.badge) private var badgeID: String = Cosmetics.defaultBadgeID
    @AppStorage(CosmeticKeys.theme) private var themeID: String = Cosmetics.defaultThemeID
    var engine: GameEngine
    var onInsights: () -> Void

    @State private var daily: PlayerGoals.DailyGoal?
    @State private var shownProgress: Double = 0
    @State private var lastRank: Int = -1
    @State private var burst = false
    @State private var claimGlow = false

    var body: some View {
        let st: Career.RankStatus = engine.careerStatus
        let goals: [Career.Goal] = engine.careerNextGoals
        let accent: Color = Cosmetics.resolvedTheme(themeID, pro: ent.isPro).accent
        let badge: Cosmetics.Badge = Cosmetics.resolvedBadge(badgeID, earned: engine.careerCosmetics, pro: ent.isPro)
        let rankIndex: Int = st.rank.index
        let tick: Int = engine.state.week * 7 + engine.state.day
        return HStack(spacing: Theme.Space.m) {
            ringButton(st, accent: accent, badge: badge)
            textBlock(st, goals: goals, accent: accent)
            Spacer(minLength: Theme.Space.xs)
            missionColumn(accent: accent)
            insightsButton(accent: accent)
        }
        .onAppear {
            refreshDaily()
            if lastRank < 0 { lastRank = rankIndex }
            fill(to: st.progress)
        }
        .onChange(of: st.progress) { _, v in fill(to: v) }
        .onChange(of: tick) { _, _ in refreshDaily() }
        .onChange(of: rankIndex) { old, new in rankChanged(from: old, to: new) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-rank-strip")
    }

    // MARK: Pieces

    private func ringButton(_ st: Career.RankStatus, accent: Color, badge: Cosmetics.Badge) -> some View {
        Button { Haptics.tap(); store.openApp(.goals) } label: {
            ZStack {
                AccentRing(progress: shownProgress, tint: accent, size: 44)
                CosmeticBadgeView(badge: badge, tint: accent, size: 28)
            }
            .scaleEffect(burst ? 1.22 : 1)
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Rank \(st.rank.title)")
        .accessibilityIdentifier("home-rank-ring")
    }

    private func textBlock(_ st: Career.RankStatus, goals: [Career.Goal], accent: Color) -> some View {
        let goalLine: String = goals.first.map { (g: Career.Goal) -> String in "Next: " + g.title } ?? "Keep building"
        return Button { Haptics.tap(); store.openApp(.goals) } label: {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                HStack(spacing: Theme.Space.s) {
                    Text(st.rank.title).textStyle(.headline).lineLimit(1)
                    if st.next != nil {
                        CountUpPercent(value: shownProgress * 100).textStyle(.caption, tint: accent, weight: .medium)
                    }
                }
                Text(goalLine).textStyle(.caption).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(st.rank.title + (st.next.map { (n: Career.Rank) -> String in ", next rank " + n.title } ?? ""))
        .accessibilityIdentifier("home-rank-text")
    }

    /// Streak flame with the count, and today's mission below it: "Claim" (pulsing) when it is ready, a tick once claimed.
    private func missionColumn(accent: Color) -> some View {
        let streak: Int = PlayStreak.current(engine.state, today: GameStore.calendarDay())
        let claimable: Bool = (daily?.done ?? false) && !(daily?.claimed ?? false)
        let claimed: Bool = daily?.claimed ?? false
        let line: String = claimable ? "Claim" : claimed ? "Done today" : daily != nil ? "Mission" : ""
        let lineColor: Color = claimable ? accent : claimed ? Theme.gain : Theme.inkFaint
        return Button {
            if claimable { claim() } else { Haptics.tap(); store.openApp(.goals) }
        } label: {
            VStack(spacing: Theme.Space.xxs) {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: "flame.fill").font(.caption).foregroundStyle(streak > 0 ? accent : Theme.inkFaint)
                    Text(streak > 0 ? "\(streak)" : "0").textStyle(.body, tint: streak > 0 ? Theme.ink : Theme.inkFaint, numeric: true, weight: .semibold)
                }
                if !line.isEmpty {
                    Text(line).textStyle(.caption, tint: lineColor, weight: claimable ? .semibold : nil).lineLimit(1)
                        .opacity(claimable && claimGlow ? 0.55 : 1)
                }
            }
            .frame(minWidth: 52, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onChange(of: claimable) { _, on in pulse(on) }
        .onAppear { pulse(claimable) }
        .accessibilityLabel(streak > 0 ? "\(streak) day streak. " + line : "Start a streak today. " + line)
        .accessibilityIdentifier("home-mission")
    }

    private func insightsButton(accent: Color) -> some View {
        Button { Haptics.tap(); onInsights() } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "chart.line.uptrend.xyaxis").font(.body.weight(.medium)).foregroundStyle(accent)
                    .frame(width: Theme.Icon.large, height: Theme.Icon.large)
                if !ent.isPro {
                    Image(systemName: "lock.fill").font(.caption2.weight(.bold)).foregroundStyle(Theme.accent).offset(x: Theme.Space.xs, y: -Theme.Space.xxs)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(ent.isPro ? "Insights" : "Insights, needs Ledger Pro")
        .accessibilityIdentifier("home-insights")
    }

    // MARK: Behaviour

    private func refreshDaily() {
        daily = store.act { (e: inout GameEngine) in e.dailyGoal() } ?? nil
    }

    private func claim() {
        if let r = store.act({ (e: inout GameEngine) in e.claimDailyGoal() }) ?? nil {
            Haptics.success()
            store.show("Daily goal: \(store.short(r)). A new goal comes tomorrow.", tone: "good")
        } else {
            Haptics.warning()
            store.show("That goal cannot be claimed yet.", tone: "warn")
        }
        refreshDaily()
    }

    private func fill(to target: Double) {
        let t: Double = HomeProgress.clamp(target)
        Motion.animate(Motion.reveal(reduceMotion)) { shownProgress = t }
    }

    private func pulse(_ on: Bool) {
        guard on, !reduceMotion else { claimGlow = false; return }
        Motion.animate(Motion.pulseAnimation) { claimGlow = true }
    }

    /// A rank-up: the ring and badge swell once with a glow (the celebration popup itself comes from the engine's queue).
    private func rankChanged(from old: Int, to new: Int) {
        defer { lastRank = new }
        guard new > old, !reduceMotion else { return }
        Motion.animate(Motion.moveAnimation) { burst = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            Motion.animate(Motion.moveAnimation) { burst = false }
        }
    }
}
