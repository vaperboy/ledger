import SwiftUI
import GameCore
import Simulation
import Businesses

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
        if app == .profile {
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
        case .stats:
            StatsApp()
        case .atlas:
            AtlasApp()
        case .market:
            MarketApp()
        case .luxury:
            LuxuryView()
        case .marketplace:
            MarketplaceApp()
        case .airStay:
            AirStayApp()
        case .techPro:
            TechProApp()
        case .store:
            StoreApp()
        case .competition:
            CompetitionApp()
        case .rankings:
            RankingsApp()
        case .world:
            LevelGuard(feature: .government) { WorldApp() }
        case .inbox:
            InboxView()
        case .news:
            NewsView()
        case .desk:
            DeskApp().appScreen(title: app.title, subtitle: app.subtitle)
        case .season:
            SeasonView().appScreen(title: app.title, subtitle: app.subtitle)
        case .settings:
            SettingsView().appScreen(title: app.title, subtitle: app.subtitle)
        case .profile:
            ProfileView()
        }
    }
}
