import SwiftUI
import GameCore
import Simulation

// The only goal on Home: what to do next, or a reward waiting. Tapping opens the Goals screen.
struct HomeGoalStrip: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var daily: PlayerGoals.DailyGoal?

    var body: some View {
        let tick: Int = engine.state.week * 7 + engine.state.day
        Group {
            if let next = GoalsFeed.next(engine, daily: daily, claims: store.claimableGoals) { strip(next) }
        }
        .onAppear { daily = store.dailyGoal() }
        .onChange(of: tick) { _, _ in daily = store.dailyGoal() }
    }

    private func strip(_ n: GoalsFeed.Next) -> some View {
        Button { Haptics.tap(); store.openGoals() } label: {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                LedgerGlyph(glyph: Glyph.goals, size: Theme.Icon.medium, tint: n.ready ? Theme.gain : Theme.inkSoft)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(n.label).textStyle(.label, tint: n.ready ? Theme.gain : Theme.inkFaint)
                    Text(n.title.tidyMoney).textStyle(.body, tint: Theme.ink, weight: .medium).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
            }
            .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
            .frame(minHeight: 44)
            .glassSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens your goals")
        .coachAnchor(.goalCard)
        .accessibilityIdentifier("home-goal")
    }
}
