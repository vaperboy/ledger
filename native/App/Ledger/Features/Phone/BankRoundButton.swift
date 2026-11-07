import SwiftUI
import GameCore
import Countries
import Simulation

/// A round outlined action button with its label under it (Deposit, Send, Transfer, Buy, Sell). Never filled: only Next Day is.
struct BankRoundButton: View {
    @Environment(\.outsidePalette) private var P
    var glyph: String
    var title: String
    var tint: Color? = nil
    var badge: Int = 0
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 6) {
                GlyphView(glyph: glyph, size: 22, weight: 1.6, tint: tint ?? P.accent)
                    .frame(width: 56, height: 56)
                    .overlay(Circle().strokeBorder(P.lineStrong, lineWidth: 1))
                    .overlay(alignment: .topTrailing) { RedBubble(count: badge, size: .small).offset(x: 2, y: -2) }
                Text(title).textStyle(.caption, tint: P.ink).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
    }
}
