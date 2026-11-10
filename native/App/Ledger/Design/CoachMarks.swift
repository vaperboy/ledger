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
    case nextDay, happened, needsYou, homeCompany
    case firstPick, firstItemRow, itemPrice, itemSupplier, goalCard, inboxGuided
    case tabBar, customTab
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
        .glassSurface(radius: Theme.Radius.card, raised: true)
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
    static func tutorial(_ step: TutorialStep) -> [CoachMark] {
        switch step {
        case .openCompany:
            return [
                CoachMark(stop: .homeCompany, text: "Tap your company to open it.", passThrough: true, button: ""),
                CoachMark(stop: .groupCard, text: "Tap your company to open it.", passThrough: true, button: ""),
                CoachMark(stop: .tabBar, text: "Open the Home tab, then tap your company.", passThrough: true, button: ""),
            ]
        case .pickSupplier:
            return [
                CoachMark(stop: .itemSupplier, text: "Who supplies it? Keep the suggested supplier, or pick another.", passThrough: true, button: ""),
                CoachMark(stop: .firstPick, text: "Tap the product you want to start with, then press Start with this product.", passThrough: true, button: ""),
                CoachMark(stop: .companyTabs, text: "Tap Sales to choose your first product. Supply is where you change suppliers later.", passThrough: true, button: ""),
                CoachMark(stop: .tabBar, text: "Open the Home tab, then tap your company.", passThrough: true, button: ""),
            ]
        case .setPrice:
            return [
                CoachMark(stop: .itemPrice, text: "Set your price: type it, tap Use market price, or press Keep this price.", passThrough: true, button: ""),
                CoachMark(stop: .firstItemRow, text: "Tap your product to set its price.", passThrough: true, button: ""),
                CoachMark(stop: .companyTabs, text: "Tap Sales to find your product.", passThrough: true, button: ""),
                CoachMark(stop: .tabBar, text: "Open the Home tab, then tap your company.", passThrough: true, button: ""),
            ]
        case .nextDay:
            return [
                CoachMark(stop: .nextDay, text: "Press Next day. One day passes: customers buy and the books move.", passThrough: true, button: ""),
                CoachMark(stop: .tabBar, text: "Go back to the Home tab: Next day is there.", passThrough: true, button: ""),
            ]
        case .openInbox:
            return [
                CoachMark(stop: .phoneInbox, text: "Open the Inbox. Questions and news from your business arrive here.", passThrough: true, button: ""),
                CoachMark(stop: .tabBar, text: "Open the Phone tab. The Inbox is an app on it.", passThrough: true, button: ""),
            ]
        case .readInbox:
            return [
                CoachMark(stop: .inboxGuided, text: "Open the message marked Read next. Anything that needs an answer waits at the top of the Inbox.", passThrough: true, button: "", blocking: false),
                CoachMark(stop: .phoneInbox, text: "Open the Inbox again to read what came in.", passThrough: true, button: "", blocking: false),
                CoachMark(stop: .tabBar, text: "Open the Phone tab, then the Inbox.", passThrough: true, button: "", blocking: false),
            ]
        case .claimGoal:
            return [
                CoachMark(stop: .goalCard, text: "Open your Mission card and claim your first goal when it is ready.", passThrough: true, button: "", blocking: false),
                CoachMark(stop: .tabBar, text: "Open the Home tab: your Mission card is there.", passThrough: true, button: "", blocking: false),
            ]
        }
    }

    static let all: [CoachTour] = [
        CoachTour(id: "group", trigger: .tab(.group), marks: [
            CoachMark(stop: .groupAdd, text: "Add a new company, holding, franchise or club to your group here."),
            CoachMark(stop: .groupPeople, text: "People lists everyone who works for you. Tap it to look.", passThrough: true),
            CoachMark(stop: .groupStructure, text: "Structure shows what you own and who runs it. Tap it to look.", passThrough: true),
            CoachMark(stop: .groupCard, text: "Each card is a company or a stake. Open one to manage it."),
        ]),
        CoachTour(id: "ventures", trigger: .tab(.projects), marks: [
            CoachMark(stop: .venturesHeader, text: "This is what your startups, stakes and funds are worth together."),
            CoachMark(stop: .venturesFound, text: "Found a startup here: pick an idea and put some money in."),
            CoachMark(stop: .venturesBacking, text: "Back other founders here: put money into a pitch for a share of it."),
        ]),
        CoachTour(id: "phone", trigger: .tab(.phone), marks: [
            CoachMark(stop: .phoneGrid, text: "Every app lives here, the Store and the Market too. Tap one to open it."),
            CoachMark(stop: .phoneInbox, text: "The Inbox holds every question waiting for you."),
            CoachMark(stop: .phoneBank, text: "The Bank holds your money, bills and loans.", button: "Done"),
        ]),
        CoachTour(id: "custom", trigger: .tab(.custom), marks: [
            CoachMark(stop: .customTab, text: "This tab is yours. Press and hold it to choose what it opens: it starts on the Inbox. Pick any app, or one of your companies.", button: "Done", fallback: .tabBar),
        ]),
        CoachTour(id: "company", trigger: .route(.company), marks: [
            CoachMark(stop: .companyTabs, text: "Overview is the summary, Team the people, Manage how it runs, Sales what it sells and what you charge, Supply who you buy from and Stats the money."),
            CoachMark(stop: .companyPage, text: "Start on Overview: it shows the cash and what needs you.", button: "Done"),
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
        return tab == .custom && customPath.isEmpty && customTarget == .app(app)
    }
}
