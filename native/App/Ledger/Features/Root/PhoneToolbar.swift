import SwiftUI

/// One toolbar button on Company and Group that opens the former Phone pages (news, stats, activity, luxury, settings, achievements,
/// rich list, ranking, world) as a sheet. A tap opens the list; a long press offers each page directly. The sheet itself is attached
/// once, in `GameShell`.
struct PhoneToolbar: ViewModifier {
    @EnvironmentObject var store: GameStore
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    ForEach(PhoneDestination.allCases, id: \.self) { d in
                        Button { store.openMore(d) } label: { Label(d.title, systemImage: d.symbol) }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                } primaryAction: {
                    store.openMore()
                }
                .accessibilityIdentifier("more-button")
            }
        }
    }
}

extension View {
    func phoneToolbar() -> some View { modifier(PhoneToolbar()) }
}
