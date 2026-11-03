import SwiftUI

/// Text whose number is `shown`: SwiftUI feeds it every step of an animation, so the figure counts instead of jumping.
struct CountingText: View, Animatable {
    var shown: Double
    var format: (Double) -> String

    var animatableData: Double {
        get { shown }
        set { shown = newValue }
    }

    var body: some View {
        Text(format(shown)).monospacedDigit()
    }
}

/// What restarts a `CountedFigure`'s counting: a new value, or the order to finish at once.
private struct CountKey: Hashable {
    var value: Double
    var instant: Bool
}

/// A real figure that counts up from 0 (about 400 ms, ease-out) the first time it appears, and counts from the shown to the new value
/// when `value` changes (another period picked). The counting is driven by a task that sets the shown number every frame, so it does
/// not depend on SwiftUI interpolating a view's data (which did not run on screen). `delay` waits before the count starts (a staggered
/// briefing); `instant` finishes it at once. Reduce Motion: the value is simply shown. `tint` colours it; nil keeps the surrounding
/// colour. Font and line limits come from the caller.
struct CountedFigure: View {
    var value: Double
    var format: (Double) -> String
    var tint: Color? = nil
    var duration: Double = 0.4
    var delay: Double = 0
    var instant: Bool = false
    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let current: Double = (reduceMotion || instant) ? value : shown
        let key = CountKey(value: value, instant: instant)
        label(current)
            .task(id: key) { await count(to: key.value, instant: key.instant) }
    }

    @ViewBuilder private func label(_ current: Double) -> some View {
        if let tint {
            CountingText(shown: current, format: format).foregroundStyle(tint)
        } else {
            CountingText(shown: current, format: format)
        }
    }

    private func count(to target: Double, instant now: Bool) async {
        let from: Double = shown
        if reduceMotion || now || abs(from - target) < 0.0001 { shown = target; return }
        if delay > 0 && from == 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        let start: Date = Date()
        while !Task.isCancelled {
            let t: Double = Date().timeIntervalSince(start) / duration
            if t >= 1 { break }
            let eased: Double = 1 - pow(1 - t, 3)
            shown = from + (target - from) * eased
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
        if !Task.isCancelled { shown = target }
    }
}
