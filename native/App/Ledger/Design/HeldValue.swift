import SwiftUI

extension GameStore {
    /// True while Home must keep showing the figures of the day before: a day is running, or a report, the daily report, an ambition
    /// prompt or a queued reward is still waiting for its Continue. It is derived from the store, so it can never be left on.
    var holdsHomeFigures: Bool {
        isAdvancing || reportSheet != nil || dailySheet != nil || ambitionPrompt || !celebrationQueue.isEmpty || !unlockQueue.isEmpty
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

/// Text of a money figure whose digits roll when it changes: only the digits that differ scroll, upward and tinted green for a rise, downward
/// and red for a fall, and the tint fades back to the surrounding colour while the old digits leave. Reduce Motion skips the roll and keeps
/// the colour flash only. Used inside `HeldValue`, so the roll starts when the report closes, not under it.
struct RollingMoney: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var value: Double
    var format: (Double) -> String
    /// False for a figure that is a cost or loss shown without its sign: a rise is then bad news (red).
    var betterWhenHigher: Bool = true
    @State private var shown: Double
    @State private var falling: Bool = false
    @State private var flash: Color = Theme.gain
    @State private var flashAmount: Double = 0

    init(value: Double, betterWhenHigher: Bool = true, format: @escaping (Double) -> String) {
        self.value = value
        self.betterWhenHigher = betterWhenHigher
        self.format = format
        _shown = State(initialValue: value)
    }

    var body: some View {
        Text(format(shown)).monospacedDigit()
            .overlay { Text(format(shown)).monospacedDigit().foregroundStyle(flash).opacity(flashAmount).allowsHitTesting(false) }
            .contentTransition(reduceMotion ? .identity : .numericText(countsDown: falling))
            .onChange(of: value) { old, new in
                guard abs(new - old) > 0.0001 else { return }
                falling = new < old
                flash = (falling != betterWhenHigher) ? Theme.gain : Theme.loss
                flashAmount = 1
                if reduceMotion {
                    shown = new
                    withAnimation(.linear(duration: 0.8)) { flashAmount = 0 }
                } else {
                    withAnimation(.easeOut(duration: 0.7)) { shown = new }
                    withAnimation(.easeOut(duration: 1.6).delay(0.3)) { flashAmount = 0 }
                }
            }
    }
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
