import SwiftUI

struct ShopQuantity: View {
    @Environment(\.outsidePalette) private var P
    var label: String = "Quantity"
    var value: Int
    var range: ClosedRange<Int>
    var onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Text(label.tidyText).textStyle(.body, tint: P.inkSoft)
            Spacer(minLength: Theme.Space.s)
            HStack(spacing: 0) {
                Button { onChange(max(range.lowerBound, value - 1)); Haptics.choose() } label: {
                    LedgerGlyph(glyph: Glyph.minus, size: Theme.Icon.small, tint: P.accent).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .disabled(value <= range.lowerBound)
                .accessibilityLabel("Fewer")
                Text("\(value)").textStyle(.headline, numeric: true).frame(minWidth: 28)
                Button { onChange(min(range.upperBound, value + 1)); Haptics.choose() } label: {
                    LedgerGlyph(glyph: Glyph.hire, size: Theme.Icon.small, tint: P.accent).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .disabled(value >= range.upperBound)
                .accessibilityLabel("More")
            }
            .buttonStyle(PressableStyle())
            .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(P.inset))
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(value)")
    }
}
