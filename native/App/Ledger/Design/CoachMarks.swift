import SwiftUI

/// The one-time "seen" flags of first-run help (tour, tab tip, phone app sheets), kept per install in UserDefaults.
enum FirstRunFlags {
    static let tour = "firstRun.tour"
    static let customTabTip = "firstRun.customTabTip"
    static func appHelp(_ appID: String) -> String { "firstRun.appHelp." + appID }

    static func seen(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
    static func mark(_ key: String) { UserDefaults.standard.set(true, forKey: key) }
}

/// A place on screen a coach mark can point at.
enum CoachStop: Hashable { case nextDay, happened, needsYou, phoneTab }

/// Collects the bounds of every view tagged with `coachAnchor`, so one overlay higher up can cut a hole around any of them.
struct CoachAnchorKey: PreferenceKey {
    static let defaultValue: [CoachStop: Anchor<CGRect>] = [:]
    static func reduce(value: inout [CoachStop: Anchor<CGRect>], nextValue: () -> [CoachStop: Anchor<CGRect>]) {
        value.merge(nextValue()) { (_: Anchor<CGRect>, new: Anchor<CGRect>) -> Anchor<CGRect> in new }
    }
}

extension View {
    /// Marks this view's bounds as the place `stop` points at (no effect when `enabled` is false).
    func coachAnchor(_ stop: CoachStop, enabled: Bool = true) -> some View {
        anchorPreference(key: CoachAnchorKey.self, value: .bounds) { (a: Anchor<CGRect>) -> [CoachStop: Anchor<CGRect>] in
            enabled ? [stop: a] : [:]
        }
    }
}

/// One mark of a tour: where it points, its sentence, whether a tap on the highlighted view reaches it (the step is done by using it)
/// and the label of the button that moves on (empty: the step ends by itself).
struct CoachMark: Equatable {
    var stop: CoachStop
    var text: String
    var passThrough: Bool = false
    var button: String = "Next"
}

/// A dimmed screen with a cut-out around the view the current mark points at, and a small card with one sentence, the step count and Skip.
/// The host owns the step and decides when to show it (`visible`); under Reduce Motion nothing moves or fades.
struct CoachMarks: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var marks: [CoachMark]
    var anchors: [CoachStop: Anchor<CGRect>]
    var step: Int
    var visible: Bool
    var onNext: () -> Void
    var onSkip: () -> Void

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            if visible, step < marks.count, let anchor = anchors[marks[step].stop] {
                let mark: CoachMark = marks[step]
                let hole: CGRect = geo[anchor].insetBy(dx: -6, dy: -6)
                ZStack {
                    dim(size: geo.size, hole: hole, passThrough: mark.passThrough)
                    ring(hole)
                    callout(mark, hole: hole, size: geo.size)
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.quick(reduceMotion), value: visible)
        .animation(Motion.quick(reduceMotion), value: step)
    }

    private func dim(size: CGSize, hole: CGRect, passThrough: Bool) -> some View {
        var path = Path(CGRect(origin: .zero, size: size))
        path.addRoundedRect(in: hole, cornerSize: CGSize(width: Theme.Radius.card, height: Theme.Radius.card))
        // The hole lets taps through only when the step is done by using the highlighted view.
        let hit: Path = passThrough ? path : Path(CGRect(origin: .zero, size: size))
        return path.fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
            .contentShape(hit, eoFill: true)
            .onTapGesture { }
            .accessibilityHidden(true)
    }

    private func ring(_ hole: CGRect) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(Theme.accent, lineWidth: 2)
            .frame(width: hole.width, height: hole.height)
            .position(x: hole.midX, y: hole.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func callout(_ mark: CoachMark, hole: CGRect, size: CGSize) -> some View {
        let above: Bool = hole.midY > size.height / 2
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(mark.text).textStyle(.headline, tint: Theme.ink).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Space.s) {
                Text("\(step + 1) of \(marks.count)").textStyle(.caption, tint: Theme.inkFaint, numeric: true)
                Spacer(minLength: Theme.Space.s)
                Button { Haptics.tap(); onSkip() } label: { Text("Skip") }
                    .buttonStyle(PlainTextButtonStyle()).accessibilityIdentifier("coach-skip")
                if !mark.button.isEmpty {
                    Button { Haptics.tap(); onNext() } label: { Text(mark.button) }
                        .buttonStyle(PrimaryButtonStyle(size: .compact)).accessibilityIdentifier("coach-next")
                }
            }
        }
        .padding(Theme.Space.l)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surfaceRaised))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1))
        .padding(.horizontal, Theme.Space.page)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: above ? .bottom : .top)
        .padding(above ? .bottom : .top, above ? size.height - hole.minY + Theme.Space.m : hole.maxY + Theme.Space.m)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}
