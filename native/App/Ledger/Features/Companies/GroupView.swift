import SwiftUI
import GameCore
import Businesses
import Simulation

struct GroupView: View {
    @EnvironmentObject var store: GameStore
    @State private var showAddMenu = false
    @State private var addDestination: GroupAddDestination?
    @State private var tab: GroupHomeTab = .overview

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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { addDestination = d }
                })
                .environmentObject(store)
            }
            .onChange(of: store.rootToken(.group)) { _, _ in showAddMenu = false; addDestination = nil; tab = .overview }
        }
    }

    private func landing(_ e: GameEngine) -> some View {
        VStack(spacing: 0) {
            Text("Group").textStyle(.title).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.xs)
            GroupHome(engine: e, tab: $tab, onAdd: { showAddMenu = true },
                      onPick: { (g: GroupEntity, s: GroupSection) in Haptics.tap(); store.push(.entity(g.id, s), on: .group) })
        }
    }

    @ViewBuilder private func addScreen(_ d: GroupAddDestination) -> some View {
        switch d {
        case .newCompany: NewCompanyRoute()
        case .holding: NewHoldingView()
        case .franchise: FranchisesView()
        case .club: ClubMarketView()
        }
    }
}

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
                    .safeAreaInset(edge: .top, spacing: 0) { EntityBreadcrumb(entity: entity, section: section, onGroup: { dismiss() }) }
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

struct EntityBreadcrumb: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var entity: GroupEntity
    var section: GroupSection
    var onGroup: () -> Void

    var body: some View {
        if let e = store.engine {
            let list: [GroupEntity] = GroupEntities.cached(store) ?? GroupEntities.build(e)
            StructureCrumbs(crumbs: crumbs(e, list))
                .padding(.horizontal, Theme.Space.page)
                .background(P == .game ? Color.clear : P.ground)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("entity-breadcrumb")
        }
    }

    private func crumbs(_ e: GameEngine, _ list: [GroupEntity]) -> [StructureCrumb] {
        var out: [StructureCrumb] = [StructureCrumb(id: "group", title: "Group", action: onGroup)]
        if entity.indent, let co = e.state.company(entity.companyID), co.holdingID != 0,
           let parent = list.first(where: { (g: GroupEntity) -> Bool in g.isHolding && g.companyID == co.holdingID }) {
            let pid: String = parent.id
            let s: GroupSection = section
            out.append(StructureCrumb(id: pid, title: parent.name, action: { store.replaceTop(with: .entity(pid, s)) }))
        }
        out.append(StructureCrumb(id: "here", title: entity.name))
        return out
    }
}
