import SwiftUI
import GameCore
import Simulation
import Businesses

/// The Phone tab: a phone home screen (two widgets, a 4-column grid of filled app icons with red bubbles, a dock of four apps). Each app opens as a pushed full screen with its own `AppHeader`
/// and a round back button to this home. The tab owns the navigation stack: apps and the companies they link to are pushed on it,
/// so Back always returns to where the player came from.
struct PhoneHome: View {
    @Environment(Entitlements.self) private var ent
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
    /// The apps that were dimmed the last time the grid looked, and the toast lines for the ones that opened since.
    @State private var lockedBefore: Set<String>?
    @State private var notes: [OrgNote] = []
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

    /// The apps kept in the dock at the foot of the screen, as on a real phone; the rest fill the grid.
    private static let dockApps: [PhoneApp] = [.bank, .accounting, .inbox, .news]

    private var home: some View {
        let badges: [PhoneApp: Int] = store.phoneBadges
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
        let shown: [PhoneApp] = PhoneApp.launcher.filter { gateState($0) != .hidden }
        let grid: [PhoneApp] = shown.filter { !Self.dockApps.contains($0) }
        let dock: [PhoneApp] = shown.filter { Self.dockApps.contains($0) }
        return FixedScreen(spacing: 16, top: 12, maxWidth: 560) {
            VStack(spacing: 22) {
                widgets
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(grid) { app in icon(app, badges) }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .id(store.rootToken(.phone))
        .onAppear { store.endVisits(); lockedBefore = lockedApps }
        .onChange(of: lockedApps) { _, now in
            guard let before = lockedBefore else { lockedBefore = now; return }
            for title in before.subtracting(now).sorted() {
                OrgNote.show($notes, text: "\(title) unlocked", tint: Theme.gold, seconds: 2)
                Haptics.tap()
            }
            lockedBefore = now
        }
        .overlay(alignment: .bottom) { OrgNoteStack(notes: notes).padding(.horizontal, 16).padding(.bottom, clearance + 8) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !dock.isEmpty { PhoneDock(apps: dock) { app in icon(app, badges, label: false) } }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: clearance) }
        .background(PhoneBackdrop())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("phone-home")
    }

    private func icon(_ app: PhoneApp, _ badges: [PhoneApp: Int], label: Bool = true) -> some View {
        AppIcon(app: app, badge: badges[app] ?? 0, lock: gateState(app).lockText, showsLabel: label || gateState(app).lockText != nil) {
            Haptics.tap()
            if app == .luxury { ent.run(.luxuryGivingFootball, "Luxury") { path.append(.app(app)) } } else { path.append(.app(app)) }
        }
    }

    /// The titles of the apps that are dimmed with a lock text right now.
    private var lockedApps: Set<String> {
        Set(PhoneApp.launcher.filter { (app: PhoneApp) -> Bool in gateState(app).lockText != nil }.map { (app: PhoneApp) -> String in app.title })
    }

    /// Where the app's gate stands; everything is open when no game is loaded.
    private func gateState(_ app: PhoneApp) -> GateVisibility {
        guard let e = store.engine else { return GateVisibility.open }
        return app.visibility(e)
    }

    // MARK: Widgets

    /// Two widgets over the grid, as on a phone: the game's date, and net worth with its trend (it opens Stats).
    private var widgets: some View {
        HStack(spacing: 12) {
            dateWidget
            worthWidget
        }
        .frame(height: 148)
    }

    private var dateWidget: some View {
        let d: (weekday: String, day: String, month: String) = dateParts
        let waiting: Int = store.waitingCount
        return PhoneWidget {
            VStack(alignment: .leading, spacing: 0) {
                Text(d.weekday).textStyle(.label, tint: Theme.accent).textCase(.uppercase).lineLimit(1)
                Text(d.day).font(.hero(46)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.6)
                Text(d.month).textStyle(.caption, tint: Theme.inkSoft).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(waiting == 0 ? "Nothing waiting" : "\(waiting) waiting").textStyle(.caption, tint: waiting == 0 ? Theme.inkFaint : Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var worthWidget: some View {
        let history: [Double] = Array((store.engine?.state.netWorthHistory ?? []).suffix(13))
        let now: Double = history.last ?? store.netWorth
        let change: Double = history.count >= 2 ? now - history[history.count - 2] : 0
        let open: Bool = gateState(.stats) == .open
        let tile = PhoneWidget {
            VStack(alignment: .leading, spacing: 2) {
                Text("Net worth").textStyle(.label, tint: Theme.inkFaint).textCase(.uppercase).lineLimit(1)
                Text(store.short(now)).font(.hero(26)).foregroundStyle(now < 0 ? Theme.loss : Theme.ink).lineLimit(1).minimumScaleFactor(0.5)
                if abs(change) >= 0.5 {
                    Text((change > 0 ? "+" : "\u{2212}") + store.short(abs(change)) + " this week").textStyle(.caption, tint: Theme.change(change), numeric: true)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 4)
                Sparkline(values: history, tint: Theme.accent).frame(height: 30).accessibilityHidden(true)
            }
        }
        if open {
            Button { Haptics.tap(); path.append(.app(.stats)) } label: { tile }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Net worth \(store.short(now))")
                .accessibilityIdentifier("phone-widget-worth")
        } else {
            tile.accessibilityElement(children: .combine)
        }
    }

    /// The game's date in three parts: "Tuesday", "2", "February 2027".
    private var dateParts: (weekday: String, day: String, month: String) {
        guard let e = store.engine else { return ("", "", "") }
        let d = GameCalendar.date(week: e.state.week, dayOffset: e.state.day)
        let weekdays: [String] = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let months: [String] = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        return (weekdays[d.weekday % 7], "\(d.day)", "\(months[d.month % 12]) \(d.year)")
    }

}

/// A home-screen widget: a raised rounded tile with a soft edge, content at its top-left.
struct PhoneWidget<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content()
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(shape.fill(Color(hex: 0x1A1B1E).opacity(0.92)))
            .overlay(shape.strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
            .contentShape(shape)
    }
}

/// The dock: up to four apps on a frosted shelf at the foot of the home screen, icons without labels.
struct PhoneDock<Icon: View>: View {
    var apps: [PhoneApp]
    @ViewBuilder var icon: (PhoneApp) -> Icon
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        HStack(spacing: 0) {
            ForEach(apps) { app in icon(app).frame(maxWidth: .infinity) }
        }
        .padding(.horizontal, 10).padding(.vertical, 12)
        .background(shape.fill(Color.white.opacity(0.07)))
        .background(shape.fill(.ultraThinMaterial).opacity(0.6))
        .overlay(shape.strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        .padding(.horizontal, 12).padding(.bottom, 8)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }
}

/// What the Phone home's `path.append(.app(app))` calls become: a push through the store.
@MainActor struct PhonePath {
    var store: GameStore
    func append(_ page: PhoneHome.Page) { store.setPhonePath(store.phonePath + [page]) }
}

/// The home screen wallpaper: the page with a soft champagne glow at the top and a deep green one at the foot.
struct PhoneBackdrop: View {
    var body: some View {
        ZStack {
            Theme.page
            RadialGradient(colors: [Theme.accent.opacity(0.16), Color.clear], center: .topLeading, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color(hex: 0x24443B).opacity(0.55), Color.clear], center: .bottomTrailing, startRadius: 0, endRadius: 620)
        }
        .ignoresSafeArea()
    }
}

/// One app on the grid: a filled icon in the app's own colour, its name under it (not in the dock) and the red bubble.
struct AppIcon: View {
    var app: PhoneApp
    var badge: Int
    /// The lock text of a gate that is near (`Unlocks ...`): the tile is dimmed and does not open.
    var lock: String? = nil
    var showsLabel: Bool = true
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                PhoneIconFace(glyph: app.glyph, tint: app.tint).opacity(lock == nil ? 1 : 0.35)
                if showsLabel {
                    Text(lock ?? app.title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(lock == nil ? Theme.ink : Theme.inkFaint)
                        .multilineTextAlignment(.center).lineLimit(lock == nil ? 1 : 2).minimumScaleFactor(0.75)
                }
            }
            .animation(Motion.quick(reduceMotion), value: lock)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topTrailing) { RedBubble(count: badge).offset(x: -4, y: -6) }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(lock != nil)
        .accessibilityLabel(app.title)
        .accessibilityValue(badge > 0 ? "\(badge) waiting" : "")
        .accessibilityIdentifier("phone-app-\(app.title)")
    }
}

/// The face of a Phone app icon: a squircle filled with the app's colour, lighter at the top, and its glyph in dark ink on it.
struct PhoneIconFace: View {
    var glyph: String
    var tint: Color
    var size: CGFloat = 60

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
        GlyphView(glyph: glyph, size: size * 0.48, weight: 1.9, tint: Color(hex: 0x121314))
            .frame(width: size, height: size)
            .background(shape.fill(LinearGradient(colors: [tint, tint.opacity(0.78)], startPoint: .top, endPoint: .bottom)))
            .background(shape.fill(Color(hex: 0x101112)))
            .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.35), radius: 6, y: 3)
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
