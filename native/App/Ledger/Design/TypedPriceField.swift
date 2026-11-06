import SwiftUI
import Countries
import Businesses

/// A price typed in the trade's own unit ("an hour", "each", "a night") next to a slider. The number is held inside `range` (the slider's range),
/// `hint` gives a live profit line for what is typed, and `onSet` receives the price in accounting units when the person taps Set or presses return.
struct TypedPriceField: View {
    var price: Double
    var range: ClosedRange<Double>
    var cur: Currency
    var unit: String
    var hint: (Double) -> String? = { _ in nil }
    var onSet: (Double) -> Void
    @State private var text = ""
    @State private var note: String?
    @FocusState private var focused: Bool

    private var typed: PriceInput.Result? { PriceInput.parse(text, currency: cur, range: range) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(cur.country.currencySymbol).foregroundStyle(Theme.ivoryMuted)
                TextField("Price", text: $text)
                    .keyboardType(.decimalPad).focused($focused)
                    .font(.system(size: 16, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.ivory)
                    .accessibilityIdentifier("typed-price")
                    .onSubmit { set() }
                Text(unit).font(.caption).foregroundStyle(Theme.ivoryMuted)
                Button("Set") { set() }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(typed == nil ? Theme.ivoryFaint : Theme.gold)
                    .disabled(typed == nil)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            if let t = typed, let h = hint(t.value) {
                Text(h).font(.caption).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
            }
            if let n = note ?? rangeNote {
                Text(n).font(.caption).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { text = PriceInput.text(price, currency: cur) }
        .onChange(of: price) { _, p in if !focused { text = PriceInput.text(p, currency: cur) } }
    }

    private var rangeNote: String? {
        guard let t = typed, t.clamped else { return nil }
        return "Allowed from " + PriceInput.text(range.lowerBound, currency: cur) + " to " + PriceInput.text(range.upperBound, currency: cur) + "; it will be set to \(PriceInput.text(t.value, currency: cur))."
    }

    private func set() {
        guard let t = typed else { return }
        focused = false
        text = PriceInput.text(t.value, currency: cur)
        note = nil
        onSet(t.value)
    }
}
