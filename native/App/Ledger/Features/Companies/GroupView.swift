import SwiftUI
import GameCore
import Businesses
import Simulation

/// The Group tab, built to the approved mockups: a header with a round icon, the serif title and a grey line, then underline tabs
/// Overview, Structure, Board, Deals and More (a menu of every other Group page). There is no Money tab here: the group's money is
/// managed in the Bank app, and Overview carries a "Manage in Bank" link to it. The tabs live in `GroupTabs.swift`.
struct GroupView: View {
    @EnvironmentObject var store: GameStore
    @State private var path: [CompanyRoute] = []
    @State private var tab: GroupTab = .overview
    @State private var more: GroupMorePage = .holdings
    @State private var showGiving = false
    @State private var showNewHolding = false

    var body: some View {
        NavigationStack(path: $path) {
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
                    .scrollIndicators(.hidden)
                }
            }
            .ledgerBackground()
            .toolbar(.hidden, for: .navigationBar)
            .companyRouteDestinations()
            .navigationDestination(isPresented: $showGiving) { GivingView() }
            .navigationDestination(isPresented: $showNewHolding) { NewHoldingView() }
            .routeRequests(for: .group, path: $path)
            .onAppear { sendMoneyToBank() }
            .onChange(of: store.moneySection) { _, _ in sendMoneyToBank() }
        }
    }

    /// Group > Money is gone. An old deep link to a money section (loans, invest, taxes) opens the Bank app instead.
    private func sendMoneyToBank() {
        if store.moneySection != nil { store.moneySection = nil; store.openApp(.bank) }
    }

    /// Board decisions waiting, as a red count on the Board tab.
    private var badges: [GroupTab: Int] {
        guard let e = store.engine else { return [:] }
        let n = e.boardKeys.filter { e.boardIsActive(key: $0) }.reduce(0) { $0 + e.boardMeetings(key: $1).filter { $0.status.isEmpty }.count }
        return n > 0 ? [.board: n] : [:]
    }

    private var subtitle: String {
        switch tab {
        case .overview: return "Holdings · Chains · Franchises · Board"
        case .structure: return "Who owns what"
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

    @ViewBuilder private func content(_ e: GameEngine) -> some View {
        switch tab {
        case .overview: GroupOverviewTab(engine: e, goStructure: { tab = .structure }, openMore: { more = $0; tab = .more })
        case .structure: GroupStructureTab(engine: e) { more = $0; tab = .more }
        case .board: GroupBoardTab(engine: e) { more = $0; tab = .more }
        case .deals: GroupDealsTab(engine: e) { more = $0; tab = .more }
        case .more: GroupMoreTab(engine: e, page: more, pick: { more = $0 }, showGiving: { showGiving = true })
        }
    }
}
