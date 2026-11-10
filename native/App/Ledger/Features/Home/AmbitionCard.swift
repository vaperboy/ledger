import SwiftUI
import Businesses
import Simulation

struct AmbitionCard: View {
    @EnvironmentObject var store: GameStore
    var compact: Bool = false

    private static let lines: [String: String] = [
        "titan": "Companies that supply each other; steadier costs.",
        "dynasty": "Own outright, keep control, never go bust.",
        "dominator": "Be the biggest in your markets; buy rivals.",
        "champion": "Few companies, excellent and very profitable.",
        "financier": "Make money with money: holdings, banks, stakes.",
        "global": "Companies in many countries.",
    ]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("What do you want to build?").textStyle(.headline).multilineTextAlignment(.leading)
            if !compact {
                Text("Pick a path with its own milestones and a perk. You can change it freely for four weeks.").textStyle(.caption)
            }
            HStack(spacing: Theme.Space.m) {
                Menu {
                    ForEach(Ambitions.paths, id: \.id) { p in
                        Button(p.name + ": " + (Self.lines[p.id] ?? "")) { Haptics.tap(); store.chooseAmbition(p.id) }
                    }
                } label: {
                    Text("Choose").textStyle(.body, tint: Theme.accent, weight: .semibold).frame(minHeight: 44)
                }
                .accessibilityIdentifier("ambition-choose")
                Button { Haptics.tap(); store.chooseAmbition(nil) } label: {
                    Text("Not now").textStyle(.body, tint: Theme.inkSoft).frame(minHeight: 44)
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("ambition-later")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, compact ? Theme.Space.m : Theme.Space.l).padding(.horizontal, Theme.Space.l)
        .background(shape.fill(Theme.surfaceRaised))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-ambition")
    }
}
