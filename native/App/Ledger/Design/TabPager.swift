import SwiftUI

/// Set while a horizontal control (a slider) is being touched: the tab pager never starts a page swipe then.
final class PageSwipeGate {
    static let shared = PageSwipeGate()
    var touching = false
}

/// The five tabs side by side: tapping a tab bar item slides the old page out while the new one enters from the same side (a spring of
/// about 0.3 s, no cross-fade, no scale). There is NO page swipe: tabs change only by tapping the tab bar; horizontal swipes belong to the
/// segment rows inside a page (`SegmentPager`). All pages stay alive (each keeps its own stack and scroll place). Only the settled page
/// takes touches. Under Reduce Motion the pages fade.
struct TabPager<Content: View>: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var content: (AppTab) -> Content

    @State private var width: CGFloat = 390
    @State private var settling = false

    private let tabs: [AppTab] = AppTab.allCases
    private let spring: Animation = .spring(response: 0.3, dampingFraction: 0.9)

    init(@ViewBuilder content: @escaping (AppTab) -> Content) { self.content = content }

    private func index(_ t: AppTab) -> Int { tabs.firstIndex(of: t) ?? 0 }

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
        // The mask reaches under the status bar, so the page colour is never cut off at the top safe area.
        .mask(Rectangle().ignoresSafeArea())
        .background(Theme.page.ignoresSafeArea())
        .animation(reduceMotion ? .easeOut(duration: 0.2) : spring, value: store.tab)
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
        let shift: CGFloat = CGFloat(index(t) - cur) * width
        return content(t)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(x: reduceMotion ? 0 : shift)
            .opacity(reduceMotion && !active ? 0 : 1)
            .allowsHitTesting(active && !settling)
            .accessibilityHidden(!active)
    }
}
