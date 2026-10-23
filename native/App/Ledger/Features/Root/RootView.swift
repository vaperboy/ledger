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
        .sheet(isPresented: $store.showPhone) { PhoneView().environmentObject(store) }
    }
}

/// iPhone: native bottom tab bar.
struct PhoneShell: View {
    @EnvironmentObject var store: GameStore
    var body: some View {
        TabView(selection: $store.tab) {
            ForEach(AppTab.allCases) { tab in
                TabContent(tab: tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .badge(tab == .inbox ? store.unreadCount : 0)
                    .tag(tab)
            }
        }
        .onChange(of: store.tab) { _, _ in Haptics.tap() }
    }
}

/// iPad: a sidebar with the same five destinations as the iPhone tab bar, then the More pages, and a wide detail area.
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
                        Label(tab.title, systemImage: tab.symbol)
                            .badge(tab == .inbox ? store.unreadCount : 0)
                            .tag(tab)
                    }
                }
                Section("More") {
                    ForEach(PhoneDestination.allCases, id: \.self) { d in
                        Button { store.openMore(d) } label: { Label(d.title, systemImage: d.symbol) }
                    }
                }
                // While the More sheet is up, its own rows (Stats, Settings, ...) are the ones to reach.
                .accessibilityHidden(store.showPhone)
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
        case .inbox: InboxView()
        }
    }
}

struct ToastView: View {
    @EnvironmentObject var store: GameStore
    var body: some View {
        if let t = store.toast {
            Text(t.text)
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
