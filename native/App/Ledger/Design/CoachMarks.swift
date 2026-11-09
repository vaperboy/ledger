import SwiftUI
import Simulation

/// The one-time "seen" flags of first-run help (tutorial, tab tip, phone app sheets), kept per install in UserDefaults.
enum FirstRunFlags {
    /// Set when the new-player tutorial ends (its step itself lives in the save).
    static let tour = "firstRun.tour"
    static let customTabTip = "firstRun.customTabTip"
    static func appHelp(_ appID: String) -> String { "firstRun.appHelp." + appID }
    /// The seen flag of one tour of `CoachTours` (the first-session tour keeps its original key).
    static func tourFlag(_ id: String) -> String { "firstRun.tour." + id }

    static func seen(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
    static func mark(_ key: String) { UserDefaults.standard.set(true, forKey: key) }
}

/// A place on screen a coach mark can point at.
enum CoachStop: Hashable {
    case nextDay, happened, needsYou, phoneTab
    case firstPick, firstItemRow, itemPrice, inboxGuided
    case tabBar, customTab, customPick
    case groupAdd, groupStructure, groupPeople, groupCard
    case venturesHeader, venturesFound, venturesBacking
    case phoneGrid, phoneInbox, phoneBank
    case companyTabs, companyPage
    case appHeader
}

/// Collects the bounds of every view tagged with `coachAnchor`, so one overlay higher up can cut a hole around any of them.
struct CoachAnchorKey: PreferenceKey {
    static let defaultValue: [CoachStop: Anchor<CGRect>] = [:]
    static func reduce(value: inout [CoachStop: Anchor<CGRect>], nextValue: () -> [CoachStop: Anchor<CGRect>]) {
        value.merge(nextValue()) { (_: Anchor<CGRect>, new: Anchor<CGRect>) -> Anchor<CGRect> in new }
    }
}

extension View {
    /// Marks this view's bounds as the place `stop` points at (no effect when `enabled` is false).
    func coachAnchor(_ stop: CoachStop, enabled: Bool = true) -> some View {
        anchorPreference(key: CoachAnchorKey.self, value: .bounds) { (a: Anchor<CGRect>) -> [CoachStop: Anchor<CGRect>] in
            enabled ? [stop: a] : [:]
        }
    }

    /// Marks a strip of `height` at the top of this view as the place `stop` points at: for a long block whose first lines are what to show.
    func coachTopStrip(_ stop: CoachStop, height: CGFloat) -> some View {
        overlay(alignment: .top) { Color.clear.frame(height: height).allowsHitTesting(false).coachAnchor(stop) }
    }
}

/// One mark of a tour: where it points, its sentence, whether a tap on the highlighted view reaches it (the step is done by using it)
/// and the label of the button that moves on (empty: the step ends by itself).
struct CoachMark: Equatable {
    var stop: CoachStop
    var text: String
    var passThrough: Bool = false
    var button: String = "Next"
    /// Where to point when `stop` is not on screen (a screen that has no hook for it yet).
    var fallback: CoachStop? = nil
    /// False hides Skip: the step cannot be left until it is done.
    var skippable: Bool = true
    /// False lets every tap through the dimmed screen: the card only points, it does not hold the player in place.
    var blocking: Bool = true

