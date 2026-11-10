import SwiftUI
import GameCore
import Simulation
import Businesses

struct PhoneHome: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.tabBarClearance) private var clearance
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
                                if let reason = gateState(app).lockText {
                                    Haptics.warning()
                                    store.tellLocked(app, reason: reason)
                                } else {
                                    Haptics.tap()
                                    path.append(.app(app))
                                }
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

    private var dateLine: String {
        guard let e = store.engine else { return "" }
        let d = GameCalendar.date(week: e.state.week, dayOffset: e.state.day)
        let weekdays: [String] = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let months: [String] = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        return "\(weekdays[d.weekday % 7]) \(d.day) \(months[d.month % 12]) \(d.year)"
    }
}

@MainActor struct PhonePath {
    var store: GameStore
    func append(_ page: NavRoute) { store.setPhonePath(store.phonePath + [page]) }
}
