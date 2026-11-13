import SwiftUI

/// Sub-tabs as pages: swipe left or right to move between them, and the segmented control above stays in step
/// because both share the same selection.
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

    var body: some View {
        if swipes { paged } else { tapOnly }
    }

    private var paged: some View {
        let anim: Animation? = Motion.quick(reduceMotion)
        return TabView(selection: $selection) {
            ForEach(items, id: \.self) { (item: T) in
                content(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .environment(\.markerPageActive, outerActive && item == selection)
                    .accessibilityHidden(item != selection)
                    .tag(item)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(anim, value: selection)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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
