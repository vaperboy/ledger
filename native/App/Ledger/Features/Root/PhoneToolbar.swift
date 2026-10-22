import SwiftUI

/// One toolbar button on Company and Group that opens the former Phone pages (news, stats, activity, luxury, settings, achievements,
/// rich list, ranking, world) as a sheet. The sheet itself is attached once, in `GameShell`.
struct PhoneToolbar: ViewModifier {
    @EnvironmentObject var store: GameStore
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { Haptics.tap(); store.showPhone = true } label: { Label("More", systemImage: "ellipsis.circle") }
                    .accessibilityIdentifier("more-button")
            }
        }
    }
}

extension View {
    func phoneToolbar() -> some View { modifier(PhoneToolbar()) }
}
