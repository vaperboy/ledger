import SwiftUI

/// Shared chrome for the "outside world" phone apps (Weather, News, Luxury, Ventures, World, Rich list). Each of them draws its own interface
/// and its own masthead; this only hides the system bar, sets the dark page and offers the round back button wired to `dismiss`.
/// The app's own palette (`OutsidePalette`) goes into the environment here, so the shared cards, lines, icons and the back button
/// inside it use that palette instead of the game's champagne-on-charcoal.
struct OutsideScreen: ViewModifier {
    var palette: OutsidePalette

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .ledgerBackground()
            .environment(\.outsidePalette, palette)
            .preferredColorScheme(palette.isLight ? .light : .dark)
    }
}

extension View {
    /// Hides the navigation bar and sets the page, for an app that draws its own header with `OutsideBack`.
    func outsideScreen(_ palette: OutsidePalette) -> some View { modifier(OutsideScreen(palette: palette)) }
}

/// The round back button (40 pt, grey outline) for an outside app's own masthead.
struct OutsideBack: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        RoundBackButton { dismiss() }
    }
}
