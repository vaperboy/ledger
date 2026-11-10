import SwiftUI

struct InfoSheetButton: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var text: String
    var label: String = ""
    var identifier: String = ""
    @State private var open = false

    var body: some View {
        Button { Haptics.tap(); open = true } label: {
            LedgerGlyph(glyph: Glyph.info, size: Theme.Icon.small, tint: P.inkFaint)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label.isEmpty ? "About " + title : label)
        .accessibilityIdentifier(identifier)
        .centerSheet(isPresented: $open, title: title, size: .fit) {
            Text(text).popupText(.subtitle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
