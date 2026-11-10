import SwiftUI
import GameCore
import Simulation

struct SeasonView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case rewards = "Rewards", missions = "Missions", collection = "Collection"
        var id: String { rawValue }
    }

    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @ObservedObject private var model = SeasonModel.shared
    @State private var showPlans = false
    @State private var pending: PendingAction?
    @State private var tab: Tab = .rewards
    @Namespace private var tabLine

    private var pass: SeasonPass { model.pass }
    private var premium: Bool { model.premiumOpen(plus: ent.isPlus, founder: ent.isFounder) }
    private var accent: Color { tint(for: "theme") ?? Theme.accent }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard
                    tabBar
                    content
                        .id(tab)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 10)), removal: .opacity))
                }
                .padding(.horizontal, Theme.Space.margin)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                model.refreshSeason()
                let target: Int = min(SeasonPass.tierCount, max(1, pass.tier))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { withAnimation(.smooth(duration: 0.4)) { proxy.scrollTo("tier\(target)", anchor: .center) } }
            }
        }
        .ledgerBackground()
        .safeAreaInset(edge: .bottom) { if !premium { unlockBar } }
        .confirmAction($pending)
        .centerSheet(isPresented: $showPlans, title: "Plans and gold", size: .tall, category: .detail, tone: .prestige) { ProPlansView() }
    }

    private var summaryCard: some View {
        let left: Int = pass.daysLeft(today: model.today)
        let open: Int = pass.claimableCount(isPlus: premium)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Season \(pass.seasonNumber)").capsLabel(accent)
                Spacer(minLength: 8)
                Text(left == 1 ? "Ends tomorrow" : "\(left) days left").textStyle(.caption)
            }
            Text(pass.progressText).textStyle(.headline).fixedSize(horizontal: false, vertical: true)
            ProgressLine(fraction: pass.tierProgress, tint: accent, height: 6)
            if let ending = pass.endingNote(today: model.today, isPlus: premium) {
                Text(ending).textStyle(.caption, tint: Theme.warn).fixedSize(horizontal: false, vertical: true)
            } else if let missed = pass.missedNote, left > SeasonPass.seasonDays - 7 {
                Text(missed).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            }
            if open > 0 {
                Button { claimAll() } label: {
                    Text(open == 1 ? "Claim 1 reward" : "Claim \(open) rewards")
                        .textStyle(.headline, tint: Theme.accentInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(accent))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(16)
        .liquidGlass(cornerRadius: Theme.Radius.hero)
        .animation(.smooth(duration: 0.3), value: open)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { t in
                Button {
                    Haptics.tap()
                    withAnimation(.smooth(duration: 0.3)) { tab = t }
                } label: {
                    Text(t.rawValue)
                        .textStyle(.body, tint: tab == t ? Theme.accentInk : Theme.inkSoft, weight: .semibold)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if tab == t { Capsule().fill(accent).matchedGeometryEffect(id: "tabPill", in: tabLine) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.inset))
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .rewards: rewardsList
        case .missions: missionsList
        case .collection: collectionList
        }
    }

    private var unlockBar: some View {
        Button { Haptics.tap(); showPlans = true } label: {
            HStack(spacing: 8) {
                LedgerGlyph(glyph: Glyph.lock, size: 16, tint: Theme.accentInk)
                Text("Unlock battle pass").textStyle(.headline, tint: Theme.accentInk)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Capsule().fill(accent))
            .padding(.horizontal, Theme.Space.margin)
            .padding(.vertical, 8)
        }
        .buttonStyle(PressableStyle())
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("unlock-battle-pass")
    }

    private var rewardsList: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Free").textStyle(.label, tint: Theme.inkSoft).frame(maxWidth: .infinity)
                Text("").frame(width: 34)
                Text("Premium").textStyle(.label, tint: Theme.inkSoft).frame(maxWidth: .infinity)
            }
            ForEach(1...SeasonPass.tierCount, id: \.self) { t in row(t).id("tier\(t)") }
        }
    }

    private func row(_ t: Int) -> some View {
        let reached: Bool = t <= pass.tier
        return HStack(alignment: .center, spacing: 8) {
            cell(.free, t)
            Text("\(t)")
                .textStyle(.caption, tint: reached ? Theme.accentInk : Theme.inkFaint, numeric: true, weight: .semibold)
                .frame(width: 34, height: 34)
                .background(Circle().fill(reached ? accent : Theme.inset))
            cell(.premium, t)
        }
    }

    @ViewBuilder private func cell(_ track: SeasonPass.Track, _ t: Int) -> some View {
        if let r = pass.reward(track, tier: t) {
            let claimed: Bool = pass.isClaimed(track, tier: t)
            let ready: Bool = pass.canClaim(track, tier: t, isPlus: premium)
            let locked: Bool = track == .premium && !premium
            Button { tap(track, t) } label: {
                HStack(alignment: .center, spacing: 8) {
                    ItemArt(reward: r, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.title).textStyle(.caption, tint: Theme.ink).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Text(claimed ? "Claimed" : ready ? "Claim" : locked ? "Premium" : "Tier \(t)").textStyle(.label, tint: ready ? accent : Theme.inkFaint)
                    }
                    Spacer(minLength: 0)
                    if claimed { LedgerGlyph(glyph: Glyph.check, size: 12, tint: Theme.gain) }
                    else if locked { LedgerGlyph(glyph: Glyph.lock, size: 12, tint: Theme.inkFaint) }
                }
                .padding(8)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(ready ? accent : Theme.line, lineWidth: ready ? 1.5 : 1))
                .opacity(claimed || ready || t <= pass.tier ? 1 : 0.72)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("\(track == .premium ? "Premium" : "Free") tier \(t): \(r.title). \(claimed ? "Claimed" : ready ? "Ready to claim" : locked ? "Locked, part of the premium track" : "Not reached yet")")
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 1)
        }
    }

    private func tap(_ track: SeasonPass.Track, _ t: Int) {
        if track == .premium && !premium { showPlans = true; return }
        guard pass.canClaim(track, tier: t, isPlus: premium) else { return }
        if case .claimed(let r) = model.claim(track, tier: t, isPlus: premium) { announce([r]) }
    }

    private func claimAll() {
        let got: [SeasonReward] = model.claimAll(isPlus: premium)
        if !got.isEmpty { announce(got) }
    }

    private func announce(_ rewards: [SeasonReward]) {
        Haptics.success()
        let text: String = rewards.count <= 3 ? rewards.map(effect).joined(separator: "\n") : "\(rewards.count) rewards, including \(effect(rewards[0]))"
        store.tell(rewards.count == 1 ? "Reward claimed" : "Rewards claimed", text, tone: "good")
    }

    private func effect(_ r: SeasonReward) -> String {
        switch r.kind {
        case .gold: return "\(r.title) added to your gold wallet in the Store."
        case .box: return "\(r.title) waiting in the Store, free to open."
        case .profileCard, .companyCard: return "\(r.title) added to your cabinet. Wear it in Customise."
        case .artifact: return "\(r.title) added to your cabinet."
        case .xp: return "\(r.title) added to your pass."
        default: return "\(r.title) added to your collection."
        }
    }

    private var missionsList: some View {
        let today: Int = model.today
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                LedgerGlyph(glyph: pass.loginDay == today ? Glyph.check : Glyph.lock, size: 14, tint: pass.loginDay == today ? Theme.gain : Theme.inkFaint)
                Text("Open the game today").textStyle(.body)
                Spacer(minLength: 8)
                Text("+\(PassMissions.loginXP) XP").textStyle(.body, tint: Theme.gain, numeric: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
            ForEach(PassMissions.Period.allCases, id: \.self) { period in
                VStack(alignment: .leading, spacing: 8) {
                    Text(period.label).capsLabel()
                    ForEach(pass.missionRows(period, today: today)) { r in missionRow(r) }
                }
            }
            earnSection
        }
    }

    private func missionRow(_ r: SeasonPass.MissionRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                LedgerGlyph(glyph: r.done ? Glyph.check : Glyph.chevron, size: 12, tint: r.done ? Theme.gain : Theme.inkFaint)
                Text(r.mission.title).textStyle(.body, tint: r.done ? Theme.inkSoft : Theme.ink)
                Spacer(minLength: 8)
                Text("+\(r.mission.xp) XP").textStyle(.caption, tint: Theme.gain, numeric: true)
            }
            ProgressLine(fraction: Double(r.progress) / Double(max(1, r.mission.target)), tint: accent, height: 4)
            Text("\(r.progress) of \(r.mission.target)").textStyle(.caption, numeric: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
        .animation(.smooth(duration: 0.3), value: r.progress)
    }

    private var earnSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Other ways to earn XP").capsLabel()
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
            Text("These add up to at most \(SeasonPass.dailyXPCap) XP a day. The pass fills at the pace of steady play, not in a week.").textStyle(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var collection: [SeasonReward] { SeasonRewards.all.filter { pass.owned.contains($0.id) && $0.kind != .box && $0.kind != .gold && $0.kind != .profileCard && $0.kind != .companyCard && $0.kind != .artifact && $0.kind != .xp } }

    @ViewBuilder private var collectionList: some View {
        if collection.isEmpty {
            Text("Rewards you claim from the pass appear here.").textStyle(.body, tint: Theme.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(collection) { r in
                    let on: Bool = pass.equipped[r.kind.rawValue] == r.id
                    HStack(alignment: .top, spacing: 10) {
                        ItemArt(reward: r, rarity: GoldCosmetics.cosmetic(r.id)?.rarity, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).textStyle(.headline)
                            Text(r.kind.label + ". " + r.detail).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if r.kind.isEquippable {
                            Button(on ? "In use" : "Use") { model.equipAsking(r.id, pending: $pending) }
                                .textStyle(.body, tint: on ? Theme.inkFaint : accent)
                                .disabled(on)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func tint(for kind: String) -> Color? {
        guard let id = pass.equipped[kind], let c = SeasonRewards.item(id)?.colors.first else { return nil }
        return Color(hex: c)
    }
}
