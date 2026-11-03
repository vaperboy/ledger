import SwiftUI

/// The one container for every page with its own tab / segment row. Native paging (`TabView` page style): the content follows the finger
/// sideways, slides to the next or previous tab, and a tap on the row slides in the proper direction. No cross-fade. Each page keeps its
/// own vertical scroll, so the pager sits OUTSIDE the per-page ScrollView: the tab row stays fixed above, the pager fills the rest.
/// Keep horizontal scrollers (chip rows) in the fixed header, never inside a page.
struct SegmentPager<T: Hashable, Content: View>: View {
    var items: [T]
    @Binding var selection: T
    var content: (T) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.markerPageActive) private var outerActive

    init(items: [T], selection: Binding<T>, @ViewBuilder content: @escaping (T) -> Content) {
        self.items = items
        self._selection = selection
        self.content = content
    }

    var body: some View {
        let anim: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.25)
        TabView(selection: $selection) {
            ForEach(items, id: \.self) { (item: T) in
                content(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .environment(\.markerPageActive, outerActive && item == selection)
                    .tag(item)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(anim, value: selection)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
