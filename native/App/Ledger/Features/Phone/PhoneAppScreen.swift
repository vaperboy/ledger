import SwiftUI
import GameCore
import Simulation
import Businesses

struct AppsList: View {
    @Environment(Entitlements.self) private var ent
    @EnvironmentObject var store: GameStore

    var body: some View {
        let badges: [PhoneApp: Int] = store.phoneBadges
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
        FixedScreen(spacing: 16, top: 16, maxWidth: 560, overflowScrolls: true) {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(PhoneApp.launcher) { app in
                    if gateState(app) != .hidden {
                        AppIcon(app: app, badge: badges[app] ?? 0, lock: gateState(app).lockText, quietDot: app == .desk && store.deskWaitingNow) {
                            Haptics.tap()
                            if app == .luxury { ent.run(.luxuryGivingFootball, "Luxury") { store.openApp(app) } } else { store.openApp(app) }
                        }
                    }
                }
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity)
        }
        .background(PhoneBackdrop())
        .onAppear { store.endVisits() }
        .appScreen(title: "Apps", subtitle: "Everything on your phone")
        .accessibilityIdentifier("phone-home")
    }

    private func gateState(_ app: PhoneApp) -> GateVisibility {
        guard let e = store.engine else { return GateVisibility.open }
        return app.visibility(e)
    }
}

struct PhoneBackdrop: View {
    var body: some View {
        RadialGradient(colors: [Color(hex: 0x1B1C1F), Theme.page], center: .top, startRadius: 0, endRadius: 560)
            .background(Theme.page)
            .ignoresSafeArea()
    }
}

struct AppIcon: View {
    var app: PhoneApp
    var badge: Int
    var lock: String? = nil
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

struct PhoneAppScreen: View {
    var app: PhoneApp
    @EnvironmentObject var store: GameStore

    var body: some View {
        if app == .apps || app == .profile {
            PhoneAppContent(app: app)
        } else {
            AppLaunchSplash(glyph: app.glyph, title: app.title, tint: app.tint,
                            palette: app.splashPalette(ownBankIsMain: store.engine?.playerMainBankIsOwn ?? false)) { PhoneAppContent(app: app) }
                .markerBudget()
                .appFirstOpenHelp(app)
                .overlay(alignment: .top) {
                    Color.clear.frame(height: 88).allowsHitTesting(false).coachAnchor(.appHeader, enabled: store.showsApp(app))
                }
                .onAppear { store.markSeen(app) }
                .onChange(of: store.engine?.state.day) { _, _ in store.markSeen(app) }
        }
    }
}

struct PhoneAppContent: View {
    var app: PhoneApp

    var body: some View {
        switch app {
        case .bank:
            BankApp()
        case .inbox:
            InboxView()
        case .news:
            NewsView()
        case .weather:
            WeatherApp()
        case .luxury:
            LuxuryView()
        case .ventures:
            VenturesFeedApp()
        case .reports:
            ReportsScreen()
        case .activity:
            ActivityView().appScreen(title: app.title, subtitle: app.subtitle)
        case .market:
            MarketApp()
        case .reviews:
            ReviewsApp()
        case .settings:
            SettingsView().appScreen(title: app.title, subtitle: app.subtitle)
        case .airStay:
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
            LevelGuard(feature: .season) { SeasonView().appScreen(title: app.title, subtitle: app.subtitle) }
        case .desk:
            DeskApp().appScreen(title: app.title, subtitle: app.subtitle)
        case .rivals:
            RivalsApp().appScreen(title: app.title, subtitle: app.subtitle)
        case .store:
            StoreApp()
        case .country:
            LevelGuard(feature: .government) { CountryApp() }
        case .apps:
            AppsList()
        case .profile:
            ProfileView()
        }
    }
}
