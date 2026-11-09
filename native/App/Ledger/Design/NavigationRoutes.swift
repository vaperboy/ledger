import SwiftUI
import GameCore
import Simulation

// Navigation. GameStore owns every tab's navigation stack (`stacks`, one `NavRoute` array per tab) and every pending request; the tab
// roots only bind their NavigationStack to it and register the one destination table (`companyRouteDestinations()`). One rule:
//  - A link never changes tab. Whatever it opens (a company, a Group entity page, a Phone app such as the Inbox or the Bank, Applicants,
//    the supplier directory) is PUSHED onto the stack of the tab the player is on, so Back and the edge swipe return to where they were.
//    A record already on the stack is gone back to, never stacked twice.
//  - Only the tab bar changes tab. Choosing a tab shows its root; choosing the tab that is already open returns it to its root.

/// Every screen a link can push, on any tab's stack.
enum NavRoute: Hashable {
    /// The company screen: its Overview with the fixed section bar Overview | Team | Manage | Sales | Stats.
    case company(Int)
    case newCompany, market
    /// One screen of a company (a section of the hub, or a trade's own page), opened from the hub, Team, Projects, the Inbox or a deep link.
    case companyAt(Int, CompanySection)
    /// The same screen opened on one of its parts (the Finances page on Ownership, Operations on Premises): `part` is the part's title.
    case companyPart(Int, CompanySection, String)
    /// The Applicants page: company id (0 = all companies) and role id ("" = all roles).
    case applicants(Int, String)
    /// A Phone app (Inbox, Bank ...); what a link asked it to show waits in `GameStore.appRequest`.
    case app(PhoneApp)
    /// The Group entity page of a company, holding or chain (`GroupEntity.id`), on one of its sections.
    case entity(String, GroupSection)
    /// Every supplier the group's companies use.
    case suppliers

    /// What makes two routes "the same record" for the navigation stack: the company, and for the trade pages that are their own screen
    /// (Marketing, Customers, Market, Plant, Fish, Club, Chain, Book, Setup) the page too. The five sections of the company screen
    /// (Overview, Team, Manage, Sales, Stats) are one record: a link to another of them changes the section shown, it never stacks a copy.
    /// An entity page is one record whatever its section.
    var key: String {
        switch self {
        case .company(let id): return "company.\(id)"
        case .companyAt(let id, let s), .companyPart(let id, let s, _): return CompanyDetailView.isLeaf(s) ? "company.\(id).\(s.rawValue)" : "company.\(id)"
        case .newCompany: return "newCompany"
        case .applicants: return "applicants"
        case .market: return "market"
        case .app(let app): return "app.\(app.rawValue)"
        case .entity(let id, _): return "entity.\(id)"
        case .suppliers: return "suppliers"
        }
    }

    /// The company a company screen shows, nil for the other routes.
    var companyID: Int? {
        switch self {
        case .company(let id), .companyAt(let id, _), .companyPart(let id, _, _): return id
        default: return nil
        }
    }

    /// The same screen of another company (the company switcher keeps the section or page the player was on).
    func with(company id: Int) -> NavRoute {
        switch self {
        case .companyAt(_, let s): return .companyAt(id, s)
        case .companyPart(_, let s, let p): return .companyPart(id, s, p)
        default: return .company(id)
        }
    }

    /// The route for `openCompany(id, section:, part:)`. A link without a section opens the hub. Premises are a part of Operations.
    static func make(_ id: Int, _ section: CompanySection?, _ part: String?) -> NavRoute {
        guard let section else { return .company(id) }
        if section == .properties { return .companyPart(id, .operations, OpsPart.premises.rawValue) }
        if let part, !part.isEmpty { return .companyPart(id, section, part) }
        return .companyAt(id, section)
    }
}

/// The company routes keep their older name at the call sites (`NavigationLink(value: CompanyRoute.company(id))`).
typealias CompanyRoute = NavRoute

/// "Back to <tab>" at a tab root reached from another tab. Links never change tab, so `ReturnLine` has nothing to show.
struct ReturnBar: ViewModifier {
    @EnvironmentObject var store: GameStore
    var tab: AppTab

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) { ReturnLine(tab: tab) }
    }
}

extension View {
    func returnBar(for tab: AppTab) -> some View { modifier(ReturnBar(tab: tab)) }
}

// MARK: Ladder goal links

extension GameStore {
    /// The screen a goal's button names (ladder, career and daily goals): sales, hire, inbox, marketing, money, company, management,
    /// customers, achievements, newCompany. Each is pushed on the stack of the tab the player is on, so Back walks up.
    /// A link that needs a company opens the one the goal is about (`ladderCompany`); without one it opens the new-company page.
    /// Returns false for an unknown or empty link.
    @discardableResult func openLadderLink(_ link: String) -> Bool {
        if link == "inbox" { openApp(.inbox); return true }
        if ["news", "market", "techPro", "reviews", "weather"].contains(link), let app = PhoneApp(rawValue: link) { openApp(app); return true }   // daily goals that open a Phone app
        if link == "accounting" { openApp(.bank); return true }
        if link == "achievements" { openApp(.achievements); return true }
        if link == "newCompany" { push(.newCompany); return true }
        guard let id = ladderCompany(for: link) else {
            if ["sales", "hire", "marketing", "money", "company", "management", "customers"].contains(link) { push(.newCompany); return true }
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
/// Home shows your own cash; Group > Money shows that plus the cash in every company that has some.
enum CashWording {
    /// Home: `NetWorth.personal` = your cash (plus money held for you).
    static let personal = "Personal cash"
    /// Group > Money: `FinanceOverview.cashAvailable` for the whole group = company cash (not overdrawn) + your own cash.
    static let group = "Cash across group"
    /// Money for one company: that company's cash only.
    static let company = "Company cash"
    static let personalNote = "of which your own cash"
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
