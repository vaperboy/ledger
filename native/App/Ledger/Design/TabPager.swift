import SwiftUI

final class PageSwipeGate {
    static let shared = PageSwipeGate()
    var touching = false
}

struct TabPager<Content: View>: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var content: (AppTab) -> Content

    @State private var width: CGFloat = 390
    @State private var settling = false

    private let tabs: [AppTab] = AppTab.allCases
    private let spring: Animation = Motion.moveAnimation
    private static var slide: CGFloat { 44 }

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
        .mask(Rectangle().ignoresSafeArea())
        .background(Theme.page.ignoresSafeArea())
        .animation(reduceMotion ? Motion.quickAnimation : spring, value: store.tab)
        .onChange(of: store.tab) { _, _ in
            settling = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(Motion.settleSeconds * 1_000_000_000))
                settling = false
            }
        }
    }

    private func page(_ t: AppTab, cur: Int) -> some View {
        let active: Bool = t == store.tab
        let side: CGFloat = CGFloat(max(-1, min(1, index(t) - cur)))
        return content(t)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(x: reduceMotion ? 0 : side * Self.slide)
            .opacity(active ? 1 : 0)
            .allowsHitTesting(active && !settling)
            .accessibilityHidden(!active)
            .environment(\.markerPageActive, active)
    }
}
