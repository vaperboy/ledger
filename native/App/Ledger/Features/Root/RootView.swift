import SwiftUI

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
        if sizeClass == .regular { SidebarShell() } else { PhoneShell() }
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

/// iPad: a sidebar with the same five destinations and a wide detail area.
struct SidebarShell: View {
    @EnvironmentObject var store: GameStore
    var body: some View {
        NavigationSplitView {
            List(AppTab.allCases, selection: Binding<AppTab?>(get: { store.tab }, set: { if let t = $0 { store.tab = t; Haptics.tap() } })) { tab in
                Label(tab.title, systemImage: tab.symbol)
                    .badge(tab == .inbox ? store.unreadCount : 0)
                    .tag(tab)
            }
            .navigationTitle("Ledger")
            .scrollContentBackground(.hidden)
            .background(Theme.walnutRaised)
        } detail: {
            TabContent(tab: store.tab)
        }
    }
}

struct TabContent: View {
    var tab: AppTab
    var body: some View {
        switch tab {
        case .home: HomeView()
        case .companies: CompaniesView()
        case .group: GroupView()
        case .phone: PhoneView()
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
