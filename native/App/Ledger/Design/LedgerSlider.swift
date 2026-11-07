import SwiftUI

/// The one slider of the app: a slim 3pt track, the active part in the accent, a plain 20pt ink thumb (no shadow, no ring) inside an invisible
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
    /// The direction of the current drag: nil until decided, true for sideways (moves the value), false for a scroll (ignored).
    @State private var axis: Bool? = nil
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
    /// Uneven snap points (sorted, inside the range); empty: `step` or a free value.
    private var stops: [Double] = []

    /// A shorter touch area for dense rows (still at least 30pt high); the default is 44pt.
    func hitHeight(_ h: CGFloat) -> LedgerSlider {
        var c: LedgerSlider = self
        c.hit = max(30, h)
        return c
    }

    /// Snaps to the nearest of `values` (uneven steps such as 0, 10, 25, 50, 100) instead of `step`. Empty keeps the default.
    func detents(_ values: [Double]) -> LedgerSlider {
        var c: LedgerSlider = self
        c.stops = values.filter { range.contains($0) }.sorted()
        return c
    }

    private func fraction(_ v: Double) -> CGFloat {
        let f: Double = (v - range.lowerBound) / span
        return CGFloat(min(1, max(0, f)))
    }

    private func snapped(_ raw: Double) -> Double {
        var v: Double = min(range.upperBound, max(range.lowerBound, raw))
        if let near = stops.min(by: { (a: Double, b: Double) -> Bool in abs(a - v) < abs(b - v) }) { return near }
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
        if (step != nil || !stops.isEmpty || atEnd) && v != lastTick {
            lastTick = v
            Haptics.choose()
        }
    }

    /// One VoiceOver adjustment: the next detent, else one `step` (or a twentieth of the range).
    private func nudged(up: Bool) -> Double {
        if !stops.isEmpty {
            let next: Double? = up ? stops.first(where: { (s: Double) -> Bool in s > value }) : stops.last(where: { (s: Double) -> Bool in s < value })
            return next ?? value
        }
        let d: Double = step ?? (span / 20)
        return snapped(up ? value + d : value - d)
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
                Text(valueText).textStyle(.caption, numeric: true, weight: .medium)
            }
            track
        }
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(valueText ?? String(format: "%.0f", value))
        .accessibilityAdjustableAction { (direction: AccessibilityAdjustmentDirection) in
            switch direction {
            case .increment: value = nudged(up: true); onEditingChanged(true); onEditingChanged(false)
            case .decrement: value = nudged(up: false); onEditingChanged(true); onEditingChanged(false)
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
                    .fill(P.ink)
                    .frame(width: thumb, height: thumb)
                    .scaleEffect(dragging ? 1.12 : 1)
                    .offset(x: x - thumb / 2)
            }
            .frame(width: w, height: hit)
            .contentShape(Rectangle())
            .gesture(
                // Only a clearly sideways drag moves the value: a scroll that starts on the track (mostly vertical) is ignored, so the
                // page scrolls instead and no value changes by accident.
                DragGesture(minimumDistance: 8)
                    .onChanged { (g: DragGesture.Value) in
                        if axis == nil { axis = abs(g.translation.width) > abs(g.translation.height) * 1.2 }
                        guard axis == true else { return }
                        PageSwipeGate.shared.touching = true
                        update(x: g.location.x, width: w)
                    }
                    .onEnded { (_: DragGesture.Value) in
                        let moved: Bool = axis == true
                        axis = nil
                        PageSwipeGate.shared.touching = false
                        if moved { finish() }
                    }
            )
            .animation(Motion.tapAnimation, value: dragging)
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
            .animation(reduceMotion ? nil : Motion.tapAnimation, value: isOn)
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
