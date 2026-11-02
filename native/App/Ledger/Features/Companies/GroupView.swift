import SwiftUI
import GameCore
import Businesses
import Simulation

/// The Group tab, built like Banking: it opens the picker of companies, holdings and chains (with the group Overview above it and the
/// Suppliers row under it); tapping an entity opens its own page with Overview, Board, Dividends, Expansion, Money and Deals.
/// Choosing the Group tab again returns to the picker. Other screens can ask for an entity page through `GroupRouteBox`.
struct GroupView: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var routes = GroupRouteBox.shared
    @State private var pickedID: String?
    @State private var section: GroupSection = .overview
    @State private var showSuppliers = false
    @State private var showNewHolding = false

    var body: some View {
        NavigationStack(path: Binding(get: { store.path(for: .group) }, set: { store.setPath($0, for: .group) })) {
            VStack(spacing: 0) {
                ReturnLine(tab: .group)
                if let e = store.engine {
                    page(e)
                        .id(store.rootToken(.group))
                }
            }
            .ledgerBackground()
            .toolbar(.hidden, for: .navigationBar)
            .companyRouteDestinations()
            .navigationDestination(isPresented: $showSuppliers) {
                GroupSupplierDirectory()
                    .ledgerBackground()
                    .appScreen(title: "Suppliers", subtitle: "Every supplier your companies use", tab: .group)
            }
            .navigationDestination(isPresented: $showNewHolding) { NewHoldingView() }
            // Choosing Group again: back to the picker.
            .onChange(of: store.rootToken(.group)) { _, _ in
                pickedID = nil; section = .overview; showSuppliers = false; showNewHolding = false
            }
            .onAppear { takeRoute() }
            .onChange(of: routes.request) { _, _ in takeRoute() }
        }
    }

    @ViewBuilder private func page(_ e: GameEngine) -> some View {
        let list: [GroupEntity] = GroupEntities.build(e)
        if let id = pickedID, let ent = list.first(where: { (g: GroupEntity) -> Bool in g.id == id }) {
            GroupEntityPage(entity: ent, section: $section, onBack: { close() })
                .transition(.move(edge: .trailing))
        } else {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 18).padding(.top, 6)
                ScrollScreen(top: 12) {
                    GroupLanding(engine: e, onPick: { (g: GroupEntity) in open(g, .overview) },
                                 onSuppliers: { showSuppliers = true }, onNewHolding: { showNewHolding = true })
                }
            }
            .transition(.move(edge: .leading))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            IconCircle(glyph: Glyph.group, size: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text("Group").font(.serifTitle(28)).foregroundStyle(Theme.ivory).lineLimit(1)
                Text("Choose a company, holding or chain").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
        }
    }

    private func open(_ g: GroupEntity, _ s: GroupSection) {
        withAnimation(.snappy(duration: 0.25)) { section = s; pickedID = g.id }
    }

    private func close() {
        withAnimation(.snappy(duration: 0.25)) { pickedID = nil; section = .overview }
    }

    /// A request from another screen (a chain store's menu, the Team tab): show that company's entity page at the asked section.
    private func takeRoute() {
        guard routes.request != nil, let e = store.engine else { return }
        guard let r = routes.take() else { return }
        let list: [GroupEntity] = GroupEntities.find(GroupEntities.build(e), companyID: r.companyID).map { [$0] } ?? []
        guard let g = list.first else { return }
        showSuppliers = false; showNewHolding = false
        let s: GroupSection = GroupSection.allCases.first(where: { (x: GroupSection) -> Bool in x.key == r.section }) ?? .overview
        open(g, s)
    }
}
