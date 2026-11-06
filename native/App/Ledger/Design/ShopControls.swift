import SwiftUI

/// A quantity with minus and plus (44 pt each) and the number between them.
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

/// The label of a business picker menu (Market, Reviews): the app's glyph, the business chosen and a down chevron, on a flat tile.
struct BusinessMenuLabel: View {
    @Environment(\.outsidePalette) private var P
    var glyph: String
    var title: String

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            LedgerGlyph(glyph: glyph, size: Theme.Icon.medium, tint: P.accent)
            Text(title.tidyText).textStyle(.headline).lineLimit(1)
            Spacer(minLength: Theme.Space.s)
            LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint).rotationEffect(.degrees(90))
        }
        .padding(.horizontal, Theme.Space.m).frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(P.surface))
        .contentShape(Rectangle())
    }
}
