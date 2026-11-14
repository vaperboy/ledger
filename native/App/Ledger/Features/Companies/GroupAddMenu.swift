import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

enum GroupAddDestination: String, Identifiable, Hashable {
    case newCompany, franchise, club
    var id: String { rawValue }
}

struct GroupAddMenu: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var onPick: (GroupAddDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            row(.newCompany, title: "New company", line: "Any trade, any city", id: "group-add-company")
            row(.franchise, title: "Join a franchise", line: "A known brand, for a fee", id: "group-add-franchise")
        }
        .centerSheetTitle("Add to group")
    }

    private func row(_ d: GroupAddDestination, title: String, line: String, id: String) -> some View {
        HStack(spacing: Theme.Space.s) {
            Button { Haptics.tap(); onPick(d) } label: {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(title).popupText(.button)
                    Text(line).popupText(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier(id)
            GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.ivoryDim)
        }
        .padding(.vertical, Theme.Space.xs)
        .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }
}
