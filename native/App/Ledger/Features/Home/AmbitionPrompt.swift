import SwiftUI
import Businesses
import Simulation

/// The popup shown once at the start of a new game, before the first day: pick what you want to build. Each ambition has one short
/// line. The choice can be changed freely during the first four weeks (Phone > Goals), and "Decide later" keeps it open.
struct AmbitionPrompt: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private static let lines: [String: String] = [
        "titan": "Companies that supply each other; steadier costs.",
        "dynasty": "Own outright, keep control, never go bust.",
        "dominator": "Be the biggest in your markets; buy rivals.",
        "champion": "Few companies, excellent and very profitable.",
        "financier": "Make money with money: holdings, banks, stakes.",
        "global": "Companies in many countries.",
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            card
                .padding(.horizontal, 22)
                .scaleEffect(shown || reduceMotion ? 1 : 0.94)
                .opacity(shown ? 1 : 0)
        }
        .onAppear { Motion.animate(Motion.arrive(reduceMotion)) { shown = true } }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What do you want to build?").font(.serifTitle(22)).foregroundStyle(Theme.ivory)
            Text("Pick an ambition. You can change it freely during your first four weeks.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Ambitions.paths, id: \.id) { p in
                row(p.id, p.name)
            }
            QuietButton(title: "Decide later", fullWidth: true) { store.chooseAmbition(nil) }
                .padding(.top, 4).accessibilityIdentifier("ambition-later")
        }
        .padding(18)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(Theme.gold.opacity(0.6), lineWidth: 1))
    }

    private func row(_ id: String, _ name: String) -> some View {
        Button { Haptics.tap(); store.chooseAmbition(id) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.ivory)
                Text(Self.lines[id] ?? "").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.surfaceTable))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("ambition-" + id)
    }
}
