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
    @State private var editing = false
    @Environment(\.outsidePalette) private var P

    private var typed: PriceInput.Result? { PriceInput.parse(text, currency: cur, range: range) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PopupTextInput(placeholder: "Price", text: $text, prefix: cur.country.currencySymbol, suffix: unit, keyboard: .decimalPad,
                           actionTitle: "Set", actionEnabled: typed != nil, identifier: "typed-price",
                           hint: typed.flatMap { hint($0.value) }, message: nil,
                           onFocusChange: { (f: Bool) in editing = f }, onSubmit: { set() }, onAction: { set() })
            if let n = note ?? rangeNote {
                Text(n).popupText(.caption).foregroundStyle(P.inkFaint)
            }
        }
        .onAppear { text = PriceInput.text(price, currency: cur) }
        .onChange(of: price) { _, p in if !editing { text = PriceInput.text(p, currency: cur) } }
    }

    private var rangeNote: String? {
        guard let t = typed, t.clamped else { return nil }
        return "Allowed from " + PriceInput.text(range.lowerBound, currency: cur) + " to " + PriceInput.text(range.upperBound, currency: cur) + "; it will be set to \(PriceInput.text(t.value, currency: cur))."
    }

    private func set() {
        guard let t = typed else { return }
        text = PriceInput.text(t.value, currency: cur)
        note = nil
        onSet(t.value)
    }
}
