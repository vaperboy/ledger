import SwiftUI
import GameCore
import Simulation

/// The Phone tab: a home screen of apps (time and date, a banner for the most urgent alert, a 4-column grid with red bubbles),
/// exactly as in native/design/new-look-2026-10/PhoneHome.dc.html. Each app opens as a pushed full screen with its own `AppHeader`
/// and a round back button to this home. The tab owns the navigation stack: apps and the companies they link to are pushed on it,
/// so Back always returns to where the player came from.
struct PhoneHome: View {
    @EnvironmentObject var store: GameStore
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            home
                .navigationDestination(for: PhoneApp.self) { app in PhoneAppScreen(app: app) }
                .companyRouteDestinations()
        }
        .onAppear { take() }
        .onChange(of: store.routeRequest) { _, _ in take() }
        .onChange(of: store.phoneAppRequest) { _, _ in take() }
    }

    /// Opens the app a link asked for, and pushes a company a link asked for on this tab.
    private func take() {
        if let r = store.routeRequest, r.tab == .phone {
            store.routeRequest = nil
            path.append(r.route)
        }
        if let app = store.phoneAppRequest {
            store.phoneAppRequest = nil
            path = NavigationPath()
            path.append(app)
        }
    }

    // MARK: Home screen

    private var home: some View {
        let alerts: [PhoneAlert] = store.phoneAlerts
        let badges: [PhoneApp: Int] = store.phoneBadges
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
        return ScrollView {
            VStack(spacing: 16) {
                clock
                if let top = alerts.first { banner(top) }
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(PhoneApp.allCases) { app in
                        AppIcon(app: app, badge: badges[app] ?? 0) {
                            Haptics.tap()
                            path.append(app)
                        }
                    }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
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

    private func banner(_ alert: PhoneAlert) -> some View {
        Button {
            Haptics.tap()
            if alert.messageID != 0 { store.openMessage(alert.messageID) } else { path.append(alert.app) }
        } label: {
            HStack(spacing: 12) {
                GlyphView(glyph: alert.app.glyph, size: 18, weight: 1.6)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(hex: 0x1C1D1F)))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.borderStrong, lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text(alert.source.uppercased() + " · now").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    Text(alert.title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(2).multilineTextAlignment(.leading)
                    if !alert.detail.isEmpty {
                        Text(alert.detail.tidyText).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).lineLimit(3).multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0x1E1F21, opacity: 0.9)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(hex: 0x2F3033), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("phone-banner")
    }
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
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                AppIconTile(glyph: app.glyph)
                Text(app.title).font(.system(size: 11.5)).foregroundStyle(Theme.ivory).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topTrailing) { RedBubble(count: badge).offset(x: -2, y: -5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.title)
        .accessibilityValue(badge > 0 ? "\(badge) waiting" : "")
        .accessibilityIdentifier("phone-app-\(app.title)")
    }
}

/// What an app opens. Existing screens are reused as they are; the screen's own navigation bar is replaced by `AppHeader`.
struct PhoneAppScreen: View {
    var app: PhoneApp

    var body: some View {
        switch app {
        case .bank:
            // Placeholder route: the existing Money screen on its Bank tab. The Bank app is rebuilt on top of this entry.
            FinanceView(section: .bank).appScreen(title: app.title, subtitle: app.subtitle)
        case .inbox:
            InboxView()
        case .news:
            NewsView().appScreen(title: app.title, subtitle: app.subtitle)
        case .stats:
            PhonePagedApp(app: app, pages: [.stats, .activity], first: .stats)
        case .goals:
            PhonePagedApp(app: app, pages: [.goals, .achievements], first: .goals)
        case .achievements:
            PhonePagedApp(app: app, pages: [.goals, .achievements], first: .achievements)
        case .world:
            PhonePagedApp(app: app, pages: [.around, .biggest, .records], first: .around)
        case .luxury:
            LuxuryView().appScreen(title: app.title, subtitle: app.subtitle)
        case .ventures:
            ScrollView {
                VenturesContent()
                    .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .appScreen(title: app.title, subtitle: app.subtitle)
        case .richList:
            RichListView().appScreen(title: app.title, subtitle: app.subtitle)
        case .reports:
            ReportsScreen().appScreen(title: app.title, subtitle: app.subtitle)
        case .settings:
            SettingsView().appScreen(title: app.title, subtitle: app.subtitle)
        }
    }
}

/// An app made of two or three existing screens, switched with a `SegmentedPill` under the header.
struct PhonePagedApp: View {
    var app: PhoneApp
    var pages: [PhonePage]
    @State private var page: PhonePage

    init(app: PhoneApp, pages: [PhonePage], first: PhonePage) {
        self.app = app
        self.pages = pages
        _page = State(initialValue: first)
    }

    var body: some View {
        VStack(spacing: 0) {
            SegmentedPill(items: pages, title: { $0.rawValue }, selection: $page)
                .padding(.horizontal, 18).padding(.bottom, 8)
            content
        }
        .background(Theme.page)
        .appScreen(title: app.title, subtitle: app.subtitle)
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .stats: StatsView()
        case .activity: ActivityView()
        case .goals: GoalsView()
        case .achievements: AchievementsView()
        case .around: WorldAroundView()
        case .biggest: RankingView()
        case .records: WorldRecordsView(page: .rival)
        }
    }
}
