import SwiftUI
import GameCore
import Countries
import Simulation

/// Chooses between the start screen and the game, and between a tab bar (iPhone) and a sidebar (iPad).
struct RootView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let e = store.engine {
                if e.state.isGameOver { GameOverView(engine: e) } else { GameShell() }
            } else { StartView() }
        }
        .background(Theme.page.ignoresSafeArea())
        .scrollDisabled(store.popupOpen)
        .allowsHitTesting(!store.popupOpen)
        .overlay { PopupLayer() }
        .overlay { MotionOverlay() }
        // Every scroll view and list in the app only bounces when its content is taller (or wider) than the screen: a page that fits stays still.
        .scrollBounceBehavior(.basedOnSize, axes: [.vertical, .horizontal])
        .transaction { t in if reduceMotion { t.animation = nil } }
        .centerSheet(item: $store.workerPopup) { (w: WorkerPopupRef) -> AnyView in
            AnyView(WorkerProfileSheet(companyID: w.companyID, employeeID: w.id).environmentObject(store))
        }
        .centerSheet(isPresented: $store.customPickerOpen) {
            CustomTabPicker().environmentObject(store)
        }
        .overlay { errorPopup }
        .overlay { NotificationBannerLayer(queue: store.banners) }
        .modifier(PostM7Paywall())
    }

    /// An error is told in the same in-game popup as every question, not in an iOS alert.
    @ViewBuilder private var errorPopup: some View {
        if let text = store.errorText {
            GamePopup(title: "Something went wrong", showsClose: false, onClose: { store.errorText = nil }) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(text).font(.system(size: 14)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer(minLength: 0)
                        Button("Close") { store.errorText = nil }
                            .buttonStyle(QuietButtonStyle()).accessibilityIdentifier("error-ok")
                    }
                }
            }
        }
    }
}

struct GameShell: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .regular { SidebarShell() } else { PhoneShell() }
        }
    }
}

/// iPhone: the floating pill tab bar (Ventures, Group, Home, Custom, Phone) over the pages. The system tab bar is hidden; the pages stay
/// alive in a sliding `TabPager`, so each tab keeps its navigation stack and scroll position. The Phone tab's bubble is the total waiting count.
struct PhoneShell: View {
    @EnvironmentObject var store: GameStore

    private var items: [PillTabItem] {
        let waiting: Int = store.waitingCount
        return AppTab.allCases.map { tab in
            PillTabItem(id: tab.rawValue, title: store.title(for: tab), glyph: store.glyph(for: tab), badge: tab == .phone ? waiting : 0, changeable: tab == .custom)
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
        .overlay(alignment: .bottom) {
            PillTabBar(items: items, selection: selection, onReselect: { raw in
                if let t = AppTab(rawValue: raw) { Haptics.tap(); store.selectTab(t) }
            }, onLongPress: { raw in
                if raw == AppTab.custom.rawValue { store.customPickerOpen = true }
            })
        }
        .onChange(of: store.tab) { _, _ in Haptics.tap() }
    }
}

/// iPad: a sidebar with the same five destinations (the Custom row has a "Change destination" menu) as the iPhone tab bar and a wide detail area. The Phone destination holds the apps.
/// Only the chosen tab is in the detail column: keeping hidden tabs alive made every visited tab's toolbar items, title and search
/// field pile up in the split view's one navigation bar (two More buttons, a stray "+" and the Team search on Group and Inbox).
/// Each tab's navigation stack lives in the store, so a company opened in Team never appears in Home and survives a switch of tab.
struct SidebarShell: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<AppTab?>(get: { store.tab }, set: { if let t = $0, t != store.tab { store.selectTab(t); Haptics.tap() } })) {
                if let e = store.engine {
                    Section {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.state.player.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ivory).lineLimit(1)
                            Text("\(e.homeCountry.flag) \(GameCalendar.dateString(week: e.state.week, dayOffset: e.state.day)) · week \(e.state.week + 1)")
                                .font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                }
                Section {
                    ForEach(AppTab.allCases) { tab in
                        SidebarLabel(title: store.title(for: tab), symbol: tab.symbol)
                            .badge(tab == .phone ? store.waitingCount : 0)
                            .tag(tab)
                            .contextMenu {
                                if tab == .custom { Button("Change destination") { store.customPickerOpen = true } }
                            }
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
        case .custom: CustomTabView()
        case .group: GroupView()
        case .projects: ProjectsView()
        case .phone: PhoneHome()
        }
    }
}
