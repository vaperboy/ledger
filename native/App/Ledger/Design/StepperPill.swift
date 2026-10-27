import SwiftUI

/// Minus and plus in one grey-outlined box.
struct StepperPill: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var body: some View {
        HStack(spacing: 0) {
            Button { value = max(range.lowerBound, value - step); Haptics.choose() } label: { GlyphView(glyph: Glyph.minus, size: 14, weight: 2, tint: Theme.gold).frame(width: 40, height: 32) }
                .disabled(value <= range.lowerBound)
            Rectangle().fill(Theme.divider).frame(width: 1, height: 18)
            Button { value = min(range.upperBound, value + step); Haptics.choose() } label: { GlyphView(glyph: Glyph.hire, size: 14, weight: 2, tint: Theme.gold).frame(width: 40, height: 32) }
                .disabled(value >= range.upperBound)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.gold)
        .buttonStyle(.plain)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(Theme.borderStrong, lineWidth: 1))
    }
}
