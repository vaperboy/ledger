import SwiftUI

/// The one slider of the app: a slim 3pt track, the active part in the Ledger champagne, a small refined 20pt thumb inside an invisible
/// 44pt touch area, an optional value text, step snapping, and a haptic only when a snap point (or an end) is reached.
/// Same use as `Slider(value:in:step:onEditingChanged:)`; `onEditingChanged(true)` fires when a drag starts and `(false)` when it ends,
/// so a caller can commit on release while the binding follows the finger.
struct LedgerSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double? = nil
    /// A value text shown above the track on the right (optional; the caller formats it).
    var valueText: String? = nil
    var onEditingChanged: (Bool) -> Void = { _ in }
    @Environment(\.outsidePalette) private var P
    @Environment(\.isEnabled) private var isEnabled
    @State private var dragging = false
    @State private var lastTick: Double = .nan

    init(value: Binding<Double>, in range: ClosedRange<Double>, step: Double? = nil, valueText: String? = nil,
         onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self._value = value
        self.range = range
        self.step = step
        self.valueText = valueText
        self.onEditingChanged = onEditingChanged
    }

    private var span: Double { max(range.upperBound - range.lowerBound, 0.000001) }
    private let thumb: CGFloat = 20
    private var hit: CGFloat = 44

    /// A shorter touch area for dense rows (still at least 30pt high); the default is 44pt.
    func hitHeight(_ h: CGFloat) -> LedgerSlider {
        var c: LedgerSlider = self
        c.hit = max(30, h)
        return c
    }

    private func fraction(_ v: Double) -> CGFloat {
        let f: Double = (v - range.lowerBound) / span
        return CGFloat(min(1, max(0, f)))
    }

    private func snapped(_ raw: Double) -> Double {
        var v: Double = min(range.upperBound, max(range.lowerBound, raw))
        if let step, step > 0 {
            let n: Double = ((v - range.lowerBound) / step).rounded()
            v = min(range.upperBound, range.lowerBound + n * step)
        }
        return v
    }

    private func update(x: CGFloat, width: CGFloat) {
        let usable: CGFloat = max(1, width - thumb)
        let f: Double = Double(min(1, max(0, (x - thumb / 2) / usable)))
        let v: Double = snapped(range.lowerBound + f * span)
        if !dragging {
            dragging = true
            onEditingChanged(true)
        }
        if v != value { value = v }
        let atEnd: Bool = v == range.lowerBound || v == range.upperBound
        if (step != nil || atEnd) && v != lastTick {
            lastTick = v
            Haptics.choose()
        }
    }

    private func finish() {
        guard dragging else { return }
        dragging = false
        lastTick = .nan
        onEditingChanged(false)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if let valueText {
                Text(valueText).font(.system(size: 12.5, weight: .medium).monospacedDigit()).foregroundStyle(P.inkSoft)
            }
            track
        }
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(valueText ?? String(format: "%.0f", value))
        .accessibilityAdjustableAction { (direction: AccessibilityAdjustmentDirection) in
            let d: Double = step ?? (span / 20)
            switch direction {
            case .increment: value = snapped(value + d); onEditingChanged(true); onEditingChanged(false)
            case .decrement: value = snapped(value - d); onEditingChanged(true); onEditingChanged(false)
            @unknown default: break
            }
        }
    }

    private var track: some View {
        GeometryReader { (geo: GeometryProxy) in
            let w: CGFloat = geo.size.width
            let usable: CGFloat = max(1, w - thumb)
            let x: CGFloat = thumb / 2 + usable * fraction(value)
            ZStack(alignment: .leading) {
                Capsule().fill(P.lineStrong).frame(height: 3)
                Capsule().fill(P.accent).frame(width: x, height: 3)
                Circle()
                    .fill(P.accent)
                    .overlay(Circle().strokeBorder(P.card, lineWidth: 2))
                    .frame(width: thumb, height: thumb)
                    .scaleEffect(dragging ? 1.12 : 1)
                    .shadow(color: Color.black.opacity(0.35), radius: 2, y: 1)
                    .offset(x: x - thumb / 2)
            }
            .frame(width: w, height: hit)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { (g: DragGesture.Value) in PageSwipeGate.shared.touching = true; update(x: g.location.x, width: w) }
                    .onEnded { (_: DragGesture.Value) in PageSwipeGate.shared.touching = false; finish() }
            )
            .animation(.easeOut(duration: 0.12), value: dragging)
        }
        .frame(height: hit)
    }
}

/// The refined switch: a small 38x23 capsule with a champagne "on" state. Used on its own where a row has its own label.
struct LedgerSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.outsidePalette) private var P
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var rowHeight: CGFloat = 44

    init(isOn: Binding<Bool>) { self._isOn = isOn }

    /// A shorter touch area for dense rows.
    func hitHeight(_ h: CGFloat) -> LedgerSwitch {
        var c: LedgerSwitch = self
        c.rowHeight = max(28, h)
        return c
    }

    var body: some View {
        Button {
            Haptics.tap()
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? P.accent : P.lineStrong).frame(width: 38, height: 23)
                Circle().fill(isOn ? P.card : P.inkSoft).frame(width: 17, height: 17).padding(.horizontal, 3)
            }
            .frame(width: 38, height: 23)
            .frame(minWidth: 44, minHeight: rowHeight)
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isOn)
        }
        .buttonStyle(PressableStyle())
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// `Toggle` with a visible label: the label on the left, the refined switch on the right. Set once at the app root and inside popups.
/// A toggle with a hidden label uses `LedgerSwitch` directly instead.
struct LedgerToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
            Spacer(minLength: 8)
            LedgerSwitch(isOn: configuration.$isOn)
        }
    }
}
