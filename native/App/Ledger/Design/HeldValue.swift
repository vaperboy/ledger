import SwiftUI

extension GameStore {
    var holdsHomeFigures: Bool {
        isAdvancing || reportSheet != nil || dailySheet != nil || !celebrationQueue.isEmpty || !unlockQueue.isEmpty
    }
}

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

struct RollingMoney: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var value: Double
    var format: (Double) -> String
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
