import SwiftUI
import GameCore
import Businesses
import Simulation

/// The Group tab, built to the approved mockups: a header with a round icon, the serif title and a grey line, then underline tabs
/// Overview, Structure, Board, Deals and More (a menu of every other Group page). There is no Money tab here: the group's money is
/// managed in the Bank app, and Overview carries a "Manage in Bank" link to it. The tabs live in `GroupTabs.swift`.
struct GroupView: View {
    @EnvironmentObject var store: GameStore
    @State private var tab: GroupTab = .overview
    @State private var more: GroupMorePage = .office
    @State private var part: GroupStructurePart = .ownership
    @State private var showGiving = false
    @State private var showNewHolding = false

    var body: some View {
        NavigationStack(path: Binding(get: { store.path(for: .group) }, set: { store.setPath($0, for: .group) })) {
            VStack(spacing: 0) {
                ReturnLine(tab: .group)
                header
                    .padding(.horizontal, 18).padding(.top, 6)
                GroupTabBar(tab: $tab, more: $more, badges: badges)
                    .padding(.horizontal, 18).padding(.top, 12)
                if let e = store.engine {
                    ScrollView {
                        content(e)
                            .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 40)
                            .frame(maxWidth: 760).frame(maxWidth: .infinity)
                    }
                    .id(store.rootToken(.group))
                    .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
                }
            }
            .ledgerBackground()
            .toolbar(.hidden, for: .navigationBar)
            .companyRouteDestinations()
            .navigationDestination(isPresented: $showGiving) { GivingView() }
            .navigationDestination(isPresented: $showNewHolding) { NewHoldingView() }
            // Choosing Group again: back to the Overview.
            .onChange(of: store.rootToken(.group)) { _, _ in tab = .overview; part = .ownership; showGiving = false; showNewHolding = false }
        }
    }

    /// Board decisions waiting, as a red count on the Board tab.
    private var badges: [GroupTab: Int] {
        guard let e = store.engine else { return [:] }
        let n = e.boardDecisionsWaiting
        return n > 0 ? [.board: n] : [:]
    }

    private var subtitle: String {
        switch tab {
        case .overview: return "Holdings · Chains · Franchises · Board"
        case .structure: return part.sub
        case .board: return "Board, owners and decisions"
        case .deals: return "Franchise offers, acquisitions and group deals"
        case .more: return more.sub
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            IconCircle(glyph: Glyph.group, size: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text("Group").font(.serifTitle(28)).foregroundStyle(Theme.ivory).lineLimit(1)
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if tab == .structure { SmallOutlineButton(title: "Set up holding") { showNewHolding = true } }
        }
    }

    /// Where a Group link lands. Holdings, chains and franchises are parts of Structure and boards are the Board tab; only the group's
    /// own services (office, posts, dividends and tax, rivals, giving) live under More.
    private func open(_ page: GroupMorePage) {
        switch page {
        case .holdings: part = .holdings; tab = .structure
        case .chains, .franchises: part = .chains; tab = .structure
        case .boards: tab = .board
        default: more = page; tab = .more
        }
    }

    @ViewBuilder private func content(_ e: GameEngine) -> some View {
        switch tab {
        case .overview: GroupOverviewTab(engine: e, goStructure: { part = .ownership; tab = .structure }, openMore: open)
        case .structure: GroupStructureTab(engine: e, part: $part, openMore: open)
        case .board: GroupBoardTab(engine: e, openMore: open)
        case .deals: GroupDealsTab(engine: e, openMore: open)
        case .more: GroupMoreTab(engine: e, page: more, pick: { more = $0 }, showGiving: { showGiving = true })
        }
    }
}
