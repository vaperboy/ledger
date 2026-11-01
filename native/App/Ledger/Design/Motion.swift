import SwiftUI
import UIKit

/// Motion rules (Stage 8). Animations are restrained and used only where something meaningful changes (a figure moved, a sheet or
/// a reward appeared, a segment changed). Every site passes the environment's Reduce Motion flag through here, so the setting is
/// respected everywhere from one place. Pure functions: no screen state, nothing to keep in step.
enum Motion {
    /// Mirrors the system Reduce Motion setting. The root view keeps it current (`RootView`), so `withAnimation` below, which every
    /// screen already calls, skips its animation when the player asked for less motion.
    static var reduceFlag = false
    /// The ordinary short ease for a state change; nil when Reduce Motion is on.
    static func standard(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .easeInOut(duration: 0.22) }
    /// A calm spring for something that arrives (the reward popup); nil when Reduce Motion is on.
    static func arrive(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86) }
    /// Runs `body` with the standard animation, or at once when Reduce Motion is on.
    static func run(_ reduceMotion: Bool, _ body: () -> Void) {
        if reduceMotion { body() } else { SwiftUI.withAnimation(.easeInOut(duration: 0.22), body) }
    }
}

/// Shadows SwiftUI's `withAnimation` inside the app: the same call, but the change is applied at once when Reduce Motion is on.
func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
    if Motion.reduceFlag { return try body() }
    return try SwiftUI.withAnimation(animation, body)
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
/// brings it back, for every navigation stack in the app (Home, Team, Group, Projects and the Phone apps).
extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
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
            DragGesture(minimumDistance: 28, coordinateSpace: .local).onEnded { value in
                let dx: CGFloat = value.translation.width
                let dy: CGFloat = value.translation.height
                guard value.startLocation.x > 32, abs(dx) > 70, abs(dx) > abs(dy) * 2.2 else { return }
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