    func anchor(in anchors: [CoachStop: Anchor<CGRect>]) -> Anchor<CGRect>? {
        if let a = anchors[stop] { return a }
        if let f = fallback { return anchors[f] }
        return nil
    }
}

/// A dimmed screen with a cut-out around the view the current mark points at, and a small card with one sentence, the step count and Skip.
/// The host owns the step and decides when to show it (`visible`); under Reduce Motion nothing moves or fades.
struct CoachMarks: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var marks: [CoachMark]
    var anchors: [CoachStop: Anchor<CGRect>]
    var step: Int
    var visible: Bool
    /// "n of m" shown on the card; nil: the step number and the count of `marks`.
    var position: Int? = nil
    var total: Int? = nil
    var onNext: () -> Void
    var onSkip: () -> Void

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            if visible, step < marks.count, let anchor = anchors[marks[step].stop] {
                let mark: CoachMark = marks[step]
                // A block taller than the screen is cut to what is on screen.
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
        // The hole lets taps through only when the step is done by using the highlighted view.
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

/// Where a tour starts. `tab`: the tab is showing at its root. `unlock`: the feature is open (the player has earned it) and its tab is
/// showing. `route`: that page is the one on top of the tab being shown.
enum CoachTrigger: Equatable {
    case tab(AppTab)
    case unlock(String, AppTab)
    case route(CoachRoute)
}

enum CoachRoute: Equatable {
    case company
    case app(PhoneApp)
}

/// One guided tour: shown once (its flag is kept per install), when its trigger holds and its first mark is on screen. A mark whose
/// view is not on screen is skipped.
struct CoachTour {
    var id: String
    var trigger: CoachTrigger
    var marks: [CoachMark]
    /// The seen flag when it is not the tour's own (the app tours share the flag of the old help sheet).
    var flag: String? = nil
    /// Seconds the trigger must hold before the tour appears (an app's opening splash plays first).
    var delay: Double = 0.6

    var key: String { flag ?? FirstRunFlags.tourFlag(id) }
}

/// Every tour of the game, in priority order: adding a tour is adding one entry here (and a `.coachAnchor` on each view it points at).
enum CoachTours {
    /// The new player's guided path, one entry per `TutorialStep`: the marks are the places that step can point at, most specific first, and
    /// the first one on screen is shown (so the card also leads the player back to the right screen). Each step is done by using the
    /// highlighted control, so no mark has a Next button; the first two cannot be skipped.
    static func tutorial(_ step: TutorialStep) -> [CoachMark] {
        switch step {
        case .pickProduct:
            return [
                CoachMark(stop: .firstPick, text: "Tap the product you want to start with, then press Start with this product.", passThrough: true, button: "", skippable: false),
                CoachMark(stop: .companyTabs, text: "Tap Sales. This is where you choose what your company sells.", passThrough: true, button: "", skippable: false),
                CoachMark(stop: .tabBar, text: "Open the Home tab, then your company.", passThrough: true, button: "", skippable: false),
            ]
        case .setPrice:
            return [
                CoachMark(stop: .itemPrice, text: "Set your price: drag the slider, pick a quick price, or press Keep this price.", passThrough: true, button: "", skippable: false),
                CoachMark(stop: .firstItemRow, text: "Tap your product to open it. There you set its price.", passThrough: true, button: "", skippable: false),
                CoachMark(stop: .companyTabs, text: "Tap Sales to find your product.", passThrough: true, button: "", skippable: false),
                CoachMark(stop: .tabBar, text: "Open the Home tab, then your company.", passThrough: true, button: "", skippable: false),
            ]
        case .nextDay:
            return [
                CoachMark(stop: .nextDay, text: "Press Next day. One day passes: customers buy and the books move.", passThrough: true, button: ""),
                CoachMark(stop: .tabBar, text: "Go back to the Home tab: Next day is there.", passThrough: true, button: ""),
            ]
        case .openInbox:
            return [
                CoachMark(stop: .phoneInbox, text: "Open the Inbox. Questions and news from your business arrive here.", passThrough: true, button: ""),
                CoachMark(stop: .phoneTab, text: "Open the Phone tab. The Inbox is an app on it.", passThrough: true, button: ""),
            ]
        case .readInbox:
            return [
                CoachMark(stop: .inboxGuided, text: "Open the message marked Read next. Anything that needs an answer waits at the top of the Inbox.", passThrough: true, button: "", blocking: false),
                CoachMark(stop: .phoneInbox, text: "Open the Inbox again to read what came in.", passThrough: true, button: "", blocking: false),
                CoachMark(stop: .phoneTab, text: "Open the Phone tab, then the Inbox.", passThrough: true, button: "", blocking: false),
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
            CoachMark(stop: .phoneGrid, text: "Every app lives here. Tap one to open it."),
            CoachMark(stop: .phoneInbox, text: "The Inbox holds every question waiting for you."),
            CoachMark(stop: .phoneBank, text: "The Bank holds your money, bills and loans.", button: "Done"),
        ]),
        CoachTour(id: "custom", trigger: .tab(.custom), marks: [
            CoachMark(stop: .customTab, text: "This tab is yours. Press and hold it to choose what it opens: the Edit chip shows until you do.", fallback: .tabBar),
            CoachMark(stop: .customPick, text: "Pick any app, or one of your companies.", button: "Done"),
        ]),
        CoachTour(id: "company", trigger: .route(.company), marks: [
            CoachMark(stop: .companyTabs, text: "Overview is the summary, Team the people, Manage how it runs, Sales what it sells and Stats the money."),
            CoachMark(stop: .companyPage, text: "Start on Overview: it shows the cash and what needs you.", button: "Done"),
        ]),
        appTour(.bank),
        appTour(.market),
        appTour(.atlas),
    ]

    /// A first-open tour of a phone app: its help text pointing at the app's header. It replaces that app's one-time help sheet.
    private static func appTour(_ app: PhoneApp) -> CoachTour {
        CoachTour(id: "app." + app.rawValue, trigger: .route(.app(app)),
                  marks: [CoachMark(stop: .appHeader, text: app.helpText ?? "", button: "Got it")],
                  flag: FirstRunFlags.appHelp(app.rawValue), delay: 1.2)
    }

    /// True when a tour introduces this app, so its help sheet stays away.
    static func coversApp(_ app: PhoneApp) -> Bool {
        all.contains { (t: CoachTour) -> Bool in
            if case .route(.app(let a)) = t.trigger { return a == app }
            return false
        }
    }
}

extension GameStore {
    /// True when `app` is the screen on top of the tab being shown: pushed on it, or the Custom tab's own root.
    func showsApp(_ app: PhoneApp) -> Bool {
        if path(for: tab).last == .app(app) { return true }
        return tab == .custom && customPath.isEmpty && customTarget == .app(app)
    }
}
