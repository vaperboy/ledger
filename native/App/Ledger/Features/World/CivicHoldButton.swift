import SwiftUI

/// Press and hold to confirm something that cannot be undone. It reads on any palette (the shared hold button is white on a faint tint,
/// unreadable on a light page). Letting go early cancels; VoiceOver confirms with the default action.
struct CivicHoldButton: View {
    var title: String
    var tint: Color
    var ink: Color
    var duration: Double = 1.2
    var identifier: String = ""
    var action: () -> Void
    @State private var progress: CGFloat = 0
    @State private var done = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Capsule().fill(tint.opacity(0.16))
            GeometryReader { (g: GeometryProxy) in
                Capsule().fill(tint.opacity(0.5)).frame(width: max(0, g.size.width * progress))
            }
            .clipShape(Capsule())
            Text(done ? "Done" : "Hold to \(title)").font(.system(size: 17, weight: .semibold)).foregroundStyle(ink)
                .lineLimit(1).minimumScaleFactor(0.8).padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54)
        .overlay(Capsule().strokeBorder(tint, lineWidth: 1.5))
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration: duration, maximumDistance: 40, perform: complete, onPressingChanged: pressing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint("Press and hold to confirm. This cannot be undone.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { complete() }
        .accessibilityIdentifier(identifier)
    }

    private func pressing(_ down: Bool) {
        guard !done else { return }
        if down {
            Haptics.tap()
            withAnimation(reduceMotion ? nil : .linear(duration: duration)) { progress = 1 }
        } else {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { progress = 0 }
        }
    }

    private func complete() {
        guard !done else { return }
        done = true
        progress = 1
        Haptics.warning()
        action()
    }
}
