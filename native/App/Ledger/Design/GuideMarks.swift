import SwiftUI

/// The guide's mark: a short note on the far side of the screen from the control and, once the player has waited,
/// a pulsing ring and a pointing hand on the control. Nothing here takes a tap except Skip.
struct GuideMarkView: View {
    var mark: CoachMark
    var hole: CGRect
    var size: CGSize
    var position: Int
    var total: Int
    var pointing: Bool
    var onSkip: () -> Void

    var body: some View {
        let noteOnTop: Bool = hole.midY > size.height / 2
        ZStack {
            if pointing {
                GuidePointer(handAbove: hole.maxY > size.height - 160)
                    .frame(width: hole.width + 8, height: hole.height + 8)
                    .position(x: hole.midX, y: hole.midY)
            }
            note
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: noteOnTop ? .top : .bottom)
                .padding(noteOnTop ? .top : .bottom, noteOnTop ? Theme.Space.s : PillTabBar.height + Theme.Space.l)
        }
        .frame(width: size.width, height: size.height)
    }

    private var note: some View {
        HStack(alignment: .center, spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(mark.text).textStyle(.headline, tint: Theme.ink).fixedSize(horizontal: false, vertical: true)
                Text("\(position) of \(total)").textStyle(.caption, tint: Theme.inkFaint, numeric: true)
            }
            .allowsHitTesting(false)
            Spacer(minLength: Theme.Space.xs)
            Button { Haptics.tap(); onSkip() } label: { Text("Skip").frame(minWidth: 44, minHeight: 44) }
                .buttonStyle(PlainTextButtonStyle())
                .accessibilityIdentifier("coach-skip")
        }
        .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.surfaceRaised)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1))
                .allowsHitTesting(false)
        )
        .padding(.horizontal, Theme.Space.page)
        .frame(maxWidth: 520)
        .accessibilityElement(children: .contain)
    }
}

/// A pulsing ring with a pointing hand, drawn over a control. Plain shapes and one repeating animation; still with Reduce Motion or Low Power Mode.
struct GuidePointer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var handAbove: Bool = false
    @State private var on: Bool = false

    private var still: Bool { reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled }

    var body: some View {
        let moving: Bool = on && !still
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(Theme.accent, lineWidth: 3)
            .scaleEffect(moving ? 1.06 : 1)
            .opacity(moving ? 0.55 : 1)
            .overlay(alignment: handAbove ? .top : .bottom) {
                Image(systemName: handAbove ? "hand.point.down.fill" : "hand.point.up.fill")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Theme.ink)
                    .shadow(color: Color.black.opacity(0.5), radius: 2, y: 1)
                    .offset(y: (handAbove ? -1 : 1) * (moving ? 30 : 22))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard !still else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

/// Points at a control inside a popup when the guide's step has waited on it for a while.
private struct GuideHint: ViewModifier {
    var active: Bool
    var key: String
    @State private var shown: String = ""

    func body(content: Content) -> some View {
        content
            .overlay {
                if active && shown == key { GuidePointer(handAbove: true).padding(-4) }
            }
            .task(id: active ? key : "") {
                shown = ""
                guard active else { return }
                try? await Task.sleep(nanoseconds: GuideTiming.idleNanos)
                if !Task.isCancelled { shown = key }
            }
    }
}

enum GuideTiming {
    /// How long the guide waits before pointing at the control.
    static let idleNanos: UInt64 = 5_000_000_000
    /// A short settle after the screen changes, so the note does not flash during transitions.
    static let settleNanos: UInt64 = 300_000_000
}

extension View {
    func guideHint(_ active: Bool, key: String) -> some View { modifier(GuideHint(active: active, key: key)) }
}
