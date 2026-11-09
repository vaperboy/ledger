import SwiftUI
import GameCore
import Simulation
import Businesses

/// The Phone tab: a home screen of apps (time and date, a 4-column grid with red bubbles),
/// exactly as in native/design/new-look-2026-10/PhoneHome.dc.html. Each app opens as a pushed full screen with its own `AppHeader`
/// and a round back button to this home. The tab owns the navigation stack: apps and the companies they link to are pushed on it,
/// so Back always returns to where the player came from.
struct PhoneHome: View {
    @Environment(Entitlements.self) private var ent
    /// What the Phone stack holds: apps, and whatever they link to (a company, an entity page, another app): the shared `NavRoute`.
    typealias Page = NavRoute

    @EnvironmentObject var store: GameStore
    /// The Store tile appears only after the player confirmed they are 18 or older.
    @AppStorage(AgeConfirmation.key) private var adultConfirmed = false
    @Environment(\.tabBarClearance) private var clearance
    /// The Phone stack lives in the store; opening an app from the grid pushes through it like every other link.
    private var path: PhonePath { PhonePath(store: store) }

    var body: some View {
        NavigationStack(path: Binding(get: { store.phonePath }, set: { store.setPhonePath($0) })) {
            home
                .companyRouteDestinations()
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
                    ForEach(PhoneApp.launcher.filter { $0 != .store || adultConfirmed }) { app in
                        if gateState(app) != .hidden {
                            AppIcon(app: app, badge: badges[app] ?? 0, lock: gateState(app).lockText, quietDot: app == .desk && store.deskWaitingNow) {
                                Haptics.tap()
                                if app == .luxury { ent.run(.luxuryGivingFootball, "Luxury") { path.append(.app(app)) } } else { path.append(.app(app)) }
                            }
                            .coachAnchor(app == .inbox ? .phoneInbox : .phoneBank, enabled: app == .inbox || app == .bank)
                        }
                    }
                }
                .padding(.top, 2)
                .coachAnchor(.phoneGrid)
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

    /// Where the app's gate stands; everything is open when no game is loaded.
    private func gateState(_ app: PhoneApp) -> GateVisibility {
        guard let e = store.engine else { return GateVisibility.open }
        return app.visibility(e)
    }

    private var clock: some View {
        VStack(spacing: 4) {
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.serifTitle(52)).foregroundStyle(Theme.ivory).monospacedDigit()
            }
            Text(dateLine).textStyle(.caption)
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
    /// A small still dot instead of a number: something is waiting but nothing is urgent (the Desk's question of the day).
    var quietDot = false
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                AppIconTile(glyph: app.glyph, tint: app.tint).opacity(lock == nil ? 1 : 0.35).zoomSource(.app(app))
                Text(lock ?? app.title).textStyle(.caption, tint: lock == nil ? Theme.ink : Theme.inkFaint).lineLimit(lock == nil ? 1 : 2).minimumScaleFactor(0.8)
            }
            .animation(Motion.quick(reduceMotion), value: lock)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topTrailing) {
                if quietDot { Circle().fill(Theme.accent).frame(width: 10, height: 10).offset(x: -10, y: -3).accessibilityHidden(true) }
                else { RedBubble(count: badge).offset(x: -2, y: -5) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(lock != nil)
        .accessibilityLabel(app.title)
        .accessibilityValue(quietDot ? "Today's question is waiting" : badge > 0 ? "\(badge) waiting" : "")
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
            .appFirstOpenHelp(app)
            // Where the app's first-open tour points: the strip its header sits in (only on the screen that is on top).
            .overlay(alignment: .top) {
                Color.clear.frame(height: 88).allowsHitTesting(false).coachAnchor(.appHeader, enabled: store.showsApp(app))
            }
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
        case .achievements:
            AchievementsView().appScreen(title: app.title, subtitle: app.subtitle)
        case .luxury:
            LuxuryView()
        case .ventures:
            VenturesFeedApp()
        case .reports:
            ReportsScreen()
        case .activity:
            ActivityView().appScreen(title: app.title, subtitle: app.subtitle)
        case .market:
            // The Market app draws its own header, with its five parts under it.
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
        case .friends:
            FriendsApp()
        case .season:
            SeasonView().appScreen(title: app.title, subtitle: app.subtitle)
        case .desk:
            DeskApp().appScreen(title: app.title, subtitle: app.subtitle)
        case .rivals:
            RivalsApp().appScreen(title: app.title, subtitle: app.subtitle)
        case .store:
            StoreApp()
        }
    }
}
