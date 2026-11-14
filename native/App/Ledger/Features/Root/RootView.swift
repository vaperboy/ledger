import SwiftUI
import GameCore
import Countries
import Simulation

struct RootView: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var popups = PopupHost()
    @AppStorage(Terms.key) private var termsAccepted = false
    private static let showcase: Bool = ProcessInfo.processInfo.arguments.contains("-showcase")
    private static let showsGameOver: Bool = ProcessInfo.processInfo.arguments.contains("-showcase-gameover")

    var body: some View {
        Group {
            if !termsAccepted && !Self.showcase {
                TermsView { termsAccepted = true }
            } else if store.isLoadingSave {
                ProgressView().tint(Theme.gold).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let e = store.engine {
                if e.state.isGameOver || Self.showsGameOver { GameOverView(engine: e) } else { GameShell() }
            } else { StartView() }
        }
        .background(Theme.page.ignoresSafeArea())
        .scrollDisabled(store.popupOpen)
        .allowsHitTesting(!store.popupOpen)
        .overlay { MotionOverlay() }
        .scrollBounceBehavior(.basedOnSize, axes: [.vertical, .horizontal])
        .transaction { t in if reduceMotion { t.animation = nil } }
        .centerSheet(item: $store.workerPopup, category: .detail, tone: .info) { (w: WorkerPopupRef) -> AnyView in
            AnyView(WorkerProfileSheet(companyID: w.companyID, employeeID: w.id).environmentObject(store))
        }
        .modifier(PostM7Paywall())
        .overlay(alignment: .top) { LinkRewardBanner() }
        .modifier(AccountChoiceHost())
        .overlay { PopupLayer() }
        .overlay { PopupHostLayer(host: popups) }
        .environment(\.popupHost, popups)
        .environment(\.outcomeStore, store)
        .transaction { t in if PowerMode.isLow { t.animation = nil; t.disablesAnimations = true } }
    }
}

struct GameShell: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .regular { SidebarShell() } else { PhoneShell() }
        }
        .modifier(CoachTourHost())
        .task(id: store.engine?.state.week ?? 0) { await online.shareProgress(from: store.engine) }
    }
}

struct PhoneShell: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var items: [PillTabItem] {
        let waiting: Int = store.waitingCount
        return AppTab.allCases.map { (tab: AppTab) -> PillTabItem in
            PillTabItem(id: tab.rawValue, title: store.title(for: tab), glyph: store.glyph(for: tab), accent: tab.accent,
                        badge: tab == .phone ? waiting : 0, changeable: false, locked: store.tabLockReason(tab) != nil)
        }
    }

    private var selection: Binding<String> {
        Binding<String>(get: { store.tab.rawValue }, set: { raw in if let t = AppTab(rawValue: raw) { store.selectTab(t) } })
    }

    var body: some View {
        TabPager { (tab: AppTab) in
            TabContent(tab: tab)
        }
        .environment(\.tabBarClearance, PillTabBar.height + 16)
        .accessibilityAction(.escape) { store.returnToPreviousTab() }
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                PillTabBar(items: items, selection: selection, onReselect: { raw in
                    if let t = AppTab(rawValue: raw) { Haptics.tap(); store.selectTab(t) }
                })
                .coachAnchor(.tabBar)
            }
        }
        .onChange(of: store.tab) { _, _ in Haptics.tap() }
    }
}

struct SidebarShell: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<AppTab?>(get: { store.tab }, set: { if let t = $0, t != store.tab { store.selectTab(t); Haptics.tap() } })) {
                if let e = store.engine {
                    Section {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.state.player.name).textStyle(.headline, weight: .semibold).lineLimit(1)
                            Text("\(e.homeCountry.flag) \(GameCalendar.dateString(week: e.state.week, dayOffset: e.state.day)) · week \(e.state.week + 1)")
                                .textStyle(.caption, tint: Theme.inkFaint).lineLimit(1)
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                }
                Section {
                    ForEach(AppTab.allCases) { (tab: AppTab) in
                        SidebarLabel(title: store.title(for: tab), symbol: store.tabLockReason(tab) != nil ? "lock" : tab.symbol)
                            .badge(tab == .phone ? store.waitingCount : 0)
                            .tag(tab)
                    }
                }
            }
            .navigationTitle("Ledger")
            .scrollContentBackground(.hidden)
            .background(Theme.walnutRaised)
        } detail: {
            TabContent(tab: store.tab).id(store.tab)
        }
    }
}

struct TabContent: View {
    @EnvironmentObject var store: GameStore
    var tab: AppTab
    var body: some View {
        if store.tabLockReason(tab) != nil {
            Color.clear.ledgerBackground()
        } else {
            unlocked
        }
    }

    @ViewBuilder private var unlocked: some View {
        switch tab {
        case .company: CompaniesView()
        case .custom: CustomTabView()
        case .group: GroupView()
        case .projects: ProjectsView()
        case .phone: PhoneHome()
        }
    }
}
