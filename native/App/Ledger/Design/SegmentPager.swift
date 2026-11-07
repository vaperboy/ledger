import SwiftUI

/// The one container for every page with its own tab / segment row. Native paging (`TabView` page style): the content follows the finger
/// sideways, slides to the next or previous tab, and a tap on the row slides in the proper direction. No cross-fade. Each page keeps its
/// own vertical scroll, so the pager sits OUTSIDE the per-page ScrollView: the tab row stays fixed above, the pager fills the rest.
/// Keep horizontal scrollers (chip rows) in the fixed header, never inside a page.
/// `.swipePaging(false)` (pages with sliders): no swipe; a tap on the row still slides the page in. All pages are then built at once.
struct SegmentPager<T: Hashable, Content: View>: View {
    var items: [T]
    @Binding var selection: T
    var content: (T) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.markerPageActive) private var outerActive
    private var swipes = true

    init(items: [T], selection: Binding<T>, @ViewBuilder content: @escaping (T) -> Content) {
        self.items = items
        self._selection = selection
        self.content = content
    }

    /// Turns the sideways swipe between pages off (default on), so a drag on a slider never turns the page.
    func swipePaging(_ on: Bool) -> SegmentPager {
        var c: SegmentPager = self
        c.swipes = on
        return c
    }

    var body: some View {
        if swipes { paged } else { tapOnly }
    }

    private var paged: some View {
        let anim: Animation? = reduceMotion ? nil : Motion.quickAnimation
        return TabView(selection: $selection) {
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

    /// The pages side by side, offset by the selection: the same sideways slide on a tap, no swipe gesture.
    private var tapOnly: some View {
        let anim: Animation? = reduceMotion ? nil : Motion.quickAnimation
        let cur: Int = items.firstIndex(of: selection) ?? 0
        return GeometryReader { (geo: GeometryProxy) in
            let w: CGFloat = geo.size.width
            ZStack(alignment: .top) {
                ForEach(Array(items.enumerated()), id: \.element) { (pair: (offset: Int, element: T)) in
                    let on: Bool = pair.element == selection
                    content(pair.element)
                        .frame(width: w, height: geo.size.height, alignment: .top)
                        .offset(x: reduceMotion ? 0 : CGFloat(pair.offset - cur) * w)
                        .opacity(reduceMotion && !on ? 0 : 1)
                        .allowsHitTesting(on)
                        .accessibilityHidden(!on)
                        .environment(\.markerPageActive, outerActive && on)
                }
            }
            .frame(width: w, height: geo.size.height, alignment: .top)
            .clipped()
        }
        .animation(anim, value: selection)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
