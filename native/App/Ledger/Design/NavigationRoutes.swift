import SwiftUI
import GameCore
import Simulation

// Navigation correctness (stage 3). One mechanism for every deep link:
//  - A company or record is PUSHED onto the navigation stack of the tab the player is on (`GameStore.openCompany`), so Back
//    returns to that screen. Each tab with its own stack takes the request with `routeRequests(for:path:)`.
//  - A link that has to land on another tab (an Inbox message, a Money section, New company) goes through `GameStore.jump(to:)`,
//    which remembers where the player came from; the destination tab shows a "Back to <tab>" bar (`returnBar(for:)`).

struct RouteRequests: ViewModifier {
    @EnvironmentObject var store: GameStore
    var tab: AppTab
    @Binding var path: [CompanyRoute]

    func body(content: Content) -> some View {
        content
            .onAppear { take() }
            .onChange(of: store.routeRequest) { _, _ in take() }
    }

    private func take() {
        guard let r = store.routeRequest, r.tab == tab else { return }
        store.routeRequest = nil
        // A finished "new company" form is not somewhere Back should return to.
        if path.last == .newCompany { path.removeLast() }
        if path.last != r.route { path.append(r.route) }
    }
}

struct ReturnBar: ViewModifier {
    @EnvironmentObject var store: GameStore
    var tab: AppTab

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if store.tab == tab, let back = store.returnTab {
                Button { Haptics.tap(); store.returnToOrigin() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                        Text("Back to \(back.title)").font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(Theme.gold)
                    .padding(.horizontal, Theme.Space.margin).padding(.vertical, 8)
                    .background(Theme.walnut.opacity(0.9))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("return-bar")
            }
        }
    }
}

extension View {
    /// Takes pushes requested by `GameStore.openCompany` for this tab onto `path`.
    func routeRequests(for tab: AppTab, path: Binding<[CompanyRoute]>) -> some View { modifier(RouteRequests(tab: tab, path: path)) }
    /// Shows "Back to <tab>" while this tab was reached by a link from another tab.
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
