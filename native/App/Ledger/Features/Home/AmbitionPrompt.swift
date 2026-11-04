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
        GamePopup(title: "What do you want to build?", showsClose: false, dismissOnBackdrop: false, onClose: { }) {
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
            VStack(alignment: .leading, spacing: 1) {
                Text(name).popupText(.rowValue)
                Text(Self.lines[id] ?? "").popupText(.caption)
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
