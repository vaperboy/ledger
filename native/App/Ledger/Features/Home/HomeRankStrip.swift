import SwiftUI
import GameCore
import Events
import Simulation

/// The career strip under the net worth on Home: the logo badge inside a ring that fills towards the next rank, the rank title with
/// its percentage (counting up), the next short goal, the play streak and today's mission. Tap the ring or the text for Goals; the
/// small chart button opens Insights (Pro). A missed day never shows a loss: the streak simply starts again.
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
        return Card(padding: 0, radius: Theme.Radius.card) {
            HStack(spacing: 10) {
                ringButton(st, accent: accent, badge: badge)
                textBlock(st, goals: goals, accent: accent)
                Spacer(minLength: 4)
                missionColumn(accent: accent)
                insightsButton(accent: accent)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
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
            .shadow(color: accent.opacity(burst ? 0.7 : 0), radius: burst ? 10 : 0)
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
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(st.rank.title).font(.serifTitle(16)).foregroundStyle(Theme.ivory).lineLimit(1)
                    if st.next != nil {
                        CountUpPercent(value: shownProgress * 100).font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
                    }
                }
                Text(goalLine).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
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
        let lineColor: Color = claimable ? accent : claimed ? Theme.gain : Theme.ivoryFaint
        return Button {
            if claimable { claim() } else { Haptics.tap(); store.openApp(.goals) }
        } label: {
            VStack(spacing: 1) {
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill").font(.system(size: 12)).foregroundStyle(streak > 0 ? accent : Theme.ivoryDim)
                    Text(streak > 0 ? "\(streak)" : "0").font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(streak > 0 ? Theme.ivory : Theme.ivoryFaint)
                }
                if !line.isEmpty {
                    Text(line).font(.system(size: 10.5, weight: claimable ? .semibold : .regular)).foregroundStyle(lineColor)
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
                Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 15, weight: .medium)).foregroundStyle(accent)
                    .frame(width: 34, height: 34)
                    .background(Circle().strokeBorder(Theme.borderStrong, lineWidth: 1))
                if !ent.isPro {
                    Image(systemName: "lock.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.gold).offset(x: 3, y: -2)
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
