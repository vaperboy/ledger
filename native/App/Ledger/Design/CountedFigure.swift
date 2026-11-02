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

/// A real figure that counts up from 0 (about 350 ms) the first time it appears, and counts from the old to the new value when `value`
/// changes (another period picked). Reduce Motion: the value is simply shown. `tint` colours it (green gain, red loss); nil keeps the
/// surrounding colour. Font and line limits come from the caller.
struct CountedFigure: View {
    var value: Double
    var format: (Double) -> String
    var tint: Color? = nil
    var duration: Double = 0.35
    @State private var shown: Double = 0
    @State private var started: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let current: Double = reduceMotion ? value : shown
        if let tint {
            CountingText(shown: current, format: format).foregroundStyle(tint)
                .onAppear { begin() }
                .onChange(of: value) { _, new in follow(new) }
        } else {
            CountingText(shown: current, format: format)
                .onAppear { begin() }
                .onChange(of: value) { _, new in follow(new) }
        }
    }

    private func begin() {
        guard !started else { return }
        started = true
        if reduceMotion { shown = value; return }
        withAnimation(.easeOut(duration: duration)) { shown = value }
    }

    private func follow(_ new: Double) {
        if reduceMotion { shown = new; return }
        withAnimation(.easeOut(duration: duration)) { shown = new }
    }
}
