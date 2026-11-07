import SwiftUI
import GameCore
import Simulation

// Navigation. GameStore owns every navigation stack (`routePaths`, `phonePath`) and every pending request; the tab roots only
// bind their NavigationStack to it. One rule for every deep link:
//  - A company or record is PUSHED onto the stack of the tab the player is on (`GameStore.openCompany`), so Back returns to that
//    screen. A record already on the stack is gone back to, never stacked twice.
//  - A link that has to land on another tab (`open(_:on:)`, `jump(to:)`, `openApp`) switches to it and remembers where it came from.
//    Back from the screen it pushed (the round back button or a swipe) returns to that origin and leaves nothing behind on the other
//    tab. At a tab root, where there is no round back button, a "Back to <tab>" line is the one way back (`returnBar(for:)`).
//  - Choosing the tab that is already open returns it to its root (`GameStore.selectTab`).

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

// MARK: Ladder goal links

extension GameStore {
    /// The screen a goal's button names (ladder, career and daily goals): sales, hire, inbox, marketing, money, company, management,
    /// customers, achievements, newCompany. Each goes straight to its target on the stack of the tab the player is on, so Back walks up.
    /// A link that needs a company opens the one the goal is about (`ladderCompany`); without one it opens the new-company page.
    /// Returns false for an unknown or empty link.
    @discardableResult func openLadderLink(_ link: String) -> Bool {
        if link == "inbox" { openApp(.inbox); return true }
        if link == "achievements" { openApp(.achievements); return true }
        if link == "newCompany" { open(.newCompany, on: .company); return true }
        guard let id = ladderCompany(for: link) else {
            if ["sales", "hire", "marketing", "money", "company", "management", "customers"].contains(link) { open(.newCompany, on: .company); return true }
            return false
        }
        switch link {
        case "sales": openCompany(id, section: .salesMarket)
        case "hire": openApplicants(companyID: id, role: nil)
        case "marketing": openCompany(id, section: .marketing)
        case "money": openCompany(id, section: .finances)
        case "company": openCompany(id)
        case "management": openCompany(id, section: .operations)
        case "customers": openCompany(id, section: .customers)
        default: return false
        }
        return true
    }

    /// The open company a goal link is about: the thinnest team for hiring, the least known for marketing, the least cash for money,
    /// the weakest reputation for sales and customers; otherwise the first.
    func ladderCompany(for link: String) -> Int? {
        guard let e = engine else { return nil }
        let live: [Company] = e.state.companies.filter { $0.status.isLive && $0.type != "hold" }
        let pick: Company?
        switch link {
        case "hire": pick = live.min { (a: Company, b: Company) -> Bool in a.staff.count < b.staff.count }
        case "marketing": pick = live.min { (a: Company, b: Company) -> Bool in a.awareness < b.awareness }
        case "money": pick = live.min { (a: Company, b: Company) -> Bool in a.cash < b.cash }
        case "sales", "customers", "management": pick = live.min { (a: Company, b: Company) -> Bool in a.reputation < b.reputation }
        default: pick = live.first
        }
        return pick?.id
    }
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
