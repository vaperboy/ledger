import SwiftUI

/// The (i) for text that is too long to sit beside a button or switch: the sentence moves here, unchanged, and
/// opens in a centred popup that is exactly as high as its text.
struct InfoSheetButton: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var text: String
    /// VoiceOver label and UI-test id; the label defaults to "About <title>".
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
