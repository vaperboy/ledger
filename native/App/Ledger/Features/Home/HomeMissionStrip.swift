import SwiftUI
import GameCore
import Simulation

struct HomeLevelBar: View {
    var engine: GameEngine
    @State private var showLadder = false

    var body: some View {
        let info: PlayerLevel.Info = engine.playerLevel
        Button { Haptics.tap(); showLadder = true } label: {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(spacing: Theme.Space.s) {
                    Text("Level \(info.level)").textStyle(.caption, tint: Theme.ink, numeric: true, weight: .semibold)
                    ProgressLine(fraction: info.progress, tint: Theme.gold, height: 3)
                    Text("\(info.xpIntoLevel) / \(info.xpForNext) XP").textStyle(.caption, numeric: true).lineLimit(1).minimumScaleFactor(0.8)
                    LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
                }
                .frame(minHeight: 24)
                HomeNextUnlock(engine: engine)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level \(info.level), \(Int(saturating: (info.progress * 100).rounded())) percent to level \(info.level + 1)")
        .accessibilityHint("Shows every level and what it unlocks")
        .accessibilityIdentifier("home-level")
        .levelLadderPopup(isPresented: $showLadder, engine: engine)
    }
}

struct HomeMissionStrip: View {
    @EnvironmentObject var store: GameStore
    @AppStorage("ledger.home.missionsHiddenWeek") private var hiddenWeek: Int = -1
    @ObservedObject private var streak = StreakModel.shared
    var engine: GameEngine

    var body: some View {
        Group {
            if hiddenWeek != engine.state.week {
                HStack(alignment: .top, spacing: Theme.Space.s) {
                    missionCard
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
        .task {
            await MainActor.run {
                if let reward = streak.openToday() { store.tell("Daily streak", reward.text, tone: "good") }
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(Theme.Space.s + Theme.Space.xxs)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassSurface()
            .contentShape(Rectangle())
    }

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
                    if !streak.line.isEmpty {
                        Text(streak.line).textStyle(.caption, tint: Theme.inkFaint).lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .coachAnchor(.goalCard)
        .accessibilityIdentifier("home-mission-card")
    }
}

struct HomeSeasonPromo: View {
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @Environment(AdCoordinator.self) private var ads
    @ObservedObject private var season = SeasonModel.shared
    @State private var showPlans = false
    @State private var watching = false
    var compact: Bool = false

    private func next(_ track: SeasonPass.Track, after tier: Int) -> SeasonReward? {
        guard tier < SeasonPass.tierCount else { return nil }
        return ((tier + 1)...SeasonPass.tierCount).lazy.compactMap { (t: Int) -> SeasonReward? in SeasonRewards.reward(track, tier: t) }.first
    }

    var body: some View {
        let pass: SeasonPass = season.pass
        let premium: Bool = season.premiumOpen(plus: ent.isPlus)
        let open: Int = pass.claimableCount(isPlus: premium)
        let left: Int = pass.daysLeft(today: season.today)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text("Battle Pass").textStyle(.label, tint: Theme.gold)
                Text("Season \(pass.seasonNumber)").textStyle(.caption)
                Spacer(minLength: Theme.Space.s)
                if open > 0 { StoreTag(text: open == 1 ? "1 reward ready" : "\(open) rewards ready", tint: Theme.gain) }
                else if !premium { StoreTag(text: "Premium locked", tint: Theme.inkFaint) }
                else { Text(left == 1 ? "Ends tomorrow" : "\(left) days left").textStyle(.caption) }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(pass.isComplete ? "All \(SeasonPass.tierCount) tiers reached" : "Tier \(pass.tier) of \(SeasonPass.tierCount)").textStyle(.headline, numeric: true)
                Spacer(minLength: Theme.Space.s)
                if !pass.isComplete { Text("\(pass.xpIntoTier) / \(SeasonPass.xpPerTier) XP").textStyle(.caption, numeric: true) }
            }
            ProgressLine(fraction: pass.tierProgress, tint: Theme.gold, height: 5)
            if !compact {
                preview(pass, premium: premium)
                if ads.canOfferSeasonBonus && open == 0 { adAction }
            }
            buttons(open: open, premium: premium)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StoreSurface(tint: Theme.gold, radius: Theme.Radius.card))
        .centerSheet(isPresented: $showPlans, title: "Ledger plans", size: .tall, category: .detail, tone: .prestige) { ProPlansView() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-season-card")
    }

    @ViewBuilder private func preview(_ pass: SeasonPass, premium: Bool) -> some View {
        let free: SeasonReward? = next(.free, after: pass.tier)
        let paid: SeasonReward? = next(.premium, after: pass.tier)
        if free != nil || paid != nil {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                if let free { rewardLine("Next free reward", free, locked: false) }
                if let paid { rewardLine(premium ? "Next premium reward" : "Premium reward", paid, locked: !premium) }
            }
        }
    }

    private func rewardLine(_ label: String, _ r: SeasonReward, locked: Bool) -> some View {
        HStack(spacing: Theme.Space.s) {
            ItemArt(reward: r, size: 28).opacity(locked ? 0.6 : 1)
            VStack(alignment: .leading, spacing: 0) {
                Text(label + ", tier \(r.tier)").textStyle(.caption, tint: Theme.inkFaint)
                Text(r.title).textStyle(.body, tint: locked ? Theme.inkSoft : Theme.ink).lineLimit(1)
            }
            Spacer(minLength: 0)
            if locked { LedgerGlyph(glyph: Glyph.lock, size: 12, tint: Theme.inkFaint) }
        }
        .accessibilityElement(children: .combine)
    }

    private var adAction: some View {
        Button { watchAd() } label: {
            Text("Watch an ad: +\(SeasonPass.adBonusXP) XP").textStyle(.caption, tint: Theme.accent, weight: .semibold).lineLimit(1)
                .frame(minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(watching)
        .accessibilityIdentifier("home-season-ad")
    }

    private func buttons(open: Int, premium: Bool) -> some View {
        HStack(spacing: Theme.Space.s) {
            if open > 0 {
                Button { claim(premium: premium) } label: {
                    Text(open == 1 ? "Claim 1 reward" : "Claim \(open) rewards").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(size: .compact, fullWidth: true))
                .accessibilityIdentifier("home-season-claim")
                Button { Haptics.tap(); store.openSeason() } label: { Text("See pass").frame(maxWidth: .infinity) }
                    .buttonStyle(SecondaryButtonStyle(size: .compact, fullWidth: true))
                    .accessibilityIdentifier("home-season-see")
            } else {
                Button { Haptics.tap(); store.openSeason() } label: { Text("See pass").frame(maxWidth: .infinity) }
                    .buttonStyle(PrimaryButtonStyle(size: .compact, fullWidth: true))
                    .accessibilityIdentifier("home-season-see")
            }
            if !premium && !compact {
                Button { Haptics.tap(); showPlans = true } label: { Text("Unlock premium track").frame(maxWidth: .infinity) }
                    .buttonStyle(SecondaryButtonStyle(size: .compact, fullWidth: true))
                    .accessibilityIdentifier("home-season-unlock")
            }
        }
    }

    private func claim(premium: Bool) {
        let got: [SeasonReward] = season.claimAll(isPlus: premium)
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
