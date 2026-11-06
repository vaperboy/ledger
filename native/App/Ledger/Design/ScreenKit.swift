import SwiftUI

// The page containers every screen uses:
//   FixedScreen      A  fixed, never scrolls; compacts to fit (scales down to `minScale`), clipped
//   ScrollScreen     B  vertical scroll only when the content is taller than the screen, never sideways, no blank space
// Class C (intentional horizontal chip rows, e.g. TechPro) is a horizontal ScrollView inside one of these.

private struct FixedHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A vertical scroll page: bounces only when the content is taller, cannot be dragged sideways, content pinned to the screen width.
/// The tab bar clearance comes from `ledgerBackground()` (a bottom safe-area inset), so the last row always clears the bar.
struct ScrollScreen<Content: View>: View {
    var spacing: CGFloat = 12
    var top: CGFloat = 6
    var bottom: CGFloat = 24
    var maxWidth: CGFloat = 760
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: spacing) { content() }
                .padding(.horizontal, 18).padding(.top, top).padding(.bottom, bottom)
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .noSidewaysDrag()
    }
}

/// A page that never scrolls. It fills the height it is given; when the content is taller it is compacted (laid out at a wider width
/// and scaled down, never below `minScale`) and clipped. With `overflowScrolls`, a page whose content would need less than `minScale`
/// (a long list on a small phone) falls back to a `ScrollScreen` instead of becoming unreadable.
struct FixedScreen<Content: View>: View {
    var spacing: CGFloat = 12
    var top: CGFloat = 6
    var maxWidth: CGFloat = 760
    var minScale: CGFloat = 0.8
    var overflowScrolls = false
    @ViewBuilder var content: () -> Content
    @State private var scale: CGFloat = 1
    @State private var scrolling = false

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let avail: CGFloat = geo.size.height
            let layoutWidth: CGFloat = min(geo.size.width / max(scale, 0.5), maxWidth)
            if scrolling {
                ScrollScreen(spacing: spacing, top: top, maxWidth: maxWidth) {
                    content()
                        .background(GeometryReader { (g: GeometryProxy) in
                            Color.clear.preference(key: FixedHeightKey.self, value: g.size.height)
                        })
                }
                .onPreferenceChange(FixedHeightKey.self) { (h: CGFloat) in measured(h, avail: avail) }
            } else {
                VStack(alignment: .leading, spacing: spacing) { content() }
                    .padding(.horizontal, 18).padding(.top, top).padding(.bottom, 12)
                    .frame(width: layoutWidth, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { (g: GeometryProxy) in
                        Color.clear.preference(key: FixedHeightKey.self, value: g.size.height)
                    })
                    .scaleEffect(scale, anchor: .top)
                    .frame(width: geo.size.width, height: avail, alignment: .top)
                    .clipped()
                    .onPreferenceChange(FixedHeightKey.self) { (h: CGFloat) in measured(h, avail: avail) }
            }
        }
    }

    private func measured(_ h: CGFloat, avail: CGFloat) {
        guard h > 1, avail > 1 else { return }
        let needed: CGFloat = scrolling ? h + top + 12 : h
        let ideal: CGFloat = avail / needed
        if ideal < minScale {
            if overflowScrolls {
                if !scrolling { scrolling = true; scale = 1 }
            } else if abs(scale - minScale) > 0.009 {
                scale = minScale
            }
            return
        }
        if scrolling { scrolling = false }
        let q: CGFloat = (min(1, ideal) * 100).rounded(.down) / 100
        if abs(q - scale) > 0.009 { scale = q }
    }
}

extension GameStore {
    /// The one definition of "a store-level popup is on screen" (report, daily, decision, notice, red alert, error, reward, ambition,
    /// the banner question): the page under it must not scroll or take taps, and banners and the paywall wait. Popups opened with
    /// `.centerSheet` are drawn by the popup host as an overlay whose backdrop blocks the page by itself.
    var popupOpen: Bool {
        reportSheet != nil || dailySheet != nil || decisionPopup != nil || toast != nil || !redAlerts.isEmpty || errorText != nil
            || !celebrationQueue.isEmpty || ambitionPrompt || banners.confirm != nil
    }
}
