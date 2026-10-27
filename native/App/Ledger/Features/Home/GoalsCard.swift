import SwiftUI
import Simulation

/// The player's own goals: today's goal with its streak, first-step rewards, and the chosen ambition. Cards: today, first steps and ambition.
struct GoalsCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var daily: PlayerGoals.DailyGoal?

    var body: some View {
        let cur = engine.homeCurrency
        VStack(alignment: .leading, spacing: 14) {
            if let g = daily, !g.claimed {
                CardSection(title: "Today", trailing: { legacy }) {
                    row(Glyph.goals, "Today: \(g.title)", g.done ? "Done. Reward \(cur.tidyShort(g.reward))" + (g.streak > 0 ? " · \(g.streak + 1) days in a row" : "") : g.progress,
                        g.done ? "Claim" : nil) {
                        if let r = store.act({ $0.claimDailyGoal() }) ?? nil { Haptics.success(); store.show("Daily goal: \(cur.tidyShort(r)). A new goal comes tomorrow.", tone: "good"); refresh() }
                        else { Haptics.warning(); store.show("That goal cannot be claimed yet.", tone: "warn") }
                    }
                }
            } else if engine.legacyScore > 0 {
                HStack { Spacer(); legacy }
            }
            if let steps = engine.firstStepRewards {
                let hidden = engine.firstStepRewardsHidden
                CardSection(title: "First steps", trailing: { EmptyView() }) {
                    if !hidden, let next = steps.first(where: { !$0.claimed }) {
                        row(Glyph.achievements, next.title, next.done ? "Done. Reward: \(next.reward.lowercased())" : next.how, next.done ? "Claim" : nil) {
                            if let t = store.act({ $0.claimFirstStep(id: next.id) }) ?? nil { Haptics.success(); store.show(t, tone: "good") }
                            else { Haptics.warning(); store.show("That reward cannot be claimed yet.", tone: "warn") }
                        }
                        CardLine()
                    } else if !hidden {
                        Text("Every first-step reward is claimed.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                    }
                    Button(hidden ? "Show the first-step rewards again" : "Hide the first-step rewards") {
                        let ok: Bool = store.act { $0.setFirstStepsHidden(!hidden) } != nil
                        if ok { store.show(hidden ? "First-step rewards are back." : "First-step rewards hidden. Rewards you have not claimed stay available.", tone: "n") }
                        else { store.show("That could not be changed.", tone: "warn") }
                    }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold).buttonStyle(.plain).frame(minHeight: 36)
                }
            }
            CardSection(title: "Ambition", trailing: { EmptyView() }) {
                if let path = engine.currentAmbition, let name = engine.ambitionPaths.first(where: { $0.id == path })?.name {
                    let ms = engine.ambitionMilestones(path: path)
                    let perk = engine.ambitionPerk(path: path)
                    row(Glyph.richList, name, "\(ms.filter { $0.done != nil }.count) of \(ms.count) milestones on this level" + (perk.isEmpty ? "" : "\nPerk: " + perk), nil) {}
                    ForEach(ms, id: \.id) { m in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            GlyphView(glyph: m.done != nil ? Glyph.check : Glyph.ring, size: 14, weight: 1.8, tint: m.done != nil ? Theme.gold : Theme.ivoryDim)
                            Text(m.text).font(.system(size: 12.5)).foregroundStyle(m.done != nil ? Theme.ivoryMuted : Theme.ivory).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 3)
                        .accessibilityElement(children: .combine)
                    }
                } else {
                    Text("Choose what you want to build. Each path has its own milestones and a perk.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                }
                Menu {
                    ForEach(engine.ambitionPaths, id: \.id) { p in
                        Button(p.name + ": " + p.detail) {
                            let ok = store.act { $0.chooseAmbition(path: p.id) } ?? false
                            Haptics.tap(); store.show(ok ? "Your ambition: \(p.name)." : "You cannot switch ambition yet.", tone: ok ? "good" : "warn")
                        }
                    }
                } label: {
                    Text(engine.currentAmbition == nil ? "Choose your ambition" : "Switch ambition")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
                        .padding(.horizontal, 16).frame(minHeight: 40)
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(Theme.gold, lineWidth: 1))
                }
                .padding(.top, 4)
            }
        }
        .onAppear { refresh() }
    }

    @ViewBuilder private var legacy: some View {
        if engine.legacyScore > 0 { Text("Legacy \(Int(engine.legacyScore.rounded()))").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }
    }

    private func refresh() { daily = store.act { $0.dailyGoal() } ?? nil }

    private func row(_ glyph: String, _ title: String, _ sub: String, _ action: String?, _ tap: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            IconCircle(glyph: glyph, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                Text(sub).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let action { Button(action, action: tap).buttonStyle(QuietButtonStyle()) }
        }.padding(.vertical, 6)
    }
}
