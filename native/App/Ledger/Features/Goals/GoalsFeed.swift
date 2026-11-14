import SwiftUI
import GameCore
import Simulation

// One goal as the Goals screen and the Home strip show it. Built only from values the engine already computes.
struct GoalLine: Identifiable {
    var id: String
    var title: String
    var detail: String = ""
    var reward: String = ""
    var progress: Double? = nil
    var done: Bool = false
    var current: Bool = false
    var link: String = ""
    var claim: GoalClaims.Claimable? = nil
}

enum GoalsFeed {
    static func progressWords(_ fraction: Double) -> String {
        switch fraction {
        case ..<0.05: return "Not started"
        case ..<0.35: return "Just getting going"
        case ..<0.65: return "About halfway"
        case ..<0.9: return "Getting close"
        default: return "Almost there"
        }
    }

    private static func claim(_ claims: [GoalClaims.Claimable], _ kind: GoalClaims.Kind, _ id: String) -> GoalClaims.Claimable? {
        claims.first { (c: GoalClaims.Claimable) -> Bool in c.kind == kind && c.goalID == id }
    }

    // Ladder goals M1 onward, then the chain and franchise goals once the ladder is finished.
    static func missions(_ e: GameEngine, claims: [GoalClaims.Claimable]) -> [GoalLine] {
        guard let ladder = PlayerGoals.ladder(e.state) else { return [] }
        let now: String? = PlayerGoals.currentLadderGoal(e.state)?.id
        var out: [GoalLine] = ladder.map { (g: PlayerGoals.LadderGoal) -> GoalLine in
            GoalLine(id: "ladder-" + g.id, title: g.title, detail: g.done ? g.pastTense : g.body, reward: g.reward, done: g.done,
                     current: g.id == now, link: g.done ? "" : g.link, claim: claim(claims, .ladder, g.id))
        }
        out += PlayerGoals.advancedGoals(e.state).map { (g: PlayerGoals.LadderGoal) -> GoalLine in
            GoalLine(id: "adv-" + g.id, title: g.title, detail: g.done ? g.pastTense : g.body, done: g.done, link: g.done ? "" : g.link)
        }
        return out
    }

    // Every career goal that is still open or waiting to be claimed, with how far along it is.
    static func career(_ e: GameEngine, claims: [GoalClaims.Claimable]) -> (open: [GoalLine], finished: Int) {
        let all: [Career.Goal] = Career.goals(e.state, data: e.data, currency: e.homeCurrency)
        let open: [GoalLine] = all.filter { (g: Career.Goal) -> Bool in !g.done || g.unclaimed }.map { (g: Career.Goal) -> GoalLine in
            GoalLine(id: "career-" + g.id, title: g.title, detail: g.horizon.label + " goal. " + (g.done ? "Finished" : progressWords(g.progress)),
                     reward: g.reward, progress: g.done ? 1 : g.progress, done: g.done, link: g.done ? "" : g.link, claim: claim(claims, .career, g.id))
        }
        return (open, all.filter { (g: Career.Goal) -> Bool in g.done }.count)
    }

    // The single goal the Home strip points at: rewards first, then the ladder, today's goal, the closest career goal.
    struct Next {
        var label: String
        var title: String
        var ready: Bool
        var count: Int = 0
    }

    static func next(_ e: GameEngine, missions: [PlayMissions.Entry], claims: [GoalClaims.Claimable]) -> Next? {
        let waiting: Int = missions.filter { (m: PlayMissions.Entry) -> Bool in m.ready }.count + claims.count
        if waiting > 0 {
            return Next(label: "Rewards ready", title: waiting == 1 ? "1 reward to claim" : "\(waiting) rewards to claim", ready: true, count: waiting)
        }
        if e.ambitionCardPending {
            return Next(label: "Ambition", title: "Choose what you want to build", ready: false)
        }
        if let g = PlayerGoals.currentLadderGoal(e.state) {
            return Next(label: "Next goal", title: g.title, ready: false)
        }
        if let m = missions.first(where: { (x: PlayMissions.Entry) -> Bool in !x.done && x.period == .day }) {
            return Next(label: "Today", title: m.title, ready: false)
        }
        if let g = e.careerNextGoals.filter({ (x: Career.Goal) -> Bool in !x.done }).max(by: { (a: Career.Goal, b: Career.Goal) -> Bool in a.progress < b.progress }) {
            return Next(label: "Next goal", title: g.title, ready: false)
        }
        return nil
    }
}

// Ring used by goal rows and the ambition card.
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
