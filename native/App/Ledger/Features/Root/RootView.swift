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
    /// Screenshots only: `-showcase-gameover` shows the end screen over the showcase game.
    private static let showcase: Bool = ProcessInfo.processInfo.arguments.contains("-showcase")
    private static let showsGameOver: Bool = ProcessInfo.processInfo.arguments.contains("-showcase-gameover")

    var body: some View {
        Group {
            if !termsAccepted && !Self.showcase {
                TermsView { termsAccepted = true }
            } else if online.needsAccountScreen && store.engine == nil {
                AccountWelcomeView()
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
        .overlay { PopupLayer() }
        .overlay { PopupHostLayer(host: popups) }
        .environment(\.popupHost, popups)
        .environment(\.outcomeStore, store)
    }
}

struct GameShell: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .regular { SidebarShell() } else { PhoneShell() }
        }
        .modifier(CoachTourHost())
    }
}

struct PhoneShell: View {
    @EnvironmentObject var store: GameStore

    private var items: [PillTabItem] {
        AppTab.allCases.filter { (tab: AppTab) -> Bool in store.tabShown(tab) }.map { (tab: AppTab) -> PillTabItem in
            PillTabItem(id: tab.rawValue, title: tab.title, glyph: tab.glyph, accent: tab.accent, badge: tab == .market ? store.appBadge(.market) : 0)
        }
    }

    private var selection: Binding<String> {
        Binding<String>(get: { store.tab.rawValue }, set: { raw in if let t = AppTab(rawValue: raw) { store.selectTab(t, resetRoot: false) } })
    }

    var body: some View {
        TabPager { (tab: AppTab) in
            TabContent(tab: tab)
        }
        .environment(\.tabBarClearance, PillTabBar.height + 16)
        .accessibilityAction(.escape) { store.returnToPreviousTab() }
        .overlay(alignment: .bottom) {
            PillTabBar(items: items, selection: selection, onReselect: { raw in
                if let t = AppTab(rawValue: raw) { Haptics.tap(); store.selectTab(t) }
            })
            .coachAnchor(.tabBar)
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
                    ForEach(AppTab.allCases.filter { (tab: AppTab) -> Bool in store.tabShown(tab) }) { tab in
                        SidebarLabel(title: tab.title, symbol: tab.symbol)
                            .badge(tab == .market ? store.appBadge(.market) : 0)
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
    var tab: AppTab
    var body: some View {
        switch tab {
        case .company: CompaniesView()
        case .group: GroupView()
        case .market: AppTabRoot(app: .market, tab: .market)
        case .store: AppTabRoot(app: .store, tab: .store)
        }
    }
}

private struct HidesRootBackKey: EnvironmentKey { static let defaultValue: Bool = false }
extension EnvironmentValues {
    var hidesRootBack: Bool {
        get { self[HidesRootBackKey.self] }
        set { self[HidesRootBackKey.self] = newValue }
    }
}

struct AppTabRoot: View {
    @EnvironmentObject var store: GameStore
    var app: PhoneApp
    var tab: AppTab

    var body: some View {
        NavigationStack(path: Binding<[NavRoute]>(get: { store.path(for: tab) }, set: { store.setPath($0, for: tab) })) {
            PhoneAppContent(app: app)
                .environment(\.hidesRootBack, true)
                .id(store.rootToken(tab))
                .markerBudget()
                .appFirstOpenHelp(app)
                .overlay(alignment: .top) {
                    Color.clear.frame(height: 88).allowsHitTesting(false).coachAnchor(.appHeader, enabled: store.showsApp(app))
                }
                .companyRouteDestinations()
        }
        .onAppear { if store.tab == tab { store.markSeen(app) } }
        .onChange(of: store.tab) { _, now in if now == tab { store.markSeen(app) } }
        .onChange(of: store.engine?.state.day) { _, _ in if store.tab == tab { store.markSeen(app) } }
        .accessibilityIdentifier("tab-root-\(tab.rawValue)")
    }
}
