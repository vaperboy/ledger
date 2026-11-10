import SwiftUI
import GameCore
import Countries
import Simulation

struct GoalsPopup: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var daily: PlayerGoals.DailyGoal?
    var close: () -> Void

    static func progressWords(_ fraction: Double) -> String {
        switch fraction {
        case ..<0.05: return "Not started"
        case ..<0.35: return "Just getting going"
        case ..<0.65: return "About halfway"
        case ..<0.9: return "Getting close"
        default: return "Almost there"
        }
    }

    private struct Row: Identifiable {
        var id: String
        var title: String
        var detail: String
        var reward: String
        var progress: Double
        var link: String
    }

    private var rows: [(heading: String, rows: [Row])] {
        var out: [(heading: String, rows: [Row])] = []
        if let g = PlayerGoals.currentLadderGoal(engine.state) {
            out.append(("Next goal", [Row(id: "ladder", title: g.title, detail: g.body, reward: g.reward, progress: 0, link: g.link)]))
        }
        if let d = daily, !d.done {
            out.append(("Today", [Row(id: "daily", title: d.title, detail: d.progress, reward: d.streak > 0 ? "\(d.streak) \(d.streak == 1 ? "day" : "days") in a row" : "", progress: 0, link: d.link)]))
        }
        let career: [Row] = engine.careerNextGoals.map { (g: Career.Goal) -> Row in
            Row(id: g.id, title: g.title, detail: g.horizon.label + " goal. " + Self.progressWords(g.progress), reward: g.reward, progress: g.progress, link: g.link)
        }
        if !career.isEmpty { out.append(("Coming up", career)) }
        return out
    }

    var body: some View {
        let groups = rows
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            rank
            if !store.claimableGoals.isEmpty { claimSection }
            if groups.isEmpty && store.claimableGoals.isEmpty {
                Text("No goals are open right now.").textStyle(.body, tint: Theme.inkSoft)
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { (_: Int, g: (heading: String, rows: [Row])) in
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(g.heading).textStyle(.label, tint: Theme.inkFaint)
                    ForEach(g.rows) { (r: Row) in row(r) }
                }
            }
            if engine.ambitionVisible { ambition }
            dailySwitch
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("goals-popup")
    }

    private var rank: some View {
        let st: Career.RankStatus = engine.careerStatus
        let line: String = st.next.map { "Next: \($0.title). \(st.missing)" } ?? "You are at the top of the ladder."
        return HStack(spacing: Theme.Space.m) {
            GoalRing(progress: st.progress, done: st.next == nil, size: 52, label: "\(Int(saturating: (st.progress * 100).rounded()))%")
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(st.rank.title).textStyle(.headline)
                Text(line).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var claimSection: some View {
        let cur: Currency? = engine.homeCurrency
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Ready to claim").textStyle(.label, tint: Theme.inkFaint)
            ForEach(store.claimableGoals) { (c: GoalClaims.Claimable) in
                HStack(alignment: .center, spacing: Theme.Space.m) {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(c.title.tidyMoney).textStyle(.headline).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        let words: String = ([c.reward] + (c.cash > 0 ? [cur.map { "+" + $0.display(c.cash) } ?? ""] : [])).filter { !$0.isEmpty }.joined(separator: ". ")
                        if !words.isEmpty { Text(words).textStyle(.caption, tint: Theme.accent).fixedSize(horizontal: false, vertical: true) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button { store.claimGoal(c.kind, id: c.goalID) } label: {
                        Text("Claim").textStyle(.body, tint: Theme.accentInk, weight: .semibold)
                            .padding(.horizontal, Theme.Space.l).frame(minHeight: 36)
                            .background(Capsule().fill(Theme.accent))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("claim-" + c.id)
                }
                .padding(.vertical, Theme.Space.xs)
                .accessibilityElement(children: .contain)
            }
        }
    }

    private var ambition: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Ambition").textStyle(.label, tint: Theme.inkFaint)
            if let path = engine.currentAmbition, let name = engine.ambitionPaths.first(where: { $0.id == path })?.name {
                let ms = engine.ambitionMilestones(path: path)
                let count: Int = ms.filter { $0.done != nil }.count
                let perk: String = engine.ambitionPerk(path: path)
                HStack(spacing: Theme.Space.m) {
                    GoalRing(progress: ms.isEmpty ? 0 : Double(count) / Double(ms.count), done: !ms.isEmpty && count == ms.count)
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(name).textStyle(.headline)
                        Text("\(count) of \(ms.count) milestones").textStyle(.caption)
                        if !perk.isEmpty { Text("Perk: " + perk).textStyle(.caption, tint: Theme.accent).fixedSize(horizontal: false, vertical: true) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("Choose what you want to build. Each path has its own milestones and a perk.").textStyle(.caption)
            }
            Menu {
                ForEach(engine.ambitionPaths, id: \.id) { p in
                    Button(p.name + ": " + p.detail) {
                        let ok: Bool = store.act { $0.chooseAmbition(path: p.id) } ?? false
                        Haptics.tap(); store.show(ok ? "Your ambition: \(p.name)." : "You cannot switch ambition yet.", tone: ok ? "good" : "warn")
                    }
                }
            } label: {
                Text(engine.currentAmbition == nil ? "Choose your ambition" : "Switch ambition").textStyle(.body, tint: Theme.accent, weight: .medium).frame(minHeight: 36)
            }
        }
    }

    private var dailySwitch: some View {
        let off: Bool = engine.dailyGoalsOff
        return Button(off ? "Turn the daily goal on" : "Turn the daily goal off") {
            store.act { $0.setDailyGoalsOff(!off) }
            Haptics.tap()
            close()
        }
        .textStyle(.caption, tint: Theme.inkFaint, weight: .medium).buttonStyle(PressableStyle()).frame(minHeight: 36)
    }

    private func row(_ r: Row) -> some View {
        let opens: Bool = !r.link.isEmpty
        return Button {
            guard opens else { return }
            Haptics.tap()
            close()
            _ = store.openLadderLink(r.link)
        } label: {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                GoalRing(progress: max(0, r.progress), done: false)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(r.title.tidyMoney).textStyle(.headline).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    if !r.detail.isEmpty {
                        Text(r.detail.tidyMoney).textStyle(.caption).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                    if !r.reward.isEmpty {
                        Text("Reward: " + r.reward).textStyle(.caption, tint: Theme.accent).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if opens { LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint) }
            }
            .padding(.vertical, Theme.Space.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!opens)
        .accessibilityElement(children: .combine)
        .accessibilityHint(opens ? "Goes to where it is done" : "")
    }
}

struct GoalRing: View {
    var progress: Double
    var done: Bool
    var size: CGFloat = 38
    var label: String = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let width: CGFloat = max(2.5, size * 0.09)
        let arc: Double = done ? 1 : min(1, max(0, progress))
        return ZStack {
            Circle().stroke(Theme.border, lineWidth: width)
            Circle().trim(from: 0, to: arc)
                .stroke(done ? Theme.gain : Theme.gold, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.fill(reduceMotion), value: arc)
            if done {
                GlyphView(glyph: Glyph.check, size: size * 0.42, weight: 2, tint: Theme.gain)
            } else if !label.isEmpty {
                Text(label).font(.system(size: size * 0.24, weight: .medium).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
            }
        }
        .frame(width: size, height: size)
        .goldPulse(done)
        .accessibilityLabel(done ? "Done" : "\(Int(saturating: (arc * 100).rounded())) percent")
    }
}
