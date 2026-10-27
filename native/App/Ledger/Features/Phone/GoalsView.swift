import SwiftUI
import GameCore
import Events
import Simulation

/// Goals app: a checklist with a progress ring for every goal (a tick when it is done), the reward under each line, and the trophies
/// as a shelf row at the end. Today's goal, the first-step rewards and the chosen ambition keep their engine calls; every claim
/// reports the engine's own result.
struct GoalsView: View {
    @EnvironmentObject var store: GameStore
    @State private var daily: PlayerGoals.DailyGoal?

    var body: some View {
        if let e = store.engine {
            PhonePageScroll(spacing: 14) {
                summaryCard(e)
                todayCard(e)
                stepsCard(e)
                ambitionCard(e)
                TrophyShelfRow(engine: e)
            }
            .onAppear { refresh() }
        } else {
            Text("No game is open.").font(.bodyText).foregroundStyle(Theme.ivoryMuted).padding(Theme.Space.margin)
        }
    }

    private func refresh() { daily = store.act { $0.dailyGoal() } ?? nil }

    // MARK: Summary

    private func summaryCard(_ e: GameEngine) -> some View {
        let steps: [PlayerGoals.FirstStep] = e.firstStepRewards ?? []
        let done: Int = steps.filter { $0.done || $0.claimed }.count
        let total: Int = max(steps.count, 1)
        let fraction: Double = Double(done) / Double(total)
        let line: String = steps.isEmpty ? "Your goals for today and your ambition." : "\(done) of \(steps.count) first steps done"
        return Card(padding: 16, radius: Theme.Radius.hero) {
            HStack(spacing: 16) {
                GoalRing(progress: fraction, done: steps.count > 0 && done == steps.count, size: 64, label: steps.isEmpty ? "" : "\(Int((fraction * 100).rounded()))%")
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your goals").capsLabel()
                    Text(line).font(.serifTitle(20)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                    if e.legacyScore > 0 {
                        Text("Legacy \(Int(e.legacyScore.rounded()))").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Today

    @ViewBuilder private func todayCard(_ e: GameEngine) -> some View {
        if let g = daily {
            let cur = e.homeCurrency
            let streak: String = g.streak > 0 ? " \u{00B7} \(g.streak + 1) days in a row" : ""
            let sub: String = g.claimed ? "Claimed. A new goal comes tomorrow." : g.progress
            CardSection("Today") {
                GoalRow(ring: GoalRing(progress: g.done || g.claimed ? 1 : 0, done: g.done || g.claimed),
                        title: g.title, detail: sub,
                        reward: "Reward " + cur.tidyShort(g.reward) + streak,
                        action: g.done && !g.claimed ? "Claim" : nil) {
                    if let r = store.act({ $0.claimDailyGoal() }) ?? nil {
                        Haptics.success(); store.show("Daily goal: \(cur.tidyShort(r)). A new goal comes tomorrow.", tone: "good"); refresh()
                    } else { Haptics.warning(); store.show("That goal cannot be claimed yet.", tone: "warn") }
                }
            }
        }
    }

    // MARK: First steps

    @ViewBuilder private func stepsCard(_ e: GameEngine) -> some View {
        if let steps = e.firstStepRewards {
            let hidden: Bool = e.firstStepRewardsHidden
            CardSection("First steps") {
                if !hidden {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                        if i > 0 { CardLine() }
                        stepRow(step)
                    }
                }
                Button(hidden ? "Show the first-step rewards again" : "Hide the first-step rewards") {
                    let ok: Bool = store.act { $0.setFirstStepsHidden(!hidden) } != nil
                    if ok { store.show(hidden ? "First-step rewards are back." : "First-step rewards hidden. Rewards you have not claimed stay available.", tone: "n") }
                    else { store.show("That could not be changed.", tone: "warn") }
                }
                .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold).buttonStyle(.plain).frame(minHeight: 36)
            }
        }
    }

    private func stepRow(_ step: PlayerGoals.FirstStep) -> some View {
        let finished: Bool = step.done || step.claimed
        let detail: String = step.claimed ? "Claimed" : step.done ? "Done" : step.how
        return GoalRow(ring: GoalRing(progress: finished ? 1 : 0, done: finished), title: step.title, detail: detail,
                       reward: "Reward: " + step.reward.lowercased(), action: step.done && !step.claimed ? "Claim" : nil) {
            if let t = store.act({ $0.claimFirstStep(id: step.id) }) ?? nil { Haptics.success(); store.show(t, tone: "good") }
            else { Haptics.warning(); store.show("That reward cannot be claimed yet.", tone: "warn") }
        }
    }

    // MARK: Ambition

    private func ambitionCard(_ e: GameEngine) -> some View {
        CardSection("Ambition") {
            if let path = e.currentAmbition, let name = e.ambitionPaths.first(where: { $0.id == path })?.name {
                ambitionBody(e, path: path, name: name)
            } else {
                Text("Choose what you want to build. Each path has its own milestones and a perk.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
            }
            ambitionMenu(e)
        }
    }

    @ViewBuilder private func ambitionBody(_ e: GameEngine, path: String, name: String) -> some View {
        let ms = e.ambitionMilestones(path: path)
        let perk: String = e.ambitionPerk(path: path)
        let count: Int = ms.filter { $0.done != nil }.count
        let fraction: Double = ms.isEmpty ? 0 : Double(count) / Double(ms.count)
        GoalRow(ring: GoalRing(progress: fraction, done: !ms.isEmpty && count == ms.count), title: name,
                detail: "\(count) of \(ms.count) milestones on this level", reward: perk.isEmpty ? "" : "Perk: " + perk, action: nil) {}
        ForEach(ms, id: \.id) { m in
            CardLine()
            let target: Double = m.target > 0 ? m.target : 1
            let part: Double = m.done != nil ? 1 : min(1, max(0, m.now / target))
            GoalRow(ring: GoalRing(progress: part, done: m.done != nil, size: 30), title: m.text, detail: m.done != nil ? "Done" : "\(Int((part * 100).rounded()))% there",
                    reward: "", action: nil, compact: true) {}
        }
    }

    private func ambitionMenu(_ e: GameEngine) -> some View {
        Menu {
            ForEach(e.ambitionPaths, id: \.id) { p in
                Button(p.name + ": " + p.detail) {
                    let ok: Bool = store.act { $0.chooseAmbition(path: p.id) } ?? false
                    Haptics.tap(); store.show(ok ? "Your ambition: \(p.name)." : "You cannot switch ambition yet.", tone: ok ? "good" : "warn")
                }
            }
        } label: {
            Text(e.currentAmbition == nil ? "Choose your ambition" : "Switch ambition")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
                .padding(.horizontal, 16).frame(minHeight: 40)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(Theme.gold, lineWidth: 1))
        }
        .padding(.top, 4)
    }
}

/// A progress ring: a grey track, a champagne arc for how far, and a tick in the middle once the goal is done (never colour alone).
struct GoalRing: View {
    var progress: Double
    var done: Bool
    var size: CGFloat = 38
    var label: String = ""

    var body: some View {
        let width: CGFloat = max(2.5, size * 0.09)
        let arc: Double = done ? 1 : min(1, max(0, progress))
        return ZStack {
            Circle().stroke(Theme.border, lineWidth: width)
            Circle().trim(from: 0, to: arc)
                .stroke(done ? Theme.gain : Theme.gold, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if done {
                GlyphView(glyph: Glyph.check, size: size * 0.42, weight: 2, tint: Theme.gain)
            } else if !label.isEmpty {
                Text(label).font(.system(size: size * 0.24, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(done ? "Done" : "\(Int((arc * 100).rounded())) percent")
    }
}

/// One line of the checklist: ring, title, a grey line, the reward line in champagne, and a Claim button when it can be claimed.
struct GoalRow: View {
    var ring: GoalRing
    var title: String
    var detail: String
    var reward: String
    var action: String?
    var compact = false
    var tap: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ring
            VStack(alignment: .leading, spacing: 2) {
                Text(title.tidyText).font(.system(size: compact ? 13 : 14.5, weight: compact ? .regular : .medium))
                    .foregroundStyle(ring.done ? Theme.ivoryMuted : Theme.ivory).fixedSize(horizontal: false, vertical: true)
                if !detail.isEmpty { Text(detail.tidyText).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true) }
                if !reward.isEmpty { Text(reward.tidyText).font(.system(size: 11.5)).foregroundStyle(Theme.gold).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            if let action { Button(action, action: tap).buttonStyle(QuietButtonStyle()) }
        }
        .padding(.vertical, compact ? 4 : 7)
        .accessibilityElement(children: .contain)
    }
}

/// The trophies as one shelf row: the latest trophies as medallions (empty slots for those still to win), the count, and a way into the
/// whole wall (Achievements).
struct TrophyShelfRow: View {
    var engine: GameEngine

    var body: some View {
        let entries = Trophies.entries(engine.state)
        let got = entries.filter { $0.reachedWeek != nil }.sorted { ($0.reachedWeek ?? 0) > ($1.reachedWeek ?? 0) }
        let slots: Int = 6
        return NavigationLink {
            AchievementsView().appScreen(title: "Achievements", subtitle: PhoneApp.achievements.subtitle)
        } label: {
            Card(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Trophy shelf").capsLabel()
                        Spacer()
                        LinkLabel(text: "\(got.count) of \(entries.count)")
                    }
                    HStack(spacing: 8) {
                        ForEach(0..<slots, id: \.self) { i in
                            Medallion(won: i < got.count)
                        }
                    }
                    if let latest = got.first {
                        Text("Latest: " + latest.name).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                    } else {
                        Text("Firsts and milestones show up here: the first customer, the first employee, the first million.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// One trophy slot on the shelf: a champagne cup in a ring when won, a dim empty ring when not.
struct Medallion: View {
    var won: Bool
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(won ? Theme.goldSelected : Color.clear)
            Circle().strokeBorder(won ? Theme.gold : Theme.border, lineWidth: 1)
            GlyphView(glyph: won ? Glyph.achievements : Glyph.ring, size: size * 0.5, weight: 1.5, tint: won ? Theme.gold : Theme.ivoryDim)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(won ? "Trophy won" : "Trophy not yet won")
    }
}
