import SwiftUI

/// Minus and plus on one inset track (no outline), each a 44 pt target.
struct StepperPill: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var body: some View {
        HStack(spacing: 0) {
            Button { value = max(range.lowerBound, value - step); Haptics.choose() } label: { LedgerGlyph(glyph: Glyph.minus, size: Theme.Icon.small, tint: Theme.accent).frame(width: 44, height: 44) }
                .disabled(value <= range.lowerBound).accessibilityLabel("Decrease")
            Rectangle().fill(Theme.line).frame(width: 0.5, height: 18)
            Button { value = min(range.upperBound, value + step); Haptics.choose() } label: { LedgerGlyph(glyph: Glyph.hire, size: Theme.Icon.small, tint: Theme.accent).frame(width: 44, height: 44) }
                .disabled(value >= range.upperBound).accessibilityLabel("Increase")
        }
        .textStyle(.body, tint: Theme.accent, weight: .semibold)
        .buttonStyle(PressableStyle())
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(Theme.inset).padding(.vertical, 6))
    }
}
