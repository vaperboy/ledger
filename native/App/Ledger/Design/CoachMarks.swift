import SwiftUI
import Simulation

enum FirstRunFlags {
    static let tour = "firstRun.tour"
    static let customTabTip = "firstRun.customTabTip"
    static func appHelp(_ appID: String) -> String { "firstRun.appHelp." + appID }
    static func tourFlag(_ id: String) -> String { "firstRun.tour." + id }

    static func seen(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
    static func mark(_ key: String) { UserDefaults.standard.set(true, forKey: key) }
}

enum CoachStop: Hashable {
    case nextDay, happened, homeCompany
    case firstPick, firstItemRow, itemPrice, goalCard, inboxGuided
    case tabBar, customTab, tabItem(String)
    case groupAdd, groupStructure, groupPeople, groupCard
    case venturesHeader, venturesFound, venturesBacking
    case phoneGrid, phoneInbox, phoneBank
    case companyTabs, companyPage
    case appHeader
}

struct CoachAnchorKey: PreferenceKey {
    static let defaultValue: [CoachStop: Anchor<CGRect>] = [:]
    static func reduce(value: inout [CoachStop: Anchor<CGRect>], nextValue: () -> [CoachStop: Anchor<CGRect>]) {
        value.merge(nextValue()) { (_: Anchor<CGRect>, new: Anchor<CGRect>) -> Anchor<CGRect> in new }
    }
}

extension View {
    func coachAnchor(_ stop: CoachStop, enabled: Bool = true) -> some View {
        anchorPreference(key: CoachAnchorKey.self, value: .bounds) { (a: Anchor<CGRect>) -> [CoachStop: Anchor<CGRect>] in
            enabled ? [stop: a] : [:]
        }
    }

    func coachTopStrip(_ stop: CoachStop, height: CGFloat) -> some View {
        overlay(alignment: .top) { Color.clear.frame(height: height).allowsHitTesting(false).coachAnchor(stop) }
    }
}

struct CoachMark: Equatable {
    var stop: CoachStop
    var text: String
    var passThrough: Bool = false
    var button: String = "Next"
    var fallback: CoachStop? = nil
    var skippable: Bool = true
    var blocking: Bool = true

    func anchor(in anchors: [CoachStop: Anchor<CGRect>]) -> Anchor<CGRect>? {
        if let a = anchors[stop] { return a }
        if let f = fallback { return anchors[f] }
        return nil
    }
}

struct CoachMarks: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var marks: [CoachMark]
    var anchors: [CoachStop: Anchor<CGRect>]
    var step: Int
    var visible: Bool
    var position: Int? = nil
    var total: Int? = nil
    var onNext: () -> Void
    var onSkip: () -> Void

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            if visible, step < marks.count, let anchor = anchors[marks[step].stop] {
                let mark: CoachMark = marks[step]
                let hole: CGRect = geo[anchor].intersection(CGRect(origin: .zero, size: geo.size)).insetBy(dx: -6, dy: -6)
                ZStack {
                    dim(size: geo.size, hole: hole, passThrough: mark.passThrough, blocking: mark.blocking)
                    ring(hole)
                    callout(mark, hole: hole, size: geo.size)
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.quick(reduceMotion), value: visible)
        .animation(Motion.quick(reduceMotion), value: step)
    }

    private func dim(size: CGSize, hole: CGRect, passThrough: Bool, blocking: Bool) -> some View {
        var path = Path(CGRect(origin: .zero, size: size))
        path.addRoundedRect(in: hole, cornerSize: CGSize(width: Theme.Radius.card, height: Theme.Radius.card))
        let hit: Path = passThrough ? path : Path(CGRect(origin: .zero, size: size))
        return path.fill(Color.black.opacity(blocking ? 0.62 : 0.3), style: FillStyle(eoFill: true))
            .contentShape(hit, eoFill: true)
            .onTapGesture { }
            .allowsHitTesting(blocking)
            .accessibilityHidden(true)
    }

    private func ring(_ hole: CGRect) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(Theme.accent, lineWidth: 2)
            .frame(width: hole.width, height: hole.height)
            .position(x: hole.midX, y: hole.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func callout(_ mark: CoachMark, hole: CGRect, size: CGSize) -> some View {
        let above: Bool = hole.midY > size.height / 2
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(mark.text).textStyle(.headline, tint: Theme.ink).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Space.s) {
                Text("\(position ?? (step + 1)) of \(total ?? marks.count)").textStyle(.caption, tint: Theme.inkFaint, numeric: true)
                Spacer(minLength: Theme.Space.s)
                if mark.skippable {
                    Button { Haptics.tap(); onSkip() } label: { Text("Skip") }
                        .buttonStyle(PlainTextButtonStyle()).accessibilityIdentifier("coach-skip")
                }
                if !mark.button.isEmpty {
                    Button { Haptics.tap(); onNext() } label: { Text(mark.button) }
                        .buttonStyle(PrimaryButtonStyle(size: .compact)).accessibilityIdentifier("coach-next")
                }
            }
        }
        .padding(Theme.Space.l)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surfaceRaised))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1))
        .padding(.horizontal, Theme.Space.page)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: above ? .bottom : .top)
        .padding(above ? .bottom : .top, above ? size.height - hole.minY + Theme.Space.m : hole.maxY + Theme.Space.m)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

