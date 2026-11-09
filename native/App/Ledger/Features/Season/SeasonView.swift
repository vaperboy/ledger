import SwiftUI
import GameCore
import Simulation

/// The Season Pass screen: this season's progress in words and a bar, a horizontal track of 30 tiers with the free row and the premium
/// row (included in Ledger Plus), a claim action, how XP is earned and the player's collection. Nothing here pulses or animates.
struct SeasonView: View {
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @ObservedObject private var model = SeasonModel.shared

    private var pass: SeasonPass { model.pass }
    private var accent: Color { tint(for: "theme") ?? Theme.accent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard
                trackSection
                if !ent.isPlus { plusLine }
                earnSection
                collectionSection
            }
            .padding(.horizontal, Theme.Space.margin)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .ledgerBackground()
        .onAppear { model.refreshSeason() }
    }

    // MARK: Summary

    private var summaryCard: some View {
        let left: Int = pass.daysLeft(today: model.today)
        let open: Int = pass.claimableCount(isPlus: ent.isPlus)
        let todayXP: Int = pass.xpLeftToday(today: model.today)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Season \(pass.seasonNumber)").capsLabel(accent)
            Text(pass.progressText).textStyle(.headline).fixedSize(horizontal: false, vertical: true)
            ProgressView(value: pass.tierProgress).tint(accent)
            Text(left == 1 ? "Ends tomorrow" : "\(left) days left in this season").textStyle(.caption)
            Text(todayXP == 0 ? "You have earned the most XP a day gives. More tomorrow." : "Up to \(todayXP) more XP can be earned today.").textStyle(.caption)
            if let ending = pass.endingNote(today: model.today, isPlus: ent.isPlus) {
                Text(ending).textStyle(.caption, tint: Theme.warn).fixedSize(horizontal: false, vertical: true)
            } else if let missed = pass.missedNote, left > SeasonPass.seasonDays - 7 {
                Text(missed).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            }
            Button { claimAll() } label: {
                Text(open == 0 ? "Nothing to claim yet" : open == 1 ? "Claim 1 reward" : "Claim \(open) rewards")
                    .textStyle(.headline, tint: open == 0 ? Theme.inkSoft : Theme.accentInk)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(open == 0 ? Theme.inset : accent))
            }
            .buttonStyle(.plain)
            .disabled(open == 0)
        }
        .padding(16)
        .liquidGlass(cornerRadius: Theme.Radius.hero)
    }

    // MARK: Track

    private var trackSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Rewards").capsLabel()
                Spacer(minLength: 8)
                Text("Free and Ledger Plus").textStyle(.caption)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("").frame(height: 18)
                        rowLabel("Free")
                        rowLabel("Plus")
                    }
                    .frame(width: 44)
                    ForEach(1...SeasonPass.tierCount, id: \.self) { t in column(t) }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func rowLabel(_ s: String) -> some View {
        Text(s).textStyle(.caption).frame(width: 44, height: 92, alignment: .leading)
    }

    private func column(_ t: Int) -> some View {
        let reached: Bool = t <= pass.tier
        return VStack(spacing: 8) {
            Text("\(t)").textStyle(.caption, tint: reached ? accent : Theme.inkFaint).frame(height: 18)
            cell(.free, t)
            cell(.premium, t)
        }
        .frame(width: 96)
    }

    @ViewBuilder private func cell(_ track: SeasonPass.Track, _ t: Int) -> some View {
        if let r = SeasonRewards.reward(track, tier: t) {
            let claimed: Bool = pass.isClaimed(track, tier: t)
            let ready: Bool = pass.canClaim(track, tier: t, isPlus: ent.isPlus)
            let locked: Bool = track == .premium && !ent.isPlus
            Button { tap(track, t) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        ItemArt(reward: r, size: 24)
                        Text(r.kind.label).textStyle(.label, tint: Theme.inkSoft).lineLimit(1).minimumScaleFactor(0.6)
                        Spacer(minLength: 0)
                        if claimed { LedgerGlyph(glyph: Glyph.check, size: 12, tint: Theme.gain) }
                        else if locked { LedgerGlyph(glyph: Glyph.lock, size: 12, tint: Theme.inkFaint) }
                    }
                    Text(r.title).textStyle(.caption, tint: Theme.ink).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Text(claimed ? "Claimed" : ready ? "Claim" : locked ? "Plus" : "Tier \(t)").textStyle(.caption, tint: ready ? accent : Theme.inkFaint)
                }
                .padding(8)
                .frame(width: 96, height: 92, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(ready ? accent : Theme.line, lineWidth: ready ? 1.5 : 1))
                .opacity(claimed || ready || t <= pass.tier ? 1 : 0.72)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(track == .premium ? "Plus" : "Free") tier \(t): \(r.title). \(claimed ? "Claimed" : ready ? "Ready to claim" : locked ? "Included in Ledger Plus" : "Not reached yet")")
        } else {
            Color.clear.frame(width: 96, height: 92)
        }
    }

    private func tap(_ track: SeasonPass.Track, _ t: Int) {
        if track == .premium && !ent.isPlus { openPaywall(); return }
        guard pass.canClaim(track, tier: t, isPlus: ent.isPlus) else { return }
        if case .claimed(let r) = model.claim(track, tier: t, isPlus: ent.isPlus) { announce([r]) }
    }

    private func claimAll() {
        let got: [SeasonReward] = model.claimAll(isPlus: ent.isPlus)
        if !got.isEmpty { announce(got) }
    }

    /// The standard small success popup, naming what was claimed.
    private func announce(_ rewards: [SeasonReward]) {
        Haptics.success()
        let text: String = rewards.count <= 3 ? rewards.map(effect).joined(separator: "\n") : "\(rewards.count) rewards, including \(effect(rewards[0]))"
        store.tell(rewards.count == 1 ? "Reward claimed" : "Rewards claimed", text, tone: "good")
    }

    /// What claiming one reward did, in words: gold goes to the wallet, a box waits in the Store, the rest joins the collection below.
    private func effect(_ r: SeasonReward) -> String {
        switch r.kind {
        case .gold: return "\(r.title) added to your gold wallet in the Store."
        case .box: return "\(r.title) waiting in the Store, free to open."
        default: return "\(r.title) added to your collection below."
        }
    }

    /// Premium needs Ledger Plus itself (Pro alone is not enough), so the paywall is asked for directly.
    private func openPaywall() {
        ent.paywall = PaywallRequest(title: "Season Pass: Plus rewards", feature: nil)
    }

    private var plusLine: some View {
        Button { openPaywall() } label: {
            HStack(spacing: 10) {
                LedgerGlyph(glyph: Glyph.lock, size: 16, tint: accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Included in Ledger Plus").textStyle(.headline)
                    Text("The Plus row adds themes, plates, backdrops and an extra save slot. Nothing here changes how the game plays.").textStyle(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .liquidGlass(cornerRadius: Theme.Radius.card)
        }
        .buttonStyle(.plain)
    }

    // MARK: How XP is earned

    private var earnSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How XP is earned").capsLabel()
            VStack(spacing: 0) {
                ForEach(SeasonPass.Source.allCases, id: \.self) { s in
                    HStack {
                        Text(s.title).textStyle(.body)
                        Spacer(minLength: 8)
                        Text("+\(s.xp) XP").textStyle(.body, tint: Theme.gain)
                    }
                    .padding(.vertical, 9)
                    .overlay(alignment: .bottom) { Hairline() }
                }
            }
            Text("A day gives at most \(SeasonPass.dailyXPCap) XP, so the pass fills at the pace of real play. Rewards are fixed.").textStyle(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Collection

    private var collection: [SeasonReward] { SeasonRewards.all.filter { pass.owned.contains($0.id) && $0.kind != .box && $0.kind != .gold } }

    @ViewBuilder private var collectionSection: some View {
        if !collection.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your collection").capsLabel()
                ForEach(collection) { r in
                    let on: Bool = pass.equipped[r.kind.rawValue] == r.id
                    HStack(alignment: .top, spacing: 10) {
                        swatch(r)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).textStyle(.headline)
                            Text(r.kind.label + ". " + r.detail).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if r.kind.isEquippable {
                            Button(on ? "In use" : "Use") { model.equip(r.id) }
                                .textStyle(.body, tint: on ? Theme.inkFaint : accent)
                                .disabled(on)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    /// The reward's drawn art (see `ItemArt`).
    private func swatch(_ r: SeasonReward) -> some View {
        ItemArt(reward: r, rarity: GoldCosmetics.cosmetic(r.id)?.rarity, size: 36)
    }

    /// The tint of the equipped reward of a kind (a theme's first colour), nil when none is chosen.
    private func tint(for kind: String) -> Color? {
        guard let id = pass.equipped[kind], let c = SeasonRewards.all.first(where: { $0.id == id })?.colors.first else { return nil }
        return Color(hex: c)
    }
}
