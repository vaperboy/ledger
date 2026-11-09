import SwiftUI
import GameCore
import Countries
import Simulation

/// Chooses between the start screen and the game, and between a tab bar (iPhone) and a sidebar (iPad).
struct RootView: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var popups = PopupHost()
    /// Screenshots only: `-showcase-gameover` shows the end screen over the showcase game.
    private static let showsGameOver: Bool = ProcessInfo.processInfo.arguments.contains("-showcase-gameover")

    var body: some View {
        Group {
            // The account screen comes once, on a new install, before anything else. A profile that waits for its 18+ confirmation
            // comes first of all, so linking is never left half done.
            if online.awaitingAdultConfirmation && store.engine == nil {
                ProfileCreationView()
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
        // Every scroll view and list in the app only bounces when its content is taller (or wider) than the screen: a page that fits stays still.
        .scrollBounceBehavior(.basedOnSize, axes: [.vertical, .horizontal])
        .transaction { t in if reduceMotion { t.animation = nil } }
        .centerSheet(item: $store.workerPopup, category: .detail, tone: .info) { (w: WorkerPopupRef) -> AnyView in
            AnyView(WorkerProfileSheet(companyID: w.companyID, employeeID: w.id).environmentObject(store))
        }
        .centerSheet(isPresented: $store.customPickerOpen, category: .medium, tone: .info) {
            CustomTabPicker().environmentObject(store)
        }
        .modifier(PostM7Paywall())
        // The one popup host: every popup of the app is drawn here, above everything (tab bar included), in queue order.
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
    /// The locked tab whose "what unlocks it" popup is open.
    @State private var lockedTab: AppTab?

    var body: some View {
        Group {
            if sizeClass == .regular { SidebarShell(lockedTab: $lockedTab) } else { PhoneShell(lockedTab: $lockedTab) }
        }
        .modifier(CoachTourHost())
        .hostedPopup(key: "tab-lock-\(lockedTab?.rawValue ?? "")", priority: .panel, active: lockedTab != nil, onClose: { lockedTab = nil }) {
            if let t = lockedTab { TabLockPopup(tab: t, onClose: { lockedTab = nil }).environmentObject(store) }
        }
        // A remembered Custom tab choice is checked against what the player has unlocked, on launch and as the game moves on.
        .onAppear { store.validateCustomTarget() }
        .onChange(of: store.engine?.state.week) { _, _ in store.validateCustomTarget() }
    }
}

/// iPhone: the floating pill tab bar (Ventures, Group, Home, Custom, Phone) over the pages. The system tab bar is hidden; the pages stay
/// alive in a sliding `TabPager`. The tab bar is the only thing that changes tab: every link pushes on the tab it was tapped on.
/// The Phone tab's bubble is the total waiting count.
struct PhoneShell: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tipVisible = false
    @Binding var lockedTab: AppTab?

    private var items: [PillTabItem] {
        let waiting: Int = store.waitingCount
        return AppTab.allCases.map { tab in
            PillTabItem(id: tab.rawValue, title: store.title(for: tab), glyph: store.glyph(for: tab), badge: tab == .phone ? waiting : 0, changeable: tab == .custom,
                         locked: store.isLocked(tab))
        }
    }

    private var selection: Binding<String> {
        Binding<String>(get: { store.tab.rawValue }, set: { raw in if let t = AppTab(rawValue: raw) { open(t) } })
    }

    /// Changes tab. A locked tab opens its popup instead; the Custom tab with no choice yet opens the picker.
    private func open(_ t: AppTab) {
        if store.isLocked(t) { lockedTab = t; return }
        if t == .custom && store.customTarget == nil { store.customPickerOpen = true; return }
        // Another tab keeps the place it had (its pushed screens and scroll position); only a second tap on the open tab goes to its root.
        store.selectTab(t, resetRoot: false)
    }

    var body: some View {
        TabPager { (tab: AppTab) in
            TabContent(tab: tab)
        }
        .environment(\.tabBarClearance, PillTabBar.height + 16)
        // The VoiceOver escape gesture (a two-finger Z) returns to the tab that was open before this one.
        .accessibilityAction(.escape) { store.returnToPreviousTab() }
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
            if tipVisible && !store.popupOpen { customTip }
            PillTabBar(items: items, selection: selection, onReselect: { raw in
                if let t = AppTab(rawValue: raw) { Haptics.tap(); open(t) }
            }, onLongPress: { raw in
                if raw == AppTab.custom.rawValue { store.customPickerOpen = true }
            }, onLocked: { raw in
                if let t = AppTab(rawValue: raw) { lockedTab = t }
            })
            .coachAnchor(.tabBar)
            }
        }
        .onChange(of: store.tab) { _, now in
            Haptics.tap()
            if now != .custom { showCustomTip() }
        }
    }

    /// One-time hint on the first tab change: the Custom tab is the player's own and is changed with a long press.
    private var customTip: some View {
        Button { tipVisible = false } label: {
            Text("Tip: press and hold the Custom tab to choose what it opens.").textStyle(.caption, tint: Theme.ink)
                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
                .background(Capsule().fill(Theme.surfaceRaised))
                .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .padding(.horizontal, Theme.Space.l)
        .transition(.opacity)
        .accessibilityLabel("Tip: press and hold the Custom tab to choose what it opens. Double tap to dismiss.")
        .accessibilityIdentifier("custom-tab-tip")
    }

    private func showCustomTip() {
        guard !FirstRunFlags.seen(FirstRunFlags.customTabTip) else { return }
        FirstRunFlags.mark(FirstRunFlags.customTabTip)
        withAnimation(Motion.quick(reduceMotion)) { tipVisible = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            withAnimation(Motion.quick(reduceMotion)) { tipVisible = false }
        }
    }
}

/// iPad: a sidebar with the same five destinations (the Custom row has a "Change destination" menu) as the iPhone tab bar and a wide detail area. The Phone destination holds the apps.
/// Only the chosen tab is in the detail column: keeping hidden tabs alive made every visited tab's toolbar items, title and search
/// field pile up in the split view's one navigation bar (two More buttons, a stray "+" and the Team search on Group and Inbox).
/// Each tab's navigation stack lives in the store, so what a link pushed on one tab never appears on another.
struct SidebarShell: View {
    @EnvironmentObject var store: GameStore
    @Binding var lockedTab: AppTab?

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<AppTab?>(get: { store.tab }, set: { if let t = $0, t != store.tab { open(t) } })) {
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
                    ForEach(AppTab.allCases) { tab in
                        SidebarLabel(title: store.title(for: tab), symbol: store.isLocked(tab) ? "lock.fill" : tab.symbol)
                            .opacity(store.isLocked(tab) ? 0.45 : 1)
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

    /// Changes tab. A locked tab opens its popup instead; the Custom tab with no choice yet opens the picker.
    private func open(_ t: AppTab) {
        if store.isLocked(t) { lockedTab = t; return }
        if t == .custom && store.customTarget == nil { store.customPickerOpen = true; return }
        store.selectTab(t)
        Haptics.tap()
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
