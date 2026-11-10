import SwiftUI
import Countries
import Businesses

struct TypedPriceField: View {
    var price: Double
    var range: ClosedRange<Double>
    var cur: Currency
    var unit: String
    var market: Double? = nil
    var hint: (Double) -> String? = { _ in nil }
    var onSet: (Double) -> Void
    @State private var text = ""
    @State private var note: String?
    @State private var editing = false
    @Environment(\.outsidePalette) private var P

    private var typed: PriceInput.Result? { PriceInput.parse(text, currency: cur, range: range) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let market {
                HStack {
                    Text("Market price").popupText(.caption).foregroundStyle(P.inkFaint)
                    Spacer()
                    Text(PriceInput.text(market, currency: cur) + " " + unit).popupText(.caption).foregroundStyle(P.inkSoft)
                }
            }
            Text("Your price").popupText(.caption).foregroundStyle(P.inkFaint)
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
