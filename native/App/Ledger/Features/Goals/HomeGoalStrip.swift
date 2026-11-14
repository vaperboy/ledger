import SwiftUI
import GameCore
import Simulation

// The only goal on Home: what to do next, or rewards waiting with one Claim button. Tapping the text opens the Goals screen.
struct HomeGoalStrip: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var celebrating: Bool = false

    var body: some View {
        let tick: Int = engine.state.week * 7 + engine.state.day
        let missions: [PlayMissions.Entry] = PlayMissions.Period.allCases.flatMap { (p: PlayMissions.Period) -> [PlayMissions.Entry] in store.missionEntries(p) }
        Group {
            if celebrating {
                claimedStrip
            } else if let next = GoalsFeed.next(engine, missions: missions, claims: store.openGoalClaims) {
                if next.ready { readyStrip(next) } else { strip(next) }
            }
        }
        .onAppear { store.syncMissions() }
        .onChange(of: tick) { _, _ in store.syncMissions() }
    }

    private func claimAll() {
        store.claimAllRewards()
        celebrating = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            celebrating = false
        }
    }

    private func readyStrip(_ n: GoalsFeed.Next) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            Button { Haptics.tap(); store.openGoals() } label: {
                HStack(alignment: .center, spacing: Theme.Space.m) {
                    LedgerGlyph(glyph: Glyph.goals, size: Theme.Icon.medium, tint: Theme.gain)
                    Text("Rewards ready (\(n.count))").textStyle(.body, tint: Theme.gain, weight: .semibold).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Opens your goals")
            Button { claimAll() } label: {
                Text("Claim").textStyle(.body, tint: Theme.accentInk, weight: .semibold)
                    .padding(.horizontal, Theme.Space.l).frame(minHeight: 44)
                    .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Claim \(n.count) rewards")
            .accessibilityIdentifier("home-claim")
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.xs)
        .glassSurface()
        .coachAnchor(.goalCard)
        .accessibilityIdentifier("home-goal")
    }

    private var claimedStrip: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            GlyphView(glyph: Glyph.check, size: Theme.Icon.medium, weight: 2, tint: Theme.gain)
                .goldPulse(celebrating)
            Text("Rewards claimed").textStyle(.body, tint: Theme.gain, weight: .semibold)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
        .frame(minHeight: 44)
        .glassSurface()
        .accessibilityElement(children: .combine)
    }

    private func strip(_ n: GoalsFeed.Next) -> some View {
        Button { Haptics.tap(); store.openGoals() } label: {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                LedgerGlyph(glyph: Glyph.goals, size: Theme.Icon.medium, tint: Theme.inkSoft)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(n.label).textStyle(.label, tint: Theme.inkFaint)
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
