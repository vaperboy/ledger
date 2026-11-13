import SwiftUI
import GameCore
import Simulation

enum NavRoute: Hashable {
    case company(Int)
    case newCompany, market
    case companyAt(Int, CompanySection)
    case companyPart(Int, CompanySection, String)
    case hire(Int)
    case app(PhoneApp)
    case entity(String, GroupSection)
    case suppliers
    case supplier(Int, String)
    case supplierOwner(SupplierOwnerRef)

    var key: String {
        switch self {
        case .company(let id): return "company.\(id)"
        case .companyAt(let id, let s), .companyPart(let id, let s, _): return CompanyDetailView.isLeaf(s) ? "company.\(id).\(s.rawValue)" : "company.\(id)"
        case .newCompany: return "newCompany"
        case .hire(let id): return "hire.\(id)"
        case .market: return "market"
        case .app(let app): return "app.\(app.rawValue)"
        case .entity(let id, _): return "entity.\(id)"
        case .suppliers: return "suppliers"
        case .supplier(let id, let subject): return "supplier.\(id).\(subject)"
        case .supplierOwner(let r): return "supplierOwner.\(r.code).\(r.company)"
        }
    }

    var companyID: Int? {
        switch self {
        case .company(let id), .companyAt(let id, _), .companyPart(let id, _, _): return id
        default: return nil
        }
    }

    func with(company id: Int) -> NavRoute {
        switch self {
        case .companyAt(_, let s): return .companyAt(id, s)
        case .companyPart(_, let s, let p): return .companyPart(id, s, p)
        default: return .company(id)
        }
    }

    static func make(_ id: Int, _ section: CompanySection?, _ part: String?) -> NavRoute {
        guard let section else { return .company(id) }
        if section == .properties { return .companyPart(id, .operations, OpsPart.premises.rawValue) }
        if let part, !part.isEmpty { return .companyPart(id, section, part) }
        return .companyAt(id, section)
    }
}

typealias CompanyRoute = NavRoute

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

extension GameStore {
    @discardableResult func openLadderLink(_ link: String) -> Bool {
        if link == "inbox" { openApp(.inbox); return true }
        if ["news", "market", "techPro", "competition"].contains(link), let app = PhoneApp(rawValue: link) { openApp(app); return true }
        if link == "achievements" { openProfile(); return true }
        if link == "newCompany" { push(.newCompany); return true }
        guard let id = ladderCompany(for: link) else {
            if ["sales", "hire", "marketing", "money", "company", "management", "customers"].contains(link) { push(.newCompany); return true }
            return false
        }
        switch link {
        case "sales": openCompany(id, section: .salesMarket)
        case "hire": openHire(companyID: id)
        case "marketing": openCompany(id, section: .marketing)
        case "money": openCompany(id, section: .finances)
        case "company": openCompany(id)
        case "management": openCompany(id, section: .operations)
        case "customers": openCompany(id, section: .customers)
        default: return false
        }
        return true
    }

    func ladderCompany(for link: String) -> Int? {
        guard let e = engine else { return nil }
        let live: [Company] = e.state.companies.filter { $0.status.isLive }
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

extension String {
    var tidyText: String { tidyMoney }
}

extension GameEngine {
    func displayText(_ text: String, companyID: Int = 0) -> String { localized(text, companyID: companyID).tidyText }
}

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
