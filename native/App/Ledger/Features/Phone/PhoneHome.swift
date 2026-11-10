import SwiftUI
import GameCore
import Simulation
import Businesses

struct PhoneHome: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.tabBarClearance) private var clearance
    private var path: PhonePath { PhonePath(store: store) }
    @State private var order: [PhoneApp] = PhoneLayout.saved()

    private var ordered: [PhoneApp] {
        order.filter { (app: PhoneApp) -> Bool in gateState(app) != .hidden }
    }

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
                    ForEach(ordered) { (app: PhoneApp) in
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
                        .draggable(app.rawValue)
                        .dropDestination(for: String.self) { (items: [String], _: CGPoint) -> Bool in
                            guard let raw = items.first, let moved = PhoneApp(rawValue: raw), moved != app else { return false }
                            withAnimation(Motion.quick(false)) { order = PhoneLayout.move(moved, before: app, in: ordered) }
                            Haptics.tap()
                            return true
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

enum PhoneLayout {
    static let key = "phoneAppOrder"

    static func saved() -> [PhoneApp] {
        let raw: [String] = UserDefaults.standard.stringArray(forKey: key) ?? []
        let known: [PhoneApp] = raw.compactMap { (r: String) -> PhoneApp? in PhoneApp(rawValue: r) }
        let rest: [PhoneApp] = PhoneApp.launcher.filter { (a: PhoneApp) -> Bool in !known.contains(a) }
        var all: [PhoneApp] = known.filter { (a: PhoneApp) -> Bool in PhoneApp.launcher.contains(a) } + rest
        var seen: Set<PhoneApp> = []
        all = all.filter { (a: PhoneApp) -> Bool in seen.insert(a).inserted }
        return all
    }

    static func move(_ app: PhoneApp, before target: PhoneApp, in shown: [PhoneApp]) -> [PhoneApp] {
        var full: [PhoneApp] = saved()
        full.removeAll { (a: PhoneApp) -> Bool in a == app }
        let at: Int = full.firstIndex(of: target) ?? full.count
        full.insert(app, at: at)
        UserDefaults.standard.set(full.map { (a: PhoneApp) -> String in a.rawValue }, forKey: key)
        return full
    }
}
