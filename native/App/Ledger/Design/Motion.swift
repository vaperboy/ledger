import SwiftUI
import UIKit

/// Motion rules. Animations are restrained and used only where something meaningful changes (a figure moved, a sheet or
/// a reward appeared, a segment changed). Every site passes the environment's Reduce Motion flag through here, so the setting is
/// respected everywhere from one place. Pure functions: no screen state, nothing to keep in step.
enum Motion {
    // Every duration and curve of the app lives here and nowhere else. Under Reduce Motion the root view drops the animation of
    // every transaction (`RootView`, `.transaction`), so the plain constants need no wrapper of their own at the call site.
    /// `tap`: button press, 0.12 s ease-out.
    static let tapAnimation: Animation = .easeOut(duration: 0.12)
    /// `quick`: toggles, row expand, pill changes, 0.22 s ease-in-out.
    static let quickAnimation: Animation = .easeInOut(duration: 0.22)
    /// `move`: sheets and cards sliding, section reorder, spring(response 0.32, damping 0.86).
    static let moveAnimation: Animation = .spring(response: 0.32, dampingFraction: 0.86)
    /// `reveal`: counting numbers and bar growth in reports, 0.6 s ease-out.
    static let revealAnimation: Animation = .easeOut(duration: 0.6)
    /// `pulse`: 1.2 s cycle (0.6 s each way), opacity 1.0 to 0.6, for the unpressed primary action and a new `Needs you` item.
    static let pulseAnimation: Animation = .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
    /// `size`: a popup changing size or class as its content changes, a slightly bouncier spring than `move`.
    static let sizeAnimation: Animation = .spring(response: 0.38, dampingFraction: 0.82)
    /// Seconds the banner layer waits before the next banner, how long a swiped banner takes to leave, and how long a toast stays.
    static let bannerGapSeconds: Double = 0.45
    static let bannerLeaveSeconds: Double = 0.19
    static let toastSeconds: Double = 3.5
    /// The gap before a toast (shorter than a banner's: a toast answers the tap just made).
    static let toastGapSeconds: Double = 0.05
    /// How long a `quick` change takes (a bump holds this long before it settles back).
    static let quickSeconds: Double = 0.22
    /// When a `move` spring has visibly settled (a page slide finishes, taps are taken again).
    static let settleSeconds: Double = 0.3
    /// How long a closing sheet takes to leave, so what opens next is not lost to its dismissal.
    static let sheetLeaveSeconds: Double = 0.45
    /// The size a waiting (not visible) confirmation sits at, and the one a scale-in confirmation starts from.
    static let hiddenScale: CGFloat = 0.94

    /// One entrance/exit per kind of popup. Confirm and decision: scale and fade. Panel and report: slide up from the bottom (the
    /// `move` spring comes from the host's animation). Toast: slide down from the top and fade. Reduce Motion: a plain fade.
    static func confirmTransition(_ reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: hiddenScale).combined(with: .opacity)
    }
    static func panelTransition(_ reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }
    static func toastTransition(_ reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }
    /// `celebrate`: goal complete, record line, 1.5 s in total.
    static let celebrateSeconds: Double = 1.5
    static let revealSeconds: Double = 0.6
    /// `pulse`: 1.2 s cycle.
    static let pulseSeconds: Double = 1.2

    /// Runs `body` with an animation (one of the constants above). The only door to `withAnimation` in the app.
    static func animate<R>(_ animation: Animation?, _ body: () throws -> R) rethrows -> R {
        try SwiftUI.withAnimation(animation, body)
    }

    /// The ordinary short ease for a state change; nil when Reduce Motion is on.
    static func standard(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : quickAnimation }
    /// A calm spring for something that arrives (the reward popup); nil when Reduce Motion is on.
    static func arrive(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : moveAnimation }
    /// `tap`; nil when Reduce Motion is on.
    static func tap(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : tapAnimation }
    /// `quick`; nil when Reduce Motion is on.
    static func quick(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : quickAnimation }
    /// `move`; nil when Reduce Motion is on.
    static func move(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : moveAnimation }
    /// `size`; nil when Reduce Motion is on.
    static func size(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : sizeAnimation }
    /// `reveal`; nil when Reduce Motion is on.
    static func reveal(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : revealAnimation }
    /// Runs `body` with the quick animation, or at once when Reduce Motion is on.
    static func run(_ reduceMotion: Bool, _ body: () -> Void) {
        if reduceMotion { body() } else { SwiftUI.withAnimation(quickAnimation, body) }
    }
}

/// The one pressed state for rows, cards and chips: a calm dip in opacity while the finger is down (no movement, so a list never
/// jumps). Buttons that draw their own style (the filled Next day, outline buttons) keep it.
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(Motion.tap(reduceMotion), value: configuration.isPressed)
    }
}

// MARK: Swipe back

/// Swipe from the left edge goes back on every pushed screen. The app hides the system back button (it draws its own round one),
/// and UIKit then turns the edge gesture off; giving the gesture a delegate that allows it whenever there is a screen to go back to
/// brings it back. `swipeBackEnabled()` is applied by the shared screen chrome (`AppScreen`, `OutsideScreen`, the Bank and Accounting
/// apps), so it covers every pushed screen. No method override: a background view controller finds its navigation controller.
final class SwipeBackDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = SwipeBackDelegate()

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // A screen with its own in-app Back (a Phone app on an inner page) steps back itself; only at its root does the swipe leave.
        if SwipeBackSteps.shared.stepIfAny() { return false }
        var responder: UIResponder? = gestureRecognizer.view
        while let r = responder {
            if let nav = r as? UINavigationController { return nav.viewControllers.count > 1 }
            responder = r.next
        }
        return false
    }
}

