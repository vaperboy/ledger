import SwiftUI
import GameCore
import Countries
import Simulation

/// Chooses between the start screen and the game, and between a tab bar (iPhone) and a sidebar (iPad).
struct RootView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if let e = store.engine {
                if e.state.isGameOver { GameOverView(engine: e) } else { GameShell() }
            } else { StartView() }
        }
        .overlay(alignment: .top) { ToastView() }
        .alert("Something went wrong", isPresented: Binding(get: { store.errorText != nil }, set: { if !$0 { store.errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.errorText ?? "") }
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

/// iPhone: the floating pill tab bar (Home, Team, Group, Projects, Phone) over the pages. The system tab bar is hidden; the pages stay
/// alive in a `TabView`, so each tab keeps its navigation stack and scroll position. The Phone tab's bubble is the total waiting count.
struct PhoneShell: View {
    @EnvironmentObject var store: GameStore

    private var items: [PillTabItem] {
        let waiting: Int = store.waitingCount
        return AppTab.allCases.map { tab in
            PillTabItem(id: tab.rawValue, title: tab.title, glyph: tab.glyph, badge: tab == .phone ? waiting : 0)
        }
    }

    private var selection: Binding<String> {
        Binding<String>(get: { store.tab.rawValue }, set: { raw in if let t = AppTab(rawValue: raw) { store.tab = t } })
    }

    var body: some View {
        TabView(selection: $store.tab) {
            ForEach(AppTab.allCases) { tab in
                TabContent(tab: tab)
                    .toolbar(.hidden, for: .tabBar)
                    .tag(tab)
            }
        }
        .environment(\.tabBarClearance, PillTabBar.height + 16)
        .overlay(alignment: .bottom) { PillTabBar(items: items, selection: selection) }
        .onChange(of: store.tab) { _, _ in Haptics.tap() }
    }
}

/// iPad: a sidebar with the same five destinations as the iPhone tab bar and a wide detail area. The Phone destination holds the apps.
/// Only the chosen tab is in the detail column: keeping hidden tabs alive made every visited tab's toolbar items, title and search
/// field pile up in the split view's one navigation bar (two More buttons, a stray "+" and the Team search on Group and Inbox).
/// Each tab owns its navigation stack, so a company opened in Team never appears in Company.
struct SidebarShell: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<AppTab?>(get: { store.tab }, set: { if let t = $0, t != store.tab { store.tab = t; Haptics.tap() } })) {
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
                        SidebarLabel(title: tab.title, symbol: tab.symbol)
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
    var tab: AppTab
    var body: some View {
        switch tab {
        case .company: CompaniesView()
        case .team: TeamView()
        case .group: GroupView()
        case .projects: ProjectsView()
        case .phone: PhoneHome()
        }
    }
}

struct ToastView: View {
    @EnvironmentObject var store: GameStore
    var body: some View {
        if let t = store.toast {
            Text(t.text.tidyMoney)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ivory)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .liquidGlassCapsule(tint: Theme.tone(t.tone).opacity(0.5))
                .shadow(radius: 10)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { store.toast = nil }
        }
    }
}
