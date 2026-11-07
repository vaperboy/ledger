import SwiftUI
import GameCore
import Simulation

/// The one table that turns a `NavRoute` into a screen. Every tab's NavigationStack registers it (`companyRouteDestinations()`), so any
/// link can push any of these screens on the tab the player is on: a company, a Group entity page, a Phone app, Applicants, Suppliers.
struct CompanyRouteDestination: View {
    var route: NavRoute

    var body: some View {
        Group {
            switch route {
            case .company(let id): CompanyDetailView(companyID: id).companySwitcher(route)
            case .companyAt(let id, let sec): CompanyPage(companyID: id, section: sec, part: nil).companySwitcher(route)
            case .companyPart(let id, let sec, let part): CompanyPage(companyID: id, section: sec, part: part).companySwitcher(route)
            case .newCompany: NewCompanyView()
            case .applicants(let id, let role): ApplicantsView(companyID: id == 0 ? nil : id, role: role.isEmpty ? nil : role)
            // The store turns this route into the Market app (`GameStore.setPath`); this is the same app.
            case .market: MarketApp()
            case .app(let app): PhoneAppScreen(app: app)
            case .entity(let id, let section): GroupEntityScreen(entityID: id, section: section)
            case .suppliers:
                GroupSupplierDirectory()
                    .ledgerBackground()
                    .appScreen(title: "Suppliers", subtitle: "Every supplier your companies use")
            }
        }
        // A fresh view per route: a link that changes the part of a screen already on the stack must not keep that screen's old state.
        .id(route)
    }
}

extension View {
    /// Registers the shared destinations on the navigation stack this view roots. Every tab root calls it exactly once.
    func companyRouteDestinations() -> some View {
        navigationDestination(for: NavRoute.self) { route in CompanyRouteDestination(route: route) }
    }

    /// The company switcher above a company screen's header.
    func companySwitcher(_ route: NavRoute) -> some View {
        safeAreaInset(edge: .top, spacing: 0) { CompanySwitcherBar(route: route) }
    }
}

/// A link to one page of a company: a section of the company screen opens it on that section; a page of its own (Marketing, Customers,
/// Setup, Plant ...) is pushed; a page this company does not have opens its Overview.
struct CompanyPage: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var section: CompanySection
    var part: String?

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            if let tab = CompanyDetailView.tab(for: section, co, e) {
                CompanyDetailView(companyID: companyID, initial: tab, part: part ?? (section == .customers ? StatsPart.customers.rawValue : nil))
            } else if section == .chain || CompanyDetailView.availableSections(co, e).contains(section) {
                CompanySectionScreen(companyID: companyID, section: section)
            } else {
                CompanyDetailView(companyID: companyID)
            }
        } else {
            CompanyDetailView(companyID: companyID)
        }
    }
}

// MARK: Company switcher

/// The companies a switcher offers for one company: its Group entity page, the chain or holding it belongs to (its members, the company
/// included), and every other company of the group in the Group picker's order.
@MainActor
struct GroupPeers {
    var entity: GroupEntity?
    var family: GroupEntity?
    var familyIDs: [Int]
    var otherIDs: [Int]

    static func make(_ store: GameStore, _ e: GameEngine, companyID: Int) -> GroupPeers {
        let list: [GroupEntity] = GroupEntities.cached(store) ?? GroupEntities.build(e)
        let family: GroupEntity? = list.first(where: { (g: GroupEntity) -> Bool in (g.isChain || g.isHolding) && g.members.contains(companyID) })
        let familyIDs: [Int] = (family?.members ?? []).filter { (id: Int) -> Bool in e.state.company(id) != nil }
        var others: [Int] = []
        for g in list {
            let ids: [Int] = g.isChain ? g.members : [g.companyID]
            for id in ids where id != companyID && !familyIDs.contains(id) && !others.contains(id) && e.state.company(id) != nil {
                others.append(id)
            }
        }
        return GroupPeers(entity: GroupEntities.find(list, companyID: companyID), family: family, familyIDs: familyIDs, otherIDs: others)
    }

    /// "Bean & Co · store 2 of 5", "Holdco · 2 of 3", "Your group · 7 companies".
    func context(companyID: Int) -> String {
        if let family, let i = familyIDs.firstIndex(of: companyID) {
            return "\(family.name) \u{00B7} \(family.isChain ? "store " : "")\(i + 1) of \(familyIDs.count)"
        }
        let n: Int = otherIDs.count + 1
        return n > 1 ? "Your group \u{00B7} \(n) companies" : "Your group"
    }
}

/// One line above a company screen's header: where the company sits in the group, and a menu that swaps this screen for the same page of
/// another company or branch in place (Back still returns to the screen under it), or pushes the company's Group entity page.
struct CompanySwitcherBar: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var route: NavRoute

    var body: some View {
        if let e = store.engine, let id = route.companyID, e.state.company(id) != nil {
            let peers: GroupPeers = GroupPeers.make(store, e, companyID: id)
            let context: String = peers.context(companyID: id)
            Menu {
                if let g = peers.entity {
                    Button { store.push(.entity(g.id, .overview)) } label: { Label("\(g.name) in Group", systemImage: "square.stack.3d.up") }
                        .accessibilityIdentifier("company-open-group")
                }
                if let family = peers.family, peers.familyIDs.count > 1 {
                    let familyTitle: String = family.isChain ? "Stores of \(family.name)" : family.name
                    Section(familyTitle) {
                        ForEach(peers.familyIDs.filter { (x: Int) -> Bool in x != id }, id: \.self) { (other: Int) in choice(e, other) }
                    }
                }
                if !peers.otherIDs.isEmpty {
                    let othersTitle: String = peers.family == nil ? "Your companies" : "Other companies"
                    Section(othersTitle) {
                        ForEach(peers.otherIDs, id: \.self) { (other: Int) in choice(e, other) }
                    }
                }
            } label: {
                SwitcherLabel(text: context)
            }
            .accessibilityIdentifier("company-switcher")
            .accessibilityLabel("Switch company")
            .accessibilityValue(context)
            .padding(.horizontal, Theme.Space.page)
            .background(P.ground.ignoresSafeArea(edges: .top))
        }
    }

    @ViewBuilder private func choice(_ e: GameEngine, _ other: Int) -> some View {
        if let co = e.state.company(other) {
            Button { store.replaceTop(with: route.with(company: other)) } label: {
                Text("\(co.name) \u{00B7} \(co.type == "hold" ? "Holding" : e.cityName(co))")
            }
            .accessibilityIdentifier("company-switch-\(other)")
        }
    }
}

/// The switcher's face: the group glyph, the context line and an up-down chevron, one 44 pt row.
struct SwitcherLabel: View {
    @Environment(\.outsidePalette) private var P
    var text: String

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            LedgerGlyph(glyph: Glyph.group, size: Theme.Icon.small, tint: P.inkFaint)
            Text(text).textStyle(.caption, tint: P.inkSoft).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(P.inkFaint)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
