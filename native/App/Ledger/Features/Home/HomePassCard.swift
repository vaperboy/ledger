import SwiftUI
import Simulation

/// The Battle Pass on Home: current tier, the next reward, progress, and a way to get the premium track.
struct HomePassCard: View {
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @ObservedObject private var model = SeasonModel.shared

    var body: some View {
        let pass: SeasonPass = model.pass
        let open: Bool = model.premiumOpen(plus: ent.isPlus, founder: ent.isFounder)
        let ready: Int = pass.claimableCount(isPlus: open)
        let next: SeasonReward? = nextReward(pass, premiumOpen: open)
        let progress: Double = pass.isComplete ? 1 : (Double(pass.tier) + pass.tierProgress) / Double(SeasonPass.tierCount)
        let heading: String = ready > 0 ? (ready == 1 ? "1 reward ready" : "\(ready) rewards ready") : "Battle Pass \u{00B7} tier \(pass.tier) of \(SeasonPass.tierCount)"
        let line: String = next.map { (r: SeasonReward) -> String in "Next: " + r.title } ?? "Every reward is within reach"
        HStack(alignment: .center, spacing: Theme.Space.s) {
            Button { Haptics.tap(); store.openGoals() } label: {
                HStack(alignment: .center, spacing: Theme.Space.m) {
                    if let next { ItemArt(reward: next, size: 44) } else { LedgerGlyph(glyph: Glyph.achievements, size: Theme.Icon.large, tint: Theme.gold) }
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(heading).textStyle(.label, tint: ready > 0 ? Theme.gain : Theme.inkFaint).lineLimit(1)
                        Text(line).textStyle(.body, tint: Theme.ink, weight: .medium).lineLimit(1)
                        HomePassBar(progress: progress).frame(height: 5)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if open { LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Opens the Battle Pass")
            .accessibilityIdentifier("home-pass")
            if !open {
                Button { Haptics.tap(); store.openApp(.store) } label: {
                    Text("Get the pass").textStyle(.caption, tint: Theme.accentInk, weight: .semibold).lineLimit(1)
                        .padding(.horizontal, Theme.Space.m).frame(minHeight: 36)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("home-pass-get")
            }
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
        .frame(minHeight: 60)
        .glassSurface()
    }

    /// The next reward to reach: premium rewards while the premium track is closed (what the pass adds), otherwise whichever comes first.
    private func nextReward(_ pass: SeasonPass, premiumOpen: Bool) -> SeasonReward? {
        guard !pass.isComplete else { return nil }
        for t in (pass.tier + 1)...SeasonPass.tierCount {
            if !premiumOpen { if let r = pass.reward(.premium, tier: t) { return r } }
            else if let r = pass.reward(.free, tier: t) ?? pass.reward(.premium, tier: t) { return r }
        }
        return nil
    }
}

private struct HomePassBar: View {
    var progress: Double

    var body: some View {
        GeometryReader { (g: GeometryProxy) in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.inset)
                Capsule().fill(Theme.gold).frame(width: max(5, g.size.width * min(1, max(0, progress))))
            }
        }
        .accessibilityHidden(true)
    }
}
