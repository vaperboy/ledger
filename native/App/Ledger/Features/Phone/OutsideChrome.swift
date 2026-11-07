import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Shared chrome for the "outside world" phone apps (Weather, News, Luxury, Ventures, World, Rich list, the shops). Each of them draws its own
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

/// Dark status bar text while a light app is on screen. The game's root asks for the dark look, which keeps the status bar white over a
/// light page; this lightens the window's root controller while at least one light screen is visible and gives the dark look back after.
struct LightStatusBar: ViewModifier {
    var on: Bool

    func body(content: Content) -> some View {
        if on {
            content
                .onAppear { StatusBarStyle.lightScreens += 1; StatusBarStyle.apply() }
                .onDisappear { StatusBarStyle.lightScreens = max(0, StatusBarStyle.lightScreens - 1); StatusBarStyle.apply() }
        } else {
            content
        }
    }
}

/// How many light screens are visible now, and the window style that follows from it.
@MainActor
enum StatusBarStyle {
    static var lightScreens = 0

    static func apply() {
        #if canImport(UIKit)
        let windows: [UIWindow] = UIApplication.shared.connectedScenes.compactMap { (s: UIScene) -> UIWindowScene? in s as? UIWindowScene }.flatMap { (w: UIWindowScene) -> [UIWindow] in w.windows }
        guard let root = (windows.first { (w: UIWindow) -> Bool in w.isKeyWindow } ?? windows.first)?.rootViewController else { return }
        let style: UIUserInterfaceStyle = lightScreens > 0 ? .light : .dark
        if root.overrideUserInterfaceStyle != style {
            root.overrideUserInterfaceStyle = style
            root.setNeedsStatusBarAppearanceUpdate()
        }
        #endif
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
