import SwiftUI
import GameCore
import Simulation

struct CompanyRouteDestination: View {
    var route: NavRoute

    var body: some View {
        Group {
            switch route {
            case .company(let id): CompanyDetailView(companyID: id).companySwitcher(route)
            case .companyAt(let id, let sec): CompanyPage(companyID: id, section: sec, part: nil).companySwitcher(route)
            case .companyPart(let id, let sec, let part): CompanyPage(companyID: id, section: sec, part: part).companySwitcher(route)
            case .newCompany: NewCompanyRoute()
            case .hire(let id): HireWorkersView(companyID: id)
            case .market: MarketApp()
            case .app(let app): PhoneAppScreen(app: app)
            case .entity(let id, let section): GroupEntityScreen(entityID: id, section: section)
            case .suppliers:
                GroupSupplierDirectory()
                    .ledgerBackground()
                    .appScreen(title: "Suppliers", subtitle: "Every supplier your companies use")
            }
        }
        .zoomDestination(route)
        .id(route)
    }
}

private struct ZoomNamespaceKey: EnvironmentKey { static let defaultValue: Namespace.ID? = nil }

extension EnvironmentValues {
    var zoomNamespace: Namespace.ID? {
        get { self[ZoomNamespaceKey.self] }
        set { self[ZoomNamespaceKey.self] = newValue }
    }
}

private struct RouteDestinations: ViewModifier {
    @Namespace private var zoomNS

    func body(content: Content) -> some View {
        content
            .environment(\.zoomNamespace, zoomNS)
            .navigationDestination(for: NavRoute.self) { route in
                CompanyRouteDestination(route: route).environment(\.zoomNamespace, zoomNS)
            }
    }
}

enum ZoomSwitch {
    static var on: Bool { UserDefaults.standard.bool(forKey: "ledger.zoomOn") }
}

private struct ZoomSource: ViewModifier {
    @Environment(\.zoomNamespace) private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var route: NavRoute

    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *), ZoomSwitch.on, let ns, !reduceMotion {
            content.matchedTransitionSource(id: route.key, in: ns)
        } else {
            content
        }
    }
}

private struct ZoomDestination: ViewModifier {
    @Environment(\.zoomNamespace) private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var route: NavRoute

    private var zooms: Bool {
        switch route {
        case .company, .companyAt, .companyPart, .app: return true
        default: return false
        }
    }

    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *), ZoomSwitch.on, zooms, let ns, !reduceMotion {
            content.navigationTransition(.zoom(sourceID: route.key, in: ns))
        } else {
            content
        }
    }
}

extension View {
    func zoomSource(_ route: NavRoute) -> some View { modifier(ZoomSource(route: route)) }
    fileprivate func zoomDestination(_ route: NavRoute) -> some View { modifier(ZoomDestination(route: route)) }
}

extension View {
    func companyRouteDestinations() -> some View {
        modifier(RouteDestinations())
    }

    func companySwitcher(_ route: NavRoute) -> some View {
        safeAreaInset(edge: .top, spacing: 0) { CompanySwitcherBar(route: route) }
    }
}

struct CompanyPage: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var section: CompanySection
    var part: String?

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            if let tab = CompanyDetailView.tab(for: section, co, e) {
                CompanyDetailView(companyID: companyID, initial: tab, part: part ?? CompanyDetailView.landing(section))
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

@MainActor
struct GroupPeers {
    var entity: GroupEntity?
    var family: GroupEntity?
    var familyIDs: [Int]
    var otherIDs: [Int]

    static func make(_ store: GameStore, _ e: GameEngine, companyID: Int) -> GroupPeers {
        let list: [GroupEntity] = GroupEntities.cached(store) ?? GroupEntities.build(e)
        let family: GroupEntity? = list.first(where: { (g: GroupEntity) -> Bool in g.isChain && g.members.contains(companyID) })
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

    func context(companyID: Int) -> String {
        if let family, let i = familyIDs.firstIndex(of: companyID) {
            return "\(family.name) \u{00B7} \(family.isChain ? "store " : "")\(i + 1) of \(familyIDs.count)"
        }
        let n: Int = otherIDs.count + 1
        return n > 1 ? "Your group \u{00B7} \(n) companies" : "Your group"
    }
}

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
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    if P != .game { P.ground.ignoresSafeArea(edges: .top) }
                    if let b = LookKit.companyBackdrop(e, id) { HeaderBackdropFill(reward: b).ignoresSafeArea(edges: .top) }
                }
            }
        }
    }

    @ViewBuilder private func choice(_ e: GameEngine, _ other: Int) -> some View {
        if let co = e.state.company(other) {
            Button { store.replaceTop(with: route.with(company: other)) } label: {
                Text("\(co.name) \u{00B7} \(e.cityName(co))")
            }
            .accessibilityIdentifier("company-switch-\(other)")
        }
    }
}

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
