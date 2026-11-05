import SwiftUI

/// The (i) for text that is too long to sit beside a button or switch: the sentence moves here, unchanged, and
/// opens in a centred popup that is exactly as high as its text.
struct InfoSheetButton: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var text: String
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            Text("i").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(P.inkSoft)
                .frame(width: 17, height: 17)
                .overlay(Circle().strokeBorder(P.inkSoft, lineWidth: 1))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("About " + title)
        .centerSheet(isPresented: $open, title: title, size: .fit) {
            Text(text).popupText(.subtitle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
