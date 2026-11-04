import SwiftUI

/// The pure rule of the step-back variant: what a close request does in a tall popup that holds its own navigation. One page is
/// popped first; only from the root does the popup close. Kept apart from the view so it is unit-tested (`PopupQueueTests`).
enum PopupStep: Equatable {
    case popPage
    case closePopup

    static func forClose(pagesPushed: Int) -> PopupStep { pagesPushed > 0 ? .popPage : .closePopup }
}

/// A tall popup (`.centerSheet(..., size: .tall)`) that holds its own navigation, e.g. a list that opens a detail page.
///
/// Inside it, `popupClose` (and so every view's own `dismiss()` helper, `AppScreen`'s round back button, "Done" after a signature) is a
/// STEP BACK: it pops one page, and closes the popup only at the root. The x of the card and a tap outside still close the whole popup.
/// Pages are pushed with `NavigationLink(value:)`, one `Hashable` value per page; the root hides the system navigation bar (the card
/// has its own header), a pushed page shows it with the system back button.
struct PopupStack<Page: Hashable, Root: View, Destination: View>: View {
    @Environment(\.popupClose) private var closePopup
    @State private var path: [Page] = []
    @ViewBuilder var root: () -> Root
    @ViewBuilder var destination: (Page) -> Destination

    var body: some View {
        let pushed: Binding<[Page]> = $path
        let close: (() -> Void)? = closePopup
        let stepBack: () -> Void = {
            switch PopupStep.forClose(pagesPushed: pushed.wrappedValue.count) {
            case .popPage: pushed.wrappedValue.removeLast()
            case .closePopup: close?()
            }
        }
        return NavigationStack(path: pushed) {
            root()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Page.self) { (page: Page) in destination(page) }
        }
        .environment(\.popupClose, stepBack)
    }
}