/// The in-app "step back" of the screens on show (a Phone app with its own Back button): the newest one that can step wins. A hook
/// adds itself when its screen appears and leaves when it goes, so a screen that is covered or closed never answers the swipe.
final class SwipeBackSteps {
    static let shared = SwipeBackSteps()
    private var entries: [(token: UUID, canStep: () -> Bool, step: () -> Void)] = []

    func set(_ token: UUID, canStep: @escaping () -> Bool, step: @escaping () -> Void) {
        entries.removeAll { $0.token == token }
        entries.append((token, canStep, step))
    }
    func remove(_ token: UUID) { entries.removeAll { $0.token == token } }

    /// Runs the newest step back that applies (after the gesture has been refused) and says whether one did.
    func stepIfAny() -> Bool {
        guard let entry = entries.last(where: { $0.canStep() }) else { return false }
        DispatchQueue.main.async { entry.step() }
        return true
    }
}

private final class SwipeBackHookController: UIViewController {
    let token = UUID()
    var canStep: () -> Bool = { false }
    var step: () -> Void = {}

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.interactivePopGestureRecognizer?.delegate = SwipeBackDelegate.shared
        register()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        SwipeBackSteps.shared.remove(token)
    }
    func register() {
        guard viewIfLoaded?.window != nil else { return }
        SwipeBackSteps.shared.set(token, canStep: canStep, step: step)
    }
}

private struct SwipeBackHook: UIViewControllerRepresentable {
    var canStep: () -> Bool
    var step: () -> Void
    func makeUIViewController(context: Context) -> UIViewController {
        let c = SwipeBackHookController()
        c.canStep = canStep; c.step = step
        return c
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard let c = uiViewController as? SwipeBackHookController else { return }
        c.canStep = canStep; c.step = step
        c.register()
    }
}

extension View {
    /// Keeps the left-edge swipe-back working on a screen whose system back button is hidden. A screen with its own in-app Back
    /// passes `canStep` (true while it is on an inner page) and `step` (the very same action its Back button runs): the edge swipe
    /// then steps back inside the app, and leaves the app only from its root.
    func swipeBackEnabled(canStep: @escaping () -> Bool = { false }, step: @escaping () -> Void = {}) -> some View {
        background(SwipeBackHook(canStep: canStep, step: step).frame(width: 0, height: 0))
    }
}

/// A full page or popup presented over the app arrives with a calm fade and a slight scale (0.97 to 1), not a slide from the bottom.
/// Under Reduce Motion it simply appears.
struct PageArrive: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.97)
            .onAppear {
                if reduceMotion { shown = true } else { SwiftUI.withAnimation(Motion.moveAnimation) { shown = true } }
            }
    }
}

extension View {
    /// Fade plus slight scale on arrival for full-page presentations (see `PageArrive`).
    func pageArrive() -> some View { modifier(PageArrive()) }
    /// A vertical scroll container that never bounces or drags sideways and clips anything wider than itself.
    func noSidewaysDrag() -> some View {
        scrollBounceBehavior(.basedOnSize, axes: .horizontal).clipped()
    }
}

// MARK: Counting numbers

/// A money figure that rolls to its new value and flashes `Theme.gain` (rose) or `Theme.loss` (fell) for 0.3 s, then settles
/// back to its own colour. The first appearance never flashes. Reduce Motion: no roll, only the colour flash.
struct MoneyFlash: ViewModifier {
    var value: Double
    @State private var flash: Int = 0          // 1 rose, -1 fell, 0 idle
    @State private var token: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let tint: Color = flash > 0 ? Theme.gain : Theme.loss
        content
            .contentTransition(reduceMotion ? .identity : .numericText(value: value))
            .animation(Motion.reveal(reduceMotion), value: value)
            .overlay(Rectangle().fill(tint).opacity(flash == 0 ? 0 : 1).blendMode(.sourceAtop))
            .compositingGroup()
            .animation(Motion.revealAnimation, value: flash)
            .onChange(of: value) { old, new in
                guard new != old else { return }
                flash = new > old ? 1 : -1
                token += 1
                let mine: Int = token
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if mine == token { flash = 0 }
                }
            }
    }
}

/// A text figure that rolls and flashes when its value changes (see `MoneyFlash`).
struct LiveFigure: View {
    var value: Double
    var text: String
    var body: some View {
        Text(text).monospacedDigit().moneyFlash(value)
    }
}

extension View {
    /// Rolls the figure and flashes it green (up) or red (down) when `value` changes.
    func moneyFlash(_ value: Double) -> some View { modifier(MoneyFlash(value: value)) }
    /// Pulses once when `trigger` rises: a new `Needs you` item. Reduce Motion: a 2 pt accent border for a moment.
    func pulseOnce(when trigger: Int) -> some View { modifier(PulseOnce(trigger: trigger)) }
}

/// One `pulse` cycle on a new `Needs you` item (opacity 1.0 to 0.6 and back); under Reduce Motion a static 2 pt accent border instead.
struct PulseOnce: ViewModifier {
    var trigger: Int
    @State private var dim = false
    @State private var marked = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(dim ? 0.6 : 1)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.gold, lineWidth: 2).opacity(marked ? 1 : 0).allowsHitTesting(false))
            .onChange(of: trigger) { old, new in
                guard new > old else { return }
                Task { @MainActor in await run() }
            }
    }

    private func run() async {
        if reduceMotion {
            marked = true
            try? await Task.sleep(nanoseconds: UInt64(Motion.pulseSeconds * 1_000_000_000))
            marked = false
            return
        }
        Motion.animate(Motion.pulseAnimation) { dim = true }
        try? await Task.sleep(nanoseconds: UInt64(Motion.pulseSeconds * 1_000_000_000))
        Motion.animate(Motion.quickAnimation) { dim = false }
    }
}

