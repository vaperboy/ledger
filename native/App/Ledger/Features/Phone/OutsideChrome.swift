import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Shared chrome for the "outside world" phone apps (Weather, News, Luxury, Ventures, the shops). Each of them draws its own
/// interface and its own masthead; this only hides the system bar, sets the page and offers the round back button wired to `dismiss`.
/// The app's own palette (`OutsidePalette`) goes into the environment here, so the shared cards, lines, icons and the back button
/// inside it use that palette instead of the game's champagne-on-charcoal. A light palette also turns the status bar dark.
struct OutsideScreen: ViewModifier {
    var palette: OutsidePalette

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .swipeBackEnabled()
            .toolbar(.hidden, for: .navigationBar)
            .ledgerBackground()
            .environment(\.outsidePalette, palette)
            .preferredColorScheme(palette.isLight ? .light : .dark)
            .modifier(LightStatusBar(on: palette.isLight))
    }
}

extension View {
    /// Hides the navigation bar and sets the page, for an app that draws its own header with `OutsideBack`.
    func outsideScreen(_ palette: OutsidePalette) -> some View { modifier(OutsideScreen(palette: palette)) }
}

/// Dark status bar text while a light app is on the selected tab. The app root follows `StatusBarScheme.shared.light`; each light app
/// screen registers itself while it is shown on the active tab page (hidden tab pages stay alive, so the tab's activity counts too).
struct LightStatusBar: ViewModifier {
    var on: Bool
    @Environment(\.markerPageActive) private var activePage
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { StatusBarScheme.shared.set(id, on && activePage) }
            .onChange(of: activePage) { _, now in StatusBarScheme.shared.set(id, on && now) }
            .onChange(of: on) { _, now in StatusBarScheme.shared.set(id, now && activePage) }
            .onDisappear { StatusBarScheme.shared.set(id, false) }
    }
}

/// Which light screens are showing now; the app root asks for the light scheme (dark status bar text) while any is.
@MainActor
final class StatusBarScheme: ObservableObject {
    static let shared = StatusBarScheme()
    @Published private(set) var light = false
    private var shown: Set<UUID> = []

    func set(_ id: UUID, _ on: Bool) {
        if on { shown.insert(id) } else { shown.remove(id) }
        let now: Bool = !shown.isEmpty
        if now != light { light = now }
    }
}

/// The back button (44 pt target, in the app's ink) for an outside app's own masthead.
struct OutsideBack: View {
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var body: some View {
        RoundBackButton { dismiss() }
    }
}