enum CoachTrigger: Equatable {
    case tab(AppTab)
    case unlock(String, AppTab)
    case route(CoachRoute)
}

enum CoachRoute: Equatable {
    case company
    case app(PhoneApp)
}

struct CoachTour {
    var id: String
    var trigger: CoachTrigger
    var marks: [CoachMark]
    var flag: String? = nil
    var delay: Double = 0.6

    var key: String { flag ?? FirstRunFlags.tourFlag(id) }
}

enum CoachTours {
    /// Guide marks for each step, most exact first: the first one whose control is on screen is shown.
    static func tutorial(_ step: TutorialStep) -> [CoachMark] {
        let home: CoachStop = .tabItem(AppTab.company.rawValue)
        let phone: CoachStop = .tabItem(AppTab.phone.rawValue)
        switch step {
        case .openCompany:
            return [
                CoachMark(stop: .homeCompany, text: "Tap your company to open it."),
                CoachMark(stop: .groupCard, text: "Tap your company to open it."),
                CoachMark(stop: home, text: "Tap Home, then your company."),
            ]
        case .setPrice:
            return [
                CoachMark(stop: .firstPick, text: "Pick what you sell first, then tap Start. Its price comes next."),
                CoachMark(stop: .firstItemRow, text: "Tap your product to set its price."),
                CoachMark(stop: .companyTabs, text: "Tap Sales to find your product."),
                CoachMark(stop: .homeCompany, text: "Tap your company to set your first price."),
                CoachMark(stop: home, text: "Tap Home, then your company."),
            ]
        case .nextDay:
            return [
                CoachMark(stop: .nextDay, text: "Tap Next day. A day passes: customers buy and the books move."),
                CoachMark(stop: home, text: "Tap Home: Next day is there."),
            ]
        case .openInbox:
            return [
                CoachMark(stop: .phoneInbox, text: "Open the Inbox. News and questions from your business arrive here."),
                CoachMark(stop: phone, text: "Tap Phone. The Inbox is an app on it."),
            ]
        case .readInbox:
            return [
                CoachMark(stop: .inboxGuided, text: "Open a message to read it."),
                CoachMark(stop: .phoneInbox, text: "Open the Inbox to read what came in."),
                CoachMark(stop: phone, text: "Tap Phone, then the Inbox."),
            ]
        case .claimGoal:
            return [
                CoachMark(stop: .goalCard, text: "A reward is ready. Tap it to claim."),
                CoachMark(stop: home, text: "Tap Home: your reward is there."),
            ]
        }
    }

    static let all: [CoachTour] = [
        CoachTour(id: "group", trigger: .tab(.group), marks: [
            CoachMark(stop: .groupAdd, text: "Add a new company, franchise or club to your group here."),
            CoachMark(stop: .groupPeople, text: "People lists everyone who works for you. Tap it to look.", passThrough: true),
            CoachMark(stop: .groupCard, text: "Each card is a company or a stake. Open one to manage it."),
        ]),
        CoachTour(id: "ventures", trigger: .tab(.projects), marks: [
            CoachMark(stop: .venturesHeader, text: "This is what your startups, stakes and funds are worth together."),
            CoachMark(stop: .venturesFound, text: "Found a startup here: pick an idea and put some money in."),
            CoachMark(stop: .venturesBacking, text: "Back other founders here: put money into a pitch for a share of it."),
        ]),
        CoachTour(id: "phone", trigger: .tab(.phone), marks: [
            CoachMark(stop: .phoneGrid, text: "Every app lives here, the Market too. Tap one to open it."),
            CoachMark(stop: .phoneInbox, text: "The Inbox holds every question waiting for you."),
            CoachMark(stop: .phoneBank, text: "The Bank holds your money, bills and loans.", button: "Done"),
        ]),
        CoachTour(id: "custom", trigger: .tab(.custom), marks: [
            CoachMark(stop: .customTab, text: "The Store: the season pass, plans, gold and boxes.", button: "Done", fallback: .tabBar),
        ]),
        CoachTour(id: "company", trigger: .route(.company), marks: [
            CoachMark(stop: .companyTabs, text: "Overview is the summary, Team the people, Manage how it runs, Sales what it sells and what you charge, and Stats the money."),
            CoachMark(stop: .companyPage, text: "Start on Overview: it shows the cash and what to look at.", button: "Done"),
        ]),
        appTour(.bank),
        appTour(.market),
        appTour(.atlas),
    ]

    private static func appTour(_ app: PhoneApp) -> CoachTour {
        CoachTour(id: "app." + app.rawValue, trigger: .route(.app(app)),
                  marks: [CoachMark(stop: .appHeader, text: app.helpText ?? "", button: "Got it")],
                  flag: FirstRunFlags.appHelp(app.rawValue), delay: 1.2)
    }

    static func coversApp(_ app: PhoneApp) -> Bool {
        all.contains { (t: CoachTour) -> Bool in
            if case .route(.app(let a)) = t.trigger { return a == app }
            return false
        }
    }
}

extension GameStore {
    func showsApp(_ app: PhoneApp) -> Bool {
        if path(for: tab).last == .app(app) { return true }
        return app == .store && tab == .custom && customPath.isEmpty
    }
}
