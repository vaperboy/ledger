import SwiftUI
import UIKit

/// Motion rules (Stage 8). Animations are restrained and used only where something meaningful changes (a figure moved, a sheet or
/// a reward appeared, a segment changed). Every site passes the environment's Reduce Motion flag through here, so the setting is
/// respected everywhere from one place. Pure functions: no screen state, nothing to keep in step.
enum Motion {
    // Under Reduce Motion the root view drops the animation of every transaction (`RootView`, `.transaction`), so the plain
    // `withAnimation` calls all over the app need no wrapper of their own.
    /// The ordinary short ease for a state change; nil when Reduce Motion is on.
    static func standard(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .easeInOut(duration: 0.22) }
    /// A calm spring for something that arrives (the reward popup); nil when Reduce Motion is on.
    static func arrive(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86) }
    /// Runs `body` with the standard animation, or at once when Reduce Motion is on.
    static func run(_ reduceMotion: Bool, _ body: () -> Void) {
        if reduceMotion { body() } else { SwiftUI.withAnimation(.easeInOut(duration: 0.22), body) }
    }
}

/// The one pressed state for rows, cards and chips: a calm dip in opacity while the finger is down (no movement, so a list never
/// jumps). Buttons that draw their own style (the filled Next day, outline buttons) keep it.
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
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

// MARK: Swipe between segments

/// Swipe left or right on a screen to move to the next or previous segment of its tab row. It is a simultaneous gesture that only
/// reacts to a clearly horizontal drag that does not start at the left edge (that is the back gesture), so vertical scrolling and
/// the back swipe are untouched.
struct SwipeBetweenSegments<T: Hashable>: ViewModifier {
    var items: [T]
    @Binding var selection: T
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 40, coordinateSpace: .local).onEnded { value in
                let dx: CGFloat = value.translation.width
                let dy: CGFloat = value.translation.height
                guard value.startLocation.x > 40, abs(dx) > 120, abs(dx) > abs(dy) * 3.2, abs(value.predictedEndTranslation.width) > 200 else { return }
                guard let i = items.firstIndex(of: selection) else { return }
                let next: Int = dx < 0 ? i + 1 : i - 1
                guard items.indices.contains(next) else { return }
                Motion.run(reduceMotion) { selection = items[next] }
                Haptics.choose()
            }
        )
    }
}

extension View {
    /// Swipe sideways to change the segment (see `SwipeBetweenSegments`).
    func swipeBetween<T: Hashable>(_ items: [T], selection: Binding<T>) -> some View {
        modifier(SwipeBetweenSegments(items: items, selection: selection))
    }
}
