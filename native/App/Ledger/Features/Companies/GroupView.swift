import SwiftUI
import GameCore
import Businesses
import Simulation

/// The Group tab: the picker of companies, holdings and chains (with the group Overview above it and the Suppliers row under it). Tapping
/// an entity pushes its own page (`NavRoute.entity`) with Overview, Management, Board, Money, Expansion and Ownership; any other tab can
/// push the same page (`GameStore.openGroupEntity`). Choosing the Group tab again returns to the picker.
struct GroupView: View {
    @EnvironmentObject var store: GameStore
    @State private var showAddMenu = false
    @Environment(Entitlements.self) private var ent
    @State private var addDestination: GroupAddDestination?

    var body: some View {
        NavigationStack(path: Binding(get: { store.path(for: .group) }, set: { store.setPath($0, for: .group) })) {
            VStack(spacing: 0) {
                if let e = store.engine {
                    landing(e)
                        .id(store.rootToken(.group))
                }
            }
            .ledgerBackground()
            .toolbar(.hidden, for: .navigationBar)
            .companyRouteDestinations()
            .navigationDestination(item: $addDestination) { (d: GroupAddDestination) in addScreen(d) }
            .centerSheet(isPresented: $showAddMenu) {
                GroupAddMenu(onPick: { (d: GroupAddDestination) in
                    showAddMenu = false
                    // The push (or the paywall) waits until the popup has gone, or it would be dropped while the popup closes.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        if let g = d.gate { ent.run(g, "Add to group") { addDestination = d } } else { addDestination = d }
                    }
                })
                .environmentObject(store)
            }
            // Choosing Group again: back to the picker.
            .onChange(of: store.rootToken(.group)) { _, _ in showAddMenu = false; addDestination = nil }
        }
    }

    private func landing(_ e: GameEngine) -> some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.xs)
            ScrollScreen(top: Theme.Space.m) {
                GroupLanding(engine: e, onPick: { (g: GroupEntity, s: GroupSection) in Haptics.tap(); store.push(.entity(g.id, s), on: .group) },
                             onSuppliers: { store.push(.suppliers, on: .group) })
            }
        }
    }

    @ViewBuilder private func addScreen(_ d: GroupAddDestination) -> some View {
        switch d {
        case .newCompany: NewCompanyView()
        case .holding: NewHoldingView()
        case .franchise: FranchisesView()
        case .club: ClubMarketView()
        }
    }

    /// The tab's name and, at the right, the one way to grow the group (a popup of the four routes).
    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            Text("Group").textStyle(.title).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button { Haptics.tap(); showAddMenu = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.inset))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Add to group")
            .accessibilityIdentifier("group-add")
        }
    }
}

/// The pushed Group entity page on any tab: the entity's own page, with the entity switcher above its header. Back (its chevron, or the
/// edge swipe) pops it like any pushed screen.
struct GroupEntityScreen: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var entityID: String
    @State private var section: GroupSection

    init(entityID: String, section: GroupSection) {
        self.entityID = entityID
        _section = State(initialValue: section)
    }

    var body: some View {
        Group {
            if let e = store.engine, let entity = (GroupEntities.cached(store) ?? GroupEntities.build(e)).first(where: { (g: GroupEntity) -> Bool in g.id == entityID }) {
                GroupEntityPage(entity: entity, section: $section, onBack: { dismiss() })
                    .safeAreaInset(edge: .top, spacing: 0) { EntitySwitcherBar(entity: entity, section: section) }
            } else {
                EmptyState(glyph: Glyph.group, title: "This company is no longer in your group")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ledgerBackground()
        .navigationBarBackButtonHidden(true)
        .swipeBackEnabled()
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// One line above an entity page's header: its place in the group, and a menu that pushes one of its companies (the stores of a chain, the
/// companies of a holding, or the company itself) or swaps this page for another entity's on the same section, in place.
struct EntitySwitcherBar: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var entity: GroupEntity
    var section: GroupSection

    var body: some View {
        if let e = store.engine {
            let list: [GroupEntity] = GroupEntities.cached(store) ?? GroupEntities.build(e)
            let others: [GroupEntity] = list.filter { (g: GroupEntity) -> Bool in g.id != entity.id }
            let own: [Int] = entity.members.filter { (id: Int) -> Bool in e.state.company(id) != nil }
            let place: Int = (list.firstIndex(where: { (g: GroupEntity) -> Bool in g.id == entity.id }) ?? 0) + 1
            let context: String = list.count > 1 ? "Group \u{00B7} \(place) of \(list.count)" : "Group"
            let ownTitle: String = entity.isChain ? "Stores" : (entity.isHolding ? "Companies" : "Company page")
            Menu {
                Section(ownTitle) {
                    ForEach(own, id: \.self) { (id: Int) in companyButton(e, id) }
                }
                if !others.isEmpty {
                    Section("Other companies and chains") {
                        ForEach(others) { (g: GroupEntity) in
                            Button { store.replaceTop(with: .entity(g.id, section)) } label: { Text("\(g.name) \u{00B7} \(g.kind)") }
                                .accessibilityIdentifier("entity-switch-\(g.id)")
                        }
                    }
                }
            } label: {
                SwitcherLabel(text: context)
            }
            .accessibilityIdentifier("entity-switcher")
            .accessibilityLabel("Switch company")
            .accessibilityValue(context)
            .padding(.horizontal, Theme.Space.page)
            .background(P.ground.ignoresSafeArea(edges: .top))
        }
    }

    /// Pushes one company of the entity (a holding opens on its holding page).
    @ViewBuilder private func companyButton(_ e: GameEngine, _ id: Int) -> some View {
        if let co = e.state.company(id) {
            let route: NavRoute = co.type == "hold" ? .companyAt(id, .holding) : .company(id)
            Button { Haptics.tap(); store.push(route) } label: {
                Text(entity.isChain ? "\(co.name) \u{00B7} \(e.cityName(co))" : co.name)
            }
            .accessibilityIdentifier("entity-open-company-\(id)")
        }
    }
}
