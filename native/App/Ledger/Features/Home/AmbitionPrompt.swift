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
        GamePopup(title: "What do you want to build?", showsClose: false, dismissOnBackdrop: false, category: .medium, tone: .investment, icon: "flag", onClose: { }) {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: PopupSpace.row) {
            Text("Pick an ambition. You can change it freely during your first four weeks.").popupText(.subtitle)
            ForEach(Ambitions.paths, id: \.id) { p in
                row(p.id, p.name)
            }
            QuietButton(title: "Decide later", fullWidth: true) { store.chooseAmbition(nil) }
                .padding(.top, 4).accessibilityIdentifier("ambition-later")
        }
    }

    private func row(_ id: String, _ name: String) -> some View {
        Button { Haptics.tap(); store.chooseAmbition(id) } label: {
            HStack(spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(name).popupText(.rowValue)
                    Text(Self.lines[id] ?? "").popupText(.caption).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
            }
            .padding(.vertical, Theme.Space.s).frame(minHeight: 44)
            .overlay(alignment: .bottom) { Hairline() }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("ambition-" + id)
    }
}
