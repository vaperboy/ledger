import SwiftUI
import GameCore
import Countries
import Businesses

/// The price as a big figure between a minus and a plus button. Tap the figure to type a price.
struct PriceStepperField: View {
    var price: Double
    var range: ClosedRange<Double>
    var step: Double
    var cur: Currency
    var unit: String
    var onSet: (Double) -> Void
    @Environment(\.outsidePalette) private var P
    @State private var text = ""
    @State private var typing = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.l) {
                stepButton(symbol: "minus", label: "Lower the price", delta: -step)
                VStack(spacing: Theme.Space.xxs) {
                    if typing {
                        TextField("Price", text: $text)
                            .font(PopupVariant.standard.figureFont)
                            .foregroundStyle(P.ink)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .focused($focused)
                            .onAppear { focused = true }
                            .onSubmit { finish() }
                            .accessibilityIdentifier("item-price-field")
                    } else {
                        Button { Haptics.tap(); text = PriceInput.text(price, currency: cur); typing = true } label: {
                            Text(itemAmount(price, cur)).popupText(.figure).lineLimit(1).minimumScaleFactor(0.6)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityHint("Type a price")
                        .accessibilityIdentifier("sales-item-price")
                    }
                    Text(unit).popupText(.caption)
                }
                .frame(maxWidth: .infinity)
                stepButton(symbol: "plus", label: "Raise the price", delta: step)
            }
            if typing {
                Button("Set price") { finish() }
                    .buttonStyle(SecondaryButtonStyle(size: .compact, tint: P.accent))
                    .accessibilityIdentifier("item-price-set")
            }
        }
        .onChange(of: focused) { _, now in if !now && typing { finish() } }
    }

    private func stepButton(symbol: String, label: String, delta: Double) -> some View {
        let next: Double = min(max(price + delta, range.lowerBound), range.upperBound)
        let blocked: Bool = abs(next - price) < 1e-9
        return Button { Haptics.tap(); onSet(next) } label: {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                .foregroundStyle(blocked ? P.inkFaint : P.accent)
                .frame(width: 48, height: 48)
                .background(Circle().fill(P.inset))
        }
        .buttonStyle(PressableStyle())
        .disabled(blocked)
        .accessibilityLabel(label)
        .accessibilityIdentifier("item-price-" + symbol)
    }

    private func finish() {
        let value: Double? = PriceInput.parse(text, currency: cur, range: range)?.value
        typing = false
        focused = false
        if let value { onSet(value) }
    }
}

/// One bar from the lowest to the highest allowed price. Red is below cost, the line is the market price, the round handle is your price.
struct PriceBar: View {
    var lo: Double
    var hi: Double
    var cost: Double
    var market: Double
    var price: Double
    var onChange: (Double) -> Void
    var onEnd: () -> Void
    private let handle: CGFloat = 28

    var body: some View {
        GeometryReader { (g: GeometryProxy) in
            let w: CGFloat = max(1, g.size.width)
            let span: Double = max(1e-9, hi - lo)
            let x: (Double) -> CGFloat = { (v: Double) -> CGFloat in CGFloat(min(max((v - lo) / span, 0), 1)) * w }
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.gain.opacity(0.4)).frame(width: w, height: 8)
                Capsule().fill(Theme.loss.opacity(0.6)).frame(width: x(cost), height: 8)
                Rectangle().fill(Theme.ink.opacity(0.85)).frame(width: 2, height: 18).offset(x: x(market) - 1)
                Circle().fill(price >= cost ? Theme.gain : Theme.loss)
                    .frame(width: handle, height: handle)
                    .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2))
                    .offset(x: min(max(x(price) - handle / 2, 0), w - handle))
            }
            .frame(width: w, height: g.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { (v: DragGesture.Value) in
                        let f: Double = Double(min(max(v.location.x / w, 0), 1))
                        onChange(lo + f * span)
                    }
                    .onEnded { (_: DragGesture.Value) in onEnd() }
            )
        }
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Price bar")
        .accessibilityValue("Cost, market and your price")
        .accessibilityAdjustableAction { (d: AccessibilityAdjustmentDirection) in
            let step: Double = (hi - lo) / 20
            switch d {
            case .increment: onChange(min(hi, price + step)); onEnd()
            case .decrement: onChange(max(lo, price - step)); onEnd()
            @unknown default: break
            }
        }
        .accessibilityIdentifier("item-price-bar")
    }
}

enum ItemPriceWords {
    /// Units a week as the player reads them: whole numbers when many, one decimal when few, never a bare 0 for a small sale.
    static func units(_ u: Double) -> String {
        if u <= 0 { return "0" }
        if u < 0.1 { return "< 0.1" }
        if u >= 10 { return String(format: "%.0f", u) }
        let t: String = String(format: "%.1f", u)
        return t.hasSuffix(".0") ? String(t.dropLast(2)) : t
    }

    /// A step for the plus and minus buttons: about two percent of the market price, rounded to 1, 2 or 5 of a round unit.
    static func step(market: Double, cur: Currency) -> Double {
        let cent: Double = 0.01 * cur.rate
        let shown: Double = max(market * 0.02, cent) / cur.rate
        let mag: Double = pow(10, floor(log10(shown)))
        let lead: Double = shown / mag
        let nice: Double = lead < 1.5 ? 1 : (lead < 3.5 ? 2 : (lead < 7.5 ? 5 : 10))
        return max(cent, nice * mag * cur.rate)
    }
}
