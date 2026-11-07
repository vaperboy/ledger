import SwiftUI
import GameCore
import Events
import Simulation

/// The career on Home as one round button in the top line: the worn logo badge inside a ring that fills towards the next rank, with an
/// accent dot while today's mission waits to be claimed. It opens Goals, where the rank, the streak and the mission live.
struct HomeRankButton: View {
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CosmeticKeys.badge) private var badgeID: String = Cosmetics.defaultBadgeID
    @AppStorage(CosmeticKeys.theme) private var themeID: String = Cosmetics.defaultThemeID
    var engine: GameEngine

    @State private var daily: PlayerGoals.DailyGoal?
    @State private var shownProgress: Double = 0
    @State private var burst = false

    var body: some View {
        let st: Career.RankStatus = store.memo("careerStatus") { $0.careerStatus } ?? engine.careerStatus
        let accent: Color = Cosmetics.resolvedTheme(themeID, pro: ent.isPro).accent
        let badge: Cosmetics.Badge = Cosmetics.resolvedBadge(badgeID, earned: engine.careerCosmetics, pro: ent.isPro)
        let claimable: Bool = (daily?.done ?? false) && !(daily?.claimed ?? false)
        let tick: Int = engine.state.week * 7 + engine.state.day
        return Button { Haptics.tap(); store.openApp(.goals) } label: {
            ZStack {
                AccentRing(progress: shownProgress, tint: accent, size: 40)
                CosmeticBadgeView(badge: badge, tint: accent, size: 26)
            }
            .overlay(alignment: .topTrailing) {
                if claimable { Circle().fill(Theme.accent).frame(width: 9, height: 9).overlay(Circle().strokeBorder(Theme.page, lineWidth: 2)) }
            }
            .scaleEffect(burst ? 1.18 : 1)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Rank \(st.rank.title)" + (st.next.map { (n: Career.Rank) -> String in ", next rank " + n.title } ?? "") + (claimable ? ". Today's mission is ready to claim" : ""))
        .accessibilityIdentifier("home-rank-ring")
        .onAppear { daily = store.dailyGoal(); fill(to: st.progress) }
        .onChange(of: st.progress) { _, v in fill(to: v) }
        .onChange(of: tick) { _, _ in daily = store.dailyGoal() }
        .onChange(of: st.rank.index) { old, new in rankChanged(from: old, to: new) }
    }

    private func fill(to target: Double) {
        let t: Double = HomeProgress.clamp(target)
        Motion.animate(Motion.reveal(reduceMotion)) { shownProgress = t }
    }

    /// A rank-up: the ring swells once (the celebration popup itself comes from the engine's queue).
    private func rankChanged(from old: Int, to new: Int) {
        guard new > old, !reduceMotion else { return }
        Motion.animate(Motion.moveAnimation) { burst = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            Motion.animate(Motion.moveAnimation) { burst = false }
        }
    }
}
