import SwiftUI
import Simulation

/// The player's own goals: today's goal with its streak, first-step rewards, and the chosen ambition. Flat rows, no boxes.
struct GoalsCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var daily: PlayerGoals.DailyGoal?

    var body: some View {
        let cur = engine.homeCurrency
        LedgerSection(title: "Goals", trailing: { if engine.legacyScore > 0 { Text("Legacy \(engine.legacyScore)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) } }) {
            VStack(alignment: .leading, spacing: 0) {
                if let g = daily, !g.claimed {
                    row("Today: \(g.title)", g.done ? "Done. Reward \(cur.short(g.reward))" + (g.streak > 0 ? " · \(g.streak + 1) days in a row" : "") : g.progress,
                        g.done ? "Claim" : nil) {
                        if let r = store.act({ $0.claimDailyGoal() }) ?? nil { Haptics.success(); store.show("Daily goal: \(cur.short(r)). A new goal comes tomorrow.", tone: "good"); refresh() }
                    }
                }
                if let steps = engine.firstStepRewards, !engine.firstStepRewardsHidden, let next = steps.first(where: { !$0.claimed }) {
                    Hairline()
                    row(next.title, next.done ? "Done. Reward: \(next.reward.lowercased())" : next.how, next.done ? "Claim" : nil) {
                        if let t = store.act({ $0.claimFirstStep(id: next.id) }) ?? nil { Haptics.success(); store.show(t, tone: "good") }
                    }
                }
                Hairline()
                if let path = engine.ambitionPath, let name = PlayerGoals.ambitionPaths.first(where: { $0.id == path })?.name {
                    let ms = engine.ambitionMilestones
                    row("Ambition: \(name)", "\(ms.filter { $0.done }.count) of \(ms.count) milestones on this level", nil) {}
                    ForEach(ms, id: \.id) { m in
                        Text((m.done ? "\u{2713} " : "\u{00B7} ") + m.text).font(.system(size: 12)).foregroundStyle(m.done ? Theme.ivoryMuted : Theme.ivory).padding(.leading, 12).padding(.vertical, 2)
                    }
                } else {
                    Text("Choose what you want to build. Each path has its own milestones and a perk.").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).padding(.vertical, 8)
                }
                Menu(engine.ambitionPath == nil ? "Choose your ambition" : "Switch ambition") {
                    ForEach(PlayerGoals.ambitionPaths, id: \.id) { p in
                        Button(p.name + ": " + p.summary) { store.act { $0.chooseAmbition(path: p.id) }; Haptics.tap(); store.show("Your ambition: \(p.name).", tone: "good") }
                    }
                }
                .font(.system(size: 13)).foregroundStyle(Theme.gold).padding(.top, 6)
            }
        }
        .onAppear { refresh() }
    }

    private func refresh() { daily = store.act { $0.dailyGoal() } ?? nil }

    private func row(_ title: String, _ sub: String, _ action: String?, _ tap: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                Text(sub).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let action { Button(action, action: tap).buttonStyle(QuietButtonStyle()) }
        }.padding(.vertical, 8)
    }
}
