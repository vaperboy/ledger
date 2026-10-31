import SwiftUI
import GameCore
import Simulation

// Navigation (stage 1). GameStore owns every navigation stack (`routePaths`, `phonePath`) and every pending request; the tab roots only
// bind their NavigationStack to it. One rule for every deep link:
//  - A company or record is PUSHED onto the stack of the tab the player is on (`GameStore.openCompany`), so Back returns to that
//    screen. A record already on the stack is gone back to, never stacked twice.
//  - A link that has to land on another tab (`open(_:on:)`, `jump(to:)`, `openApp`) switches to it and remembers where it came from.
//    Back from the screen it pushed (the round back button or a swipe) returns to that origin and leaves nothing behind on the other
//    tab. At a tab root, where there is no round back button, a "Back to <tab>" line is the one way back (`returnBar(for:)`).
//  - Choosing the tab that is already open returns it to its root (`GameStore.selectTab`).

/// What a tab root's `path.append(route)` calls become: a push through the store, so the same record is never stacked twice.
struct TabPath {
    var store: GameStore
    var tab: AppTab
    func append(_ route: CompanyRoute) { store.push(route, on: tab) }
}

/// "Back to <tab>" at the root of a tab that a link from another tab landed on (no screen is pushed there, so no round back button).
struct ReturnBar: ViewModifier {
    @EnvironmentObject var store: GameStore
    var tab: AppTab

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) { ReturnLine(tab: tab) }
    }
}

extension View {
    /// Shows "Back to <tab>" while this tab's root was reached by a link from another tab.
    func returnBar(for tab: AppTab) -> some View { modifier(ReturnBar(tab: tab)) }
}

// MARK: Shared cash wording (Home and Group > Money say the same thing)

/// What each "cash" figure includes, in one place, so Home and Money cannot drift apart.
/// Home shows personal cash plus savings; Group > Money shows that plus the cash in every company that has some.
enum CashWording {
    /// Home: `NetWorth.personal` = wallet cash + savings.
    static let personal = "Personal cash"
    /// Group > Money: `FinanceOverview.cashAvailable` for the whole group = company cash (not overdrawn) + personal cash + savings.
    static let group = "Cash across group"
    /// Money for one company: that company's cash only.
    static let company = "Company cash"
    static let personalNote = "of which personal cash and savings"
    static func available(companyID: Int?) -> String { companyID == nil ? group : company }
}

// MARK: Message text

extension String {
    /// Engine-written text with "£11 k" / "£2.5 M" / "£1.2 bn" tidied to "£11k" / "£2.5M" / "£1.2bn" and "2\u{00A0}751" to "2,751".
    /// Only a number followed by the unit is touched, so a name such as "Mr M Smith" is left alone.
    /// Display only; `Currency.short` itself stays as the golden tests pin it.
    var tidyText: String { tidyMoney }
}

extension GameEngine {
    /// `localized` for text the player reads: tokens resolved, money units tidied.
    func displayText(_ text: String, companyID: Int = 0) -> String { localized(text, companyID: companyID).tidyText }
}

/// A sidebar row whose icon sits in a fixed-width box, so wide symbols (Team's three people) do not push their title out of line.
struct SidebarLabel: View {
    var title: String
    var symbol: String
    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol).frame(width: 28, alignment: .center)
        }
    }
}
