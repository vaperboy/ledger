import SwiftUI

final class PageSwipeGate {
    static let shared = PageSwipeGate()
    var touching = false
}

/// Shows only the selected main tab. Hidden tabs are not kept alive, so a store change redraws one tab, not five.
/// Each tab's navigation path lives in the store, so nothing is lost when a tab is rebuilt.
struct TabPager<Content: View>: View {
    @EnvironmentObject var store: GameStore
    var content: (AppTab) -> Content

    init(@ViewBuilder content: @escaping (AppTab) -> Content) { self.content = content }

    var body: some View {
        let tab: AppTab = store.tab
        content(tab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.markerPageActive, true)
            .id(tab)
            .onAppear { TabSwitchTimer.end(tab) }
            .background(Theme.page.ignoresSafeArea())
    }
}
