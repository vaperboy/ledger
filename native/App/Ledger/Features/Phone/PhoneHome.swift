import SwiftUI
import GameCore
import Simulation
import Businesses

/// The Phone tab: a home screen of apps (time and date, a 4-column grid with red bubbles). Market and Store are apps here. Each app opens
/// as a pushed full screen with its own `AppHeader` and a round back button to this home. The tab owns the navigation stack: apps and the
/// companies they link to are pushed on it, so Back always returns to where the player came from.
struct PhoneHome: View {
    @Environment(Entitlements.self) private var ent
    @EnvironmentObject var store: GameStore
    @Environment(\.tabBarClearance) private var clearance
    /// The Phone stack lives in the store; opening an app from the grid pushes through it like every other link.
    private var path: PhonePath { PhonePath(store: store) }

    var body: some View {
        NavigationStack(path: Binding(get: { store.phonePath }, set: { store.setPhonePath($0) })) {
            home
                .companyRouteDestinations()
        }
    }

    private var home: some View {
        let badges: [PhoneApp: Int] = store.phoneBadges
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
        return FixedScreen(spacing: 16, top: 16, maxWidth: 560, overflowScrolls: true) {
            VStack(spacing: 16) {
                clock
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(PhoneApp.launcher) { app in
                        if gateState(app) != .hidden {
                            AppIcon(app: app, badge: badges[app] ?? 0, lock: gateState(app).lockText, quietDot: app == .desk && store.deskWaitingNow) {
                                Haptics.tap()
                                if app == .luxury { ent.run(.luxuryGivingFootball, "Luxury") { path.append(.app(app)) } } else { path.append(.app(app)) }
                            }
                            .coachAnchor(.phoneBank, enabled: app == .bank)
                            .coachAnchor(.phoneInbox, enabled: app == .inbox)
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
    func append(_ page: NavRoute) { store.setPhonePath(store.phonePath + [page]) }
}
