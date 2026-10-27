import SwiftUI

/// Shared chrome for the "outside world" phone apps (News, Luxury, Ventures, World, Rich list). Each of them draws its own interface
/// and its own masthead; this only hides the system bar, sets the dark page and offers the round back button wired to `dismiss`.
struct OutsideScreen: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .ledgerBackground()
    }
}

extension View {
    /// Hides the navigation bar and sets the page, for an app that draws its own header with `OutsideBack`.
    func outsideScreen() -> some View { modifier(OutsideScreen()) }
}

/// The round back button (40 pt, grey outline) for an outside app's own masthead.
struct OutsideBack: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        RoundBackButton { dismiss() }
    }
}
