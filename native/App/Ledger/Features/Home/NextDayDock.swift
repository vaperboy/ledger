import SwiftUI
import Simulation

/// The floating Next day control at the bottom right of Home: a 56 pt glass pill that advances one day, with a thin accent ring that runs
/// round it while the day plays. It is attached inside the page's tab bar clearance (see `CompaniesView`), so it sits above the tab bar
/// by `gap`; Home keeps `reserve` points clear for it.
struct NextDayDock: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var engine: GameEngine
    @State private var dayRing: Double = 0

    static let height: CGFloat = 56
    /// Space between the pill and the tab bar (or the screen's bottom edge where there is no bar).
    static let gap: CGFloat = Theme.Space.m
    /// Height Home keeps clear at the bottom: the pill and its gap, on top of the tab bar's own clearance.
    static let reserve: CGFloat = height + gap

    private var over: Bool { engine.state.isGameOver }
    private var blockID: Int? { store.blockingMessageID }

    var body: some View {
        HStack(spacing: Theme.Space.s) { storeButton; pill }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, Theme.Space.page)
            .onChange(of: store.isAdvancing) { _, running in
                guard running else { return }
                // A single day takes about 0.35 s: the ring fills over that time (at once under Reduce Motion).
                dayRing = 0
                if reduceMotion { dayRing = 1 } else { withAnimation(.linear(duration: 0.35)) { dayRing = 1 } }
            }
    }

    private var storeButton: some View {
        Button {
            Haptics.tap()
            store.openApp(.store)
        } label: {
            LedgerGlyph(glyph: PhoneApp.store.glyph, size: Theme.Icon.medium, tint: PhoneApp.store.tint)
                .frame(width: 44, height: 44)
                .glassCapsule()
                .overlay(Circle().strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Store")
        .accessibilityIdentifier("home-store")
    }

    private var pill: some View {
        let busy: Bool = store.isAdvancing
        let day: Int = min(7, engine.state.day + 1)
        let title: String = over ? "Game over" : busy ? "Running" : blockID != nil ? "Answer first" : "Next day"
        let caption: String = "Day \(day) of 7"
        let fraction: Double = busy ? dayRing : 0
        return Button {
            Haptics.tap()
            if let id = blockID { store.openApp(.inbox, request: .message(id)) }
            else { store.nextDay() }
        } label: {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "play.fill").font(.callout.weight(.bold)).foregroundStyle(Theme.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).textStyle(.headline, tint: Theme.ink).lineLimit(1)
                    Text(caption).textStyle(.caption, tint: Theme.inkSoft, numeric: true).lineLimit(1)
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .frame(minWidth: Self.height, minHeight: Self.height)
            .glassCapsule()
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1.5))
            .overlay(
                Capsule().trim(from: 0, to: fraction)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .opacity(fraction > 0 ? 1 : 0)
                    .animation(Motion.quick(reduceMotion), value: fraction)
            )
            .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .coachAnchor(.nextDay)
        .disabled(over || (busy || (blockID == nil && store.reportSheet != nil)))
        .accessibilityLabel(title)
        .accessibilityValue(caption)
        .accessibilityIdentifier("next-day")
    }
}
