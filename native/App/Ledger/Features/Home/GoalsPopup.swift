import SwiftUI
import GameCore
import Simulation

/// The popup behind "Your next goal" on Home: every goal being tracked (the ladder goal, today's goal and the next career goals), each with how
/// far along it is in words. A row closes the popup and goes to where that goal is done.
struct GoalsPopup: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var daily: PlayerGoals.DailyGoal?
    var close: () -> Void

    /// How far along, in plain words (the exact fraction is not worth a number).
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
        var progress: Double
        var link: String
    }

    private var rows: [(heading: String, rows: [Row])] {
        var out: [(heading: String, rows: [Row])] = []
        if let g = PlayerGoals.currentLadderGoal(engine.state) {
            out.append(("Next goal", [Row(id: "ladder", title: g.title, detail: g.body, progress: 0, link: g.link)]))
        }
        if let d = daily, !d.done {
            out.append(("Today", [Row(id: "daily", title: d.title, detail: d.progress, progress: -1, link: d.link)]))
        }
        let career: [Row] = engine.careerNextGoals.map { (g: Career.Goal) -> Row in
            Row(id: g.id, title: g.title, detail: g.horizon.label + " goal. " + Self.progressWords(g.progress), progress: g.progress, link: g.link)
        }
        if !career.isEmpty { out.append(("Coming up", career)) }
        return out
    }

    var body: some View {
        let groups = rows
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if groups.isEmpty {
                Text("No goals are open right now.").textStyle(.body, tint: Theme.inkSoft)
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { (_: Int, g: (heading: String, rows: [Row])) in
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(g.heading).textStyle(.label, tint: Theme.inkFaint)
                    ForEach(g.rows) { (r: Row) in row(r) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("goals-popup")
    }

    private func row(_ r: Row) -> some View {
        let opens: Bool = !r.link.isEmpty
        return Button {
            guard opens else { return }
            Haptics.tap()
            close()
            if r.link == "goals" { store.openApp(.goals) } else { _ = store.openLadderLink(r.link) }
        } label: {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                GoalRing(progress: max(0, r.progress), done: false)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(r.title.tidyMoney).textStyle(.headline).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    if !r.detail.isEmpty {
                        Text(r.detail.tidyMoney).textStyle(.caption).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
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
