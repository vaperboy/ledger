import SwiftUI

/// Set while a horizontal control (a slider) is being touched: the tab pager never starts a page swipe then.
final class PageSwipeGate {
    static let shared = PageSwipeGate()
    var touching = false
}

/// What the segment rows of one tab page can still do, so the page swipe knows when a swipe belongs to a segment row.
/// The rule: a segment swipe wins while its row can move in that direction; at the first or last segment the page swipe takes over.
final class SegmentEdges {
    private var entries: [UUID: SegmentReach] = [:]
    func set(_ id: UUID, prev: Bool, next: Bool) { entries[id] = SegmentReach(prev: prev, next: next) }
    func remove(_ id: UUID) { entries[id] = nil }
    /// True when some segment row on this page can move that way (`towardsNext` is a swipe to the left).
    func canMove(towardsNext: Bool) -> Bool {
        for e in entries.values {
            if towardsNext && e.next { return true }
            if !towardsNext && e.prev { return true }
        }
        return false
    }
}

struct SegmentReach {
    var prev: Bool
    var next: Bool
}

/// One `SegmentEdges` per tab page.
final class SegmentEdgeBook {
    private var byTab: [AppTab: SegmentEdges] = [:]
    func edges(_ t: AppTab) -> SegmentEdges {
        if let e = byTab[t] { return e }
        let e = SegmentEdges()
        byTab[t] = e
        return e
    }
}

private struct SegmentEdgesKey: EnvironmentKey { static let defaultValue: SegmentEdges? = nil }
extension EnvironmentValues {
    var segmentEdges: SegmentEdges? {
        get { self[SegmentEdgesKey.self] }
        set { self[SegmentEdgesKey.self] = newValue }
    }
}

/// The five tabs side by side: the page moves out while the next one enters from the same side (a spring, no cross-fade, no scale).
/// All pages stay alive (each keeps its own stack and scroll place). Only the settled page takes touches. Under Reduce Motion the pages fade.
struct TabPager<Content: View>: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var content: (AppTab) -> Content

    @State private var width: CGFloat = 390
    @State private var dragX: CGFloat = 0
    @State private var mode: Int = 0            // 0 undecided, 1 page swipe, 2 not ours
    @State private var settling = false
    @State private var book = SegmentEdgeBook()

    private let tabs: [AppTab] = AppTab.allCases
    private let spring: Animation = .spring(response: 0.3, dampingFraction: 0.9)

    init(@ViewBuilder content: @escaping (AppTab) -> Content) { self.content = content }

    private func index(_ t: AppTab) -> Int { tabs.firstIndex(of: t) ?? 0 }
    private var dragging: Bool { mode == 1 }

    var body: some View {
        let cur: Int = index(store.tab)
        ZStack {
            ForEach(tabs) { (t: AppTab) in
                page(t, cur: cur)
            }
        }
        .background(GeometryReader { (g: GeometryProxy) in
            Color.clear
                .onAppear { width = g.size.width }
                .onChange(of: g.size.width) { _, w in width = w }
        })
        .clipped()
        .animation(reduceMotion ? .easeOut(duration: 0.2) : spring, value: store.tab)
        .simultaneousGesture(swipe)
        .onChange(of: store.tab) { _, _ in
            settling = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                settling = false
            }
        }
    }

    private func page(_ t: AppTab, cur: Int) -> some View {
        let active: Bool = t == store.tab
        let shift: CGFloat = CGFloat(index(t) - cur) * width + dragX
        return content(t)
            .environment(\.segmentEdges, book.edges(t))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(x: reduceMotion ? 0 : shift)
            .opacity(reduceMotion && !active ? 0 : 1)
            .allowsHitTesting(active && !dragging && !settling)
            .accessibilityHidden(!active)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .global)
            .onChanged { (v: DragGesture.Value) in
                if mode == 0 { mode = accepts(v) ? 1 : 2 }
                guard mode == 1 else { return }
                dragX = damped(v.translation.width)
            }
            .onEnded { (v: DragGesture.Value) in
                let wasOurs: Bool = mode == 1
                mode = 0
                guard wasOurs else { dragX = 0; return }
                finish(v)
            }
    }

    /// Only a clearly horizontal drag on a settled tab root, away from the back-swipe edge, away from sliders and segment rows.
    private func accepts(_ v: DragGesture.Value) -> Bool {
        let dx: CGFloat = v.translation.width
        let dy: CGFloat = v.translation.height
        guard !reduceMotion, !settling, !PageSwipeGate.shared.touching else { return false }
        guard store.depth(store.tab) == 0 else { return false }
        guard v.startLocation.x > 40, abs(dx) > abs(dy) * 2.5 else { return false }
        return !book.edges(store.tab).canMove(towardsNext: dx < 0)
    }

    /// Past the first or last page the drag resists.
    private func damped(_ dx: CGFloat) -> CGFloat {
        let i: Int = index(store.tab)
        if (dx > 0 && i == 0) || (dx < 0 && i == tabs.count - 1) { return dx * 0.25 }
        return dx
    }

    /// An interrupted drag settles on the nearest page and leaves `store.tab` consistent.
    private func finish(_ v: DragGesture.Value) {
        let dx: CGFloat = v.translation.width
        let predicted: CGFloat = v.predictedEndTranslation.width
        let far: Bool = abs(dx) > width * 0.33 || abs(predicted) > width * 0.6
        let step: Int = far ? (dx < 0 ? 1 : -1) : 0
        let target: Int = min(tabs.count - 1, max(0, index(store.tab) + step))
        withAnimation(spring) {
            dragX = 0
            if target != index(store.tab) { store.selectTab(tabs[target], resetRoot: false) }
        }
    }
}
