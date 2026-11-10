import SwiftUI

enum PopupStep: Equatable {
    case popPage
    case closePopup

    static func forClose(pagesPushed: Int) -> PopupStep { pagesPushed > 0 ? .popPage : .closePopup }
}

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
