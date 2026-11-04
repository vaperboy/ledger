import SwiftUI
import GameCore
import Simulation

/// The Phone tab: a home screen of apps (time and date, a banner for the most urgent alert, a 4-column grid with red bubbles),
/// exactly as in native/design/new-look-2026-10/PhoneHome.dc.html. Each app opens as a pushed full screen with its own `AppHeader`
/// and a round back button to this home. The tab owns the navigation stack: apps and the companies they link to are pushed on it,
/// so Back always returns to where the player came from.
struct PhoneHome: View {
    /// What the Phone stack holds: an app, or a company a link opened from inside an app. One typed path (not a type-erased
    /// `NavigationPath`), so a company link tapped in the Inbox is pushed on exactly the stack the Inbox itself sits on.
    enum Page: Hashable {
        case app(PhoneApp)
        case company(CompanyRoute)

        /// The record a page shows: two pages with the same key are the same screen, so a link to it goes back to it.
        var key: String {
            switch self {
            case .app(let app): return "app.\(app.rawValue)"
            case .company(let route): return route.key
            }
        }
    }

    @EnvironmentObject var store: GameStore
    @Environment(\.tabBarClearance) private var clearance
    /// The Phone stack lives in the store; opening an app from the grid pushes through it like every other link.
    private var path: PhonePath { PhonePath(store: store) }

    var body: some View {
        NavigationStack(path: Binding(get: { store.phonePath }, set: { store.setPhonePath($0) })) {
            home
                .navigationDestination(for: Page.self) { (page: Page) in destination(page) }
                .companyRouteDestinations()
        }
    }

    @ViewBuilder private func destination(_ page: Page) -> some View {
        switch page {
        case .app(let app): PhoneAppScreen(app: app)
        case .company(let route): CompanyRouteDestination(route: route)
        }
    }

    // MARK: Home screen

    private var home: some View {
        let badges: [PhoneApp: Int] = store.phoneBadges
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
        return FixedScreen(spacing: 16, top: 16, maxWidth: 560) {
            VStack(spacing: 16) {
                clock
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(PhoneApp.launcher) { app in
                        let state: GateVisibility = store.engine.map { (e: GameEngine) -> GateVisibility in app.visibility(e) } ?? .open
                        if state != .hidden {
                            AppIcon(app: app, badge: badges[app] ?? 0, lock: state.lockText) {
                                Haptics.tap()
                                path.append(.app(app))
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
        }
        .id(store.rootToken(.phone))
        .onAppear { store.endVisits() }
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: clearance) }
        .background(PhoneBackdrop())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("phone-home")
    }

    private var clock: some View {
        VStack(spacing: 4) {
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.serifTitle(52)).foregroundStyle(Theme.ivory).monospacedDigit()
            }
            Text(dateLine).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
        }
    }

    /// "Tuesday 2 February 2027": the game's date.
    private var dateLine: String {
        guard let e = store.engine else { return "" }
        let d = GameCalendar.date(week: e.state.week, dayOffset: e.state.day)
        let weekdays: [String] = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let months: [String] = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        return "\(weekdays[d.weekday % 7]) \(d.day) \(months[d.month % 12]) \(d.year)"
    }

}

/// What the Phone home's `path.append(.app(app))` calls become: a push through the store.
@MainActor struct PhonePath {
    var store: GameStore
    func append(_ page: PhoneHome.Page) { store.setPhonePath(store.phonePath + [page]) }
}

/// The soft radial backdrop of the Phone home.
struct PhoneBackdrop: View {
    var body: some View {
        RadialGradient(colors: [Color(hex: 0x1B1C1F), Theme.page], center: .top, startRadius: 0, endRadius: 560)
            .background(Theme.page)
            .ignoresSafeArea()
    }
}

/// One app on the grid: icon tile, label and the red bubble.
struct AppIcon: View {
    var app: PhoneApp
    var badge: Int
    /// The lock text of a gate that is near (`Unlocks ...`): the tile is dimmed and does not open.
    var lock: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                AppIconTile(glyph: app.glyph, tint: app.tint).opacity(lock == nil ? 1 : 0.35)
                Text(lock ?? app.title).font(.system(size: 11.5)).foregroundStyle(lock == nil ? Theme.ivory : Theme.ivoryFaint).lineLimit(lock == nil ? 1 : 2).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topTrailing) { RedBubble(count: badge).offset(x: -2, y: -5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(lock != nil)
        .accessibilityLabel(app.title)
        .accessibilityValue(badge > 0 ? "\(badge) waiting" : "")
        .accessibilityIdentifier("phone-app-\(app.title)")
    }
}

/// What an app opens. Existing screens are reused as they are; the screen's own navigation bar is replaced by `AppHeader`.
struct PhoneAppScreen: View {
    var app: PhoneApp
    @EnvironmentObject var store: GameStore

    var body: some View {
        AppLaunchSplash(glyph: app.glyph, title: app.title, tint: app.tint,
                        palette: app.splashPalette(ownBankIsMain: store.engine?.playerMainBankIsOwn ?? false)) { appContent }
            .markerBudget()
            .onAppear { store.markSeen(app) }
            .onChange(of: store.engine?.state.day) { _, _ in store.markSeen(app) }
    }

    @ViewBuilder private var appContent: some View {
        switch app {
        case .bank:
            // The Bank app draws its own header (the round back goes from an account to the list first).
            BankApp()
        case .accounting:
            // Accounting & Compliance draws its own header (the round back goes up one screen inside the app before it leaves).
            AccountingApp()
        case .inbox:
            InboxView()
        case .news:
            NewsView()
        case .weather:
            WeatherApp()
        case .stats:
            StatsView().appScreen(title: app.title, subtitle: app.subtitle)
        case .goals:
            GoalsView().appScreen(title: app.title, subtitle: app.subtitle)
        case .achievements:
            AchievementsView().appScreen(title: app.title, subtitle: app.subtitle)
        case .world:
            WorldMapApp()
        case .luxury:
            LuxuryView()
        case .ventures:
            VenturesFeedApp()
        case .richList:
            RichListView()
        case .reports:
            ReportsScreen()
        case .market:
            // The Market app draws its own header, with the business selector under it.
            MarketApp()
        case .reviews:
            ReviewsApp()
        case .settings:
            SettingsView().appScreen(title: app.title, subtitle: app.subtitle)
        case .airStay:
            // The three shopping and insurance apps draw their own coloured header and keep their own steps (Back goes up one step first).
            AirStayApp()
        case .techPro:
            TechProApp()
        case .atlas:
            AtlasApp()
        case .marketplace:
            MarketplaceApp()
        }
    }
}
