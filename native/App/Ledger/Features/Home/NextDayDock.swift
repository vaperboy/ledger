import SwiftUI
import Simulation

/// The floating Next day control at the bottom right of Home, above the tab bar: a 56 pt pill (tap: one day), a small chevron beside it
/// (or a press and hold on the pill) that opens a chip with "Skip week", and during Skip week the pill turns into Stop. A thin accent
/// ring runs round the pill while a day plays (the share of the week while the week plays). Home keeps `reserve` points clear for it.
struct NextDayDock: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var engine: GameEngine
    @State private var menuOpen = false
    @State private var longPressed = false
    @State private var dayRing: Double = 0

    /// Pill height; the dock never draws taller than this except for the open Skip week chip.
    static let height: CGFloat = 56
    /// Height Home keeps clear at the bottom: the pill and a gap above the tab bar's own clearance.
    static let reserve: CGFloat = height + Theme.Space.s

    private var over: Bool { engine.state.isGameOver }
    private var blockID: Int? { store.blockingMessageID }
    private var canSkip: Bool { !over && !store.isAdvancing && blockID == nil && store.reportSheet == nil }

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Space.s) {
            if menuOpen && !store.playingWeek { skipChip.transition(.opacity.combined(with: .move(edge: .bottom))) }
            HStack(spacing: Theme.Space.s) {
                if !store.playingWeek { moreButton }
                pill
            }
        }
        .animation(Motion.quick(reduceMotion), value: menuOpen)
        .animation(Motion.quick(reduceMotion), value: store.playingWeek)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, Theme.Space.page)
        .task(id: menuOpen) {
            guard menuOpen else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            menuOpen = false
        }
        .onChange(of: store.isAdvancing) { _, running in
            guard running, !store.playingWeek else { return }
            // A single day takes about 0.35 s: the ring fills over that time (at once under Reduce Motion).
            dayRing = 0
            if reduceMotion { dayRing = 1 } else { withAnimation(.linear(duration: 0.35)) { dayRing = 1 } }
        }
    }

    // MARK: Pill

    private var pill: some View {
        let busy: Bool = store.isAdvancing
        let playing: Bool = store.playingWeek
        let day: Int = min(7, engine.state.day + 1)
        let title: String = over ? "Game over" : playing ? "Stop" : busy ? "Running" : blockID != nil ? "Answer first" : "Next day"
        let caption: String = "Day \(day) of 7"
        let fraction: Double = playing ? Double(day) / 7 : busy ? dayRing : 0
        return Button {
            if longPressed { longPressed = false; return }
            Haptics.tap()
            menuOpen = false
            if playing { store.stopPlayingWeek() }
            else if let id = blockID { store.openApp(.inbox, request: .message(id)) }
            else { store.nextDay() }
        } label: {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: playing ? "stop.fill" : "play.fill").font(.callout.weight(.bold)).foregroundStyle(Theme.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).textStyle(.headline, tint: Theme.ink).lineLimit(1)
                    Text(caption).textStyle(.caption, tint: Theme.inkSoft, numeric: true).lineLimit(1)
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .frame(minWidth: Self.height, minHeight: Self.height)
            .background(Capsule().fill(Theme.surfaceRaised))
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
        .disabled(over || (!playing && (busy || (blockID == nil && store.reportSheet != nil))))
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
            guard canSkip else { return }
            longPressed = true
            Haptics.tap()
            menuOpen = true
        })
        .accessibilityLabel(title)
        .accessibilityValue(caption)
        .accessibilityIdentifier(playing ? "stop-week" : "next-day")
        .accessibilityAction(named: "Skip week") { if canSkip { store.playToEndOfWeek() } }
    }

    // MARK: Menu

    private var moreButton: some View {
        Button { Haptics.tap(); menuOpen.toggle() } label: {
            Image(systemName: "chevron.up").font(.footnote.weight(.bold)).foregroundStyle(Theme.inkSoft)
                .rotationEffect(.degrees(menuOpen ? 180 : 0))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.surfaceRaised))
                .overlay(Circle().strokeBorder(Theme.lineStrong, lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .disabled(over)
        .accessibilityLabel(menuOpen ? "Hide options" : "More options")
        .accessibilityIdentifier("skip-menu")
    }

    private var skipChip: some View {
        Button {
            Haptics.tap()
            menuOpen = false
            store.playToEndOfWeek()
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Text("Skip week").textStyle(.body, tint: Theme.ink, weight: .semibold)
                Image(systemName: "forward.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent).accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Space.l)
            .frame(minHeight: 44)
            .background(Capsule().fill(Theme.surfaceRaised))
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(!canSkip)
        .accessibilityLabel("Skip week")
        .accessibilityIdentifier("play-week")
    }
}
