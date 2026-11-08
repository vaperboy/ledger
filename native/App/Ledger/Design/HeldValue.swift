import SwiftUI

extension GameStore {
    /// True while Home must keep showing the figures of the day before: a day is running, or a report, an ambition
    /// prompt or a queued reward is still waiting for its Continue. It is derived from the store, so it can never be left on.
    var holdsHomeFigures: Bool {
        isAdvancing || reportSheet != nil || ambitionPrompt || !celebrationQueue.isEmpty || !unlockQueue.isEmpty
    }
}

/// Shows the previous value while `store.holdsHomeFigures`, and the live value otherwise. When the hold ends the shown value changes
/// from the old to the new one, so `moneyFlash` inside `content` counts and flashes then (not under the report).
struct HeldValue<Content: View>: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.scenePhase) private var scenePhase
    var live: Double
    var content: (Double) -> Content
    @State private var held: Double?

    init(live: Double, @ViewBuilder content: @escaping (Double) -> Content) {
        self.live = live
        self.content = content
    }

    var body: some View {
        let blocked: Bool = store.holdsHomeFigures
        let shown: Double = blocked ? (held ?? live) : live
        content(shown)
            .onAppear { if held == nil { held = live } }
            .onChange(of: live) { _, new in if !store.holdsHomeFigures { held = new } }
            .onChange(of: blocked) { _, now in if !now { held = live } }
            .onChange(of: scenePhase) { _, phase in if phase == .active && !store.holdsHomeFigures { held = live } }
    }
}

/// Text of a money figure that counts from its previous value to the new one (a real interpolation, so every step shows). Reduce Motion
/// jumps straight to the new value. Used inside `HeldValue`, so the count starts when the report closes, not under it.
struct RollingMoney: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var value: Double
    var format: (Double) -> String
    @State private var shown: Double

    init(value: Double, format: @escaping (Double) -> String) {
        self.value = value
        self.format = format
        _shown = State(initialValue: value)
    }

    var body: some View {
        RollingText(value: shown, format: format)
            .onChange(of: value) { _, new in
                if reduceMotion { shown = new } else { withAnimation(.easeOut(duration: 1.1)) { shown = new } }
            }
    }
}

/// A `Text` whose number is the animated property: SwiftUI feeds it every in-between value while an animation runs.
private struct RollingText: View, Animatable {
    var value: Double
    var format: (Double) -> String
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View { Text(format(value)) }
}

extension View {
    /// Draws the view in from the left whenever `trigger` changes (not on the first appearance); Reduce Motion shows it at once.
    func revealOnChange<T: Equatable>(of trigger: T) -> some View { modifier(RevealOnChange(trigger: trigger)) }
}

private struct RevealOnChange<T: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var trigger: T
    @State private var progress: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .mask(alignment: .leading) { Rectangle().scaleEffect(x: max(progress, 0.001), y: 1, anchor: .leading) }
            .onChange(of: trigger) { _, _ in
                guard !reduceMotion else { return }
                progress = 0
                withAnimation(.easeOut(duration: 0.9)) { progress = 1 }
            }
    }
}
