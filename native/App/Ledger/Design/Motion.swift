import SwiftUI
import UIKit

enum Motion {
    static let tapAnimation: Animation = .easeOut(duration: 0.12)
    static let quickAnimation: Animation = .easeInOut(duration: 0.22)
    static let moveAnimation: Animation = .spring(response: 0.32, dampingFraction: 0.86)
    static let revealAnimation: Animation = .easeOut(duration: 0.6)
    static let pulseAnimation: Animation = .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
    static let sizeAnimation: Animation = .spring(response: 0.38, dampingFraction: 0.82)
    static let quickSeconds: Double = 0.22
    static let settleSeconds: Double = 0.3
    static let sheetLeaveSeconds: Double = 0.45
    static let hiddenScale: CGFloat = 0.94

    static let celebrateSeconds: Double = 1.5
    static let revealSeconds: Double = 0.6
    static let pulseSeconds: Double = 1.2

    static func animate<R>(_ animation: Animation?, _ body: () throws -> R) rethrows -> R {
        try SwiftUI.withAnimation(animation, body)
    }

    static func standard(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : quickAnimation }
    static func arrive(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : moveAnimation }
    static func tap(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : tapAnimation }
    static func quick(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : quickAnimation }
    static func move(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : moveAnimation }
    static func size(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : sizeAnimation }
    static func reveal(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : revealAnimation }
    static func run(_ reduceMotion: Bool, _ body: () -> Void) {
        if reduceMotion { body() } else { SwiftUI.withAnimation(quickAnimation, body) }
    }
}

struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(Motion.tap(reduceMotion), value: configuration.isPressed)
    }
}

final class SwipeBackDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = SwipeBackDelegate()

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if SwipeBackSteps.shared.stepIfAny() { return false }
        var responder: UIResponder? = gestureRecognizer.view
        while let r = responder {
            if let nav = r as? UINavigationController { return nav.viewControllers.count > 1 }
            responder = r.next
        }
        return false
    }
}

final class SwipeBackSteps {
    static let shared = SwipeBackSteps()
    private var entries: [(token: UUID, canStep: () -> Bool, step: () -> Void)] = []

    func set(_ token: UUID, canStep: @escaping () -> Bool, step: @escaping () -> Void) {
        entries.removeAll { $0.token == token }
        entries.append((token, canStep, step))
    }
    func remove(_ token: UUID) { entries.removeAll { $0.token == token } }

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
    func swipeBackEnabled(canStep: @escaping () -> Bool = { false }, step: @escaping () -> Void = {}) -> some View {
        background(SwipeBackHook(canStep: canStep, step: step).frame(width: 0, height: 0))
    }
}

extension View {
    func noSidewaysDrag() -> some View {
        scrollBounceBehavior(.basedOnSize, axes: .horizontal).clipped()
    }
}

struct MoneyFlash: ViewModifier {
    var value: Double
    @State private var flash: Int = 0
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

struct LiveFigure: View {
    var value: Double
    var text: String
    var body: some View {
        Text(text).monospacedDigit().moneyFlash(value)
    }
}

extension View {
    func moneyFlash(_ value: Double) -> some View { modifier(MoneyFlash(value: value)) }
    func pulseOnce(when trigger: Int) -> some View { modifier(PulseOnce(trigger: trigger)) }
}

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
