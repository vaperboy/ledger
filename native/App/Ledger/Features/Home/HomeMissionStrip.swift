import SwiftUI
import GameCore
import Simulation

/// Level progress and the two small cards under the progress strip: the current mission with any reward waiting to be claimed (opens the
/// goals popup), and the Season Pass (claim what is ready, or watch an ad for XP). Calm by design: no flashing, no pulse, never blocks,
/// and the cards can be put away until next week with the cross.
struct HomeLevelBar: View {
    var engine: GameEngine

    var body: some View {
        let info: PlayerLevel.Info = engine.playerLevel
        HStack(spacing: Theme.Space.s) {
            Text("Level \(info.level)").textStyle(.caption, tint: Theme.ink, numeric: true, weight: .semibold)
            ProgressLine(fraction: info.progress, tint: Theme.gold, height: 3)
            Text("\(info.xpIntoLevel) / \(info.xpForNext) XP").textStyle(.caption, numeric: true).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(minHeight: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level \(info.level), \(Int(saturating: (info.progress * 100).rounded())) percent to level \(info.level + 1)")
        .accessibilityIdentifier("home-level")
    }
}

struct HomeMissionStrip: View {
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @Environment(AdCoordinator.self) private var ads
    @ObservedObject private var season = SeasonModel.shared
    /// The game week in which the player put the cards away; they return the week after.
    @AppStorage("ledger.home.missionsHiddenWeek") private var hiddenWeek: Int = -1
    var engine: GameEngine

    var body: some View {
        if hiddenWeek != engine.state.week {
            HStack(alignment: .top, spacing: Theme.Space.s) {
                missionCard
                seasonCard
                Button { Haptics.tap(); hiddenWeek = engine.state.week } label: {
                    Image(systemName: "xmark").font(.caption2.weight(.semibold)).foregroundStyle(Theme.inkFaint)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Hide until next week")
                .accessibilityIdentifier("home-missions-hide")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(Theme.Space.s + Theme.Space.xxs)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassSurface()
            .contentShape(Rectangle())
    }

    // MARK: Mission

    private var missionCard: some View {
        let waiting: Int = store.claimableGoals.count
        let ladder: PlayerGoals.LadderGoal? = PlayerGoals.currentLadderGoal(engine.state)
        let title: String = ladder?.title ?? (waiting > 0 ? "Goals finished" : "Keep building")
        return Button {
            Haptics.tap()
            if waiting == 0, let link = ladder?.link, !link.isEmpty, store.openLadderLink(link) { return }
            store.openGoals()
        } label: {
            card {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text("Mission").textStyle(.label, tint: Theme.inkFaint)
                    Text(title.tidyMoney).textStyle(.body, tint: Theme.ink).lineLimit(2).multilineTextAlignment(.leading)
                    if waiting > 0 {
                        Text(waiting == 1 ? "1 reward to claim" : "\(waiting) rewards to claim").textStyle(.caption, tint: Theme.accent, weight: .semibold)
                    } else if let body = ladder?.body, !body.isEmpty {
                        Text(body).textStyle(.caption).lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home-mission-card")
    }

    // MARK: Season Pass

    @State private var watching = false

    private var seasonCard: some View {
        let pass: SeasonPass = season.pass
        let open: Int = pass.claimableCount(isPlus: ent.isPlus)
        return card {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("Season Pass").textStyle(.label, tint: Theme.inkFaint)
                Text(pass.isComplete ? "All tiers reached" : "Tier \(pass.tier) of \(SeasonPass.tierCount)").textStyle(.body, tint: Theme.ink, numeric: true).lineLimit(1)
                ProgressLine(fraction: pass.tierProgress, height: 3)
                if !pass.isComplete, let next = SeasonRewards.reward(.free, tier: pass.tier + 1) {
                    Text("Next: \(next.title)").textStyle(.caption).lineLimit(1)
                }
                if open > 0 {
                    action(open == 1 ? "Claim 1 reward" : "Claim \(open) rewards", id: "home-season-claim") { claimSeason() }
                } else if ads.canOfferSeasonBonus {
                    action("Watch an ad: +\(SeasonPass.adBonusXP) XP", id: "home-season-ad") { watchAd() }
                }
            }
        }
        .onTapGesture { Haptics.tap(); store.openSeason() }
        .accessibilityIdentifier("home-season-card")
    }

    private func action(_ text: String, id: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(text).textStyle(.caption, tint: Theme.accent, weight: .semibold).lineLimit(1).minimumScaleFactor(0.8)
                .frame(minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(watching)
        .accessibilityIdentifier(id)
    }

    private func claimSeason() {
        let got: [SeasonReward] = season.claimAll(isPlus: ent.isPlus)
        guard !got.isEmpty else { return }
        Haptics.success()
        let text: String = got.count <= 3 ? got.map(\.title).joined(separator: ", ") : "\(got.count) rewards, including \(got[0].title)"
        store.tell(got.count == 1 ? "Reward claimed" : "Rewards claimed", text, tone: "good")
    }

    private func watchAd() {
        guard !watching else { return }
        watching = true
        Task { @MainActor in
            let xp: Int = await ads.watchForSeasonBonus()
            watching = false
            if xp > 0 { Haptics.success(); store.tell("Season XP added", "+\(xp) XP for the pass.", tone: "good") }
        }
    }
}
