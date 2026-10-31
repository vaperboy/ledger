import SwiftUI

/// The short fake launch screen every Phone app shows when it is opened from the Phone home: the app's own icon (same tint and
/// glyph as on the grid) large and centred on a dark ground in the app's tint, the name beneath in the serif face, then a
/// cross-fade into the app. A tap skips it. Purely visual: the app underneath is already built, no game state is touched and
/// no engine call is made. It is a `@State` of the pushed screen, so it does not replay when returning from a sub-screen.
/// Skipped under `-showcase` (screenshots and UI tests).
struct AppLaunchSplash<Content: View>: View {
    var glyph: String
    var title: String
    var tint: Color
    /// An outside app's own palette: the splash then uses its ground, text and accent instead of the icon's tint. Nil for insider apps.
    var palette: OutsidePalette? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showing: Bool = !ProcessInfo.processInfo.arguments.contains("-showcase")
    @State private var settled = false

    var body: some View {
        content()
            .overlay { if showing { splash.transition(.opacity) } }
    }

    private var splash: some View {
        VStack(spacing: 22) {
            icon
                .scaleEffect(reduceMotion || settled ? 1 : 0.86)
            Text(title).font(.serifTitle(30)).foregroundStyle(palette?.ink ?? Theme.ivory)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ground.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the app")
        .task {
            if !reduceMotion { withAnimation(.easeOut(duration: 0.4)) { settled = true } }
            try? await Task.sleep(nanoseconds: 500_000_000)
            dismiss()
        }
    }

    @ViewBuilder private var icon: some View {
        if let p = palette {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.appIcon * 128 / 62, style: .continuous)
            GlyphView(glyph: glyph, size: 128 * 0.45, weight: 1.4, tint: p.accent)
                .frame(width: 128, height: 128)
                .background(shape.fill(p.card))
                .overlay(shape.strokeBorder(p.lineStrong, lineWidth: 1))
        } else {
            AppIconTile(glyph: glyph, size: 128, tint: tint)
        }
    }

    private var ground: some View {
        let top: Color = palette?.ground ?? tint.opacity(0.30)
        let bottom: Color = palette?.ground2 ?? Color(hex: 0x0B0C0D)
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
            .background(bottom)
    }

    private func dismiss() {
        guard showing else { return }
        withAnimation(.easeInOut(duration: reduceMotion ? 0.12 : 0.28)) { showing = false }
    }
}
