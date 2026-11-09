import SwiftUI
import GameCore
import Businesses
import Simulation

/// Runs the guided help of `CoachTours` over every tab: the new player's step-by-step tutorial (it leads the other help while it runs) and a
/// short tour for each tab, company page and phone app the first time it opens. One card at a time; it waits (hidden) while any popup is up,
/// an announcement is queued or a day is playing, and a tour is never shown again after it ends or is skipped.
struct CoachTourHost: ViewModifier {
    @Environment(\.popupHost) private var popupHost

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(CoachAnchorKey.self) { (anchors: [CoachStop: Anchor<CGRect>]) in
            if let host = popupHost { CoachTourLayer(host: host, anchors: anchors) }
        }
    }
}

private struct CoachTourLayer: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject var host: PopupHost
    var anchors: [CoachStop: Anchor<CGRect>]
    @State private var seen: Set<String> = Set(CoachTours.all.filter { (t: CoachTour) -> Bool in FirstRunFlags.seen(t.key) }.map { (t: CoachTour) -> String in t.id })
    /// Table index of the mark a tour is on, and how many marks it has already passed (for the "n of m" count).
    @State private var cursor: [String: Int] = [:]
    @State private var passed: [String: Int] = [:]
    /// The tour on show stays the one on show until it stops being eligible.
    @State private var activeID: String?
    /// The tour key that has held long enough to be drawn; empty while waiting.
    @State private var readyKey: String = ""

    // MARK: Conditions

    private var firstCompanyID: Int? {
        guard let e = store.engine else { return nil }
        return e.state.companies.first { (c: Company) -> Bool in c.type != "hold" && c.status.isLive }?.id
    }

    /// Anything that must be read or answered first: a popup, a queued announcement, a day in progress.
    private var blocked: Bool {
        host.hasVisible || store.popupOpen || !store.unlockQueue.isEmpty || store.workerPopup != nil || store.isAdvancing
    }

    private func atRoot(_ t: AppTab) -> Bool { store.tab == t && store.path(for: t).isEmpty }

    /// A company page is on top of the tab being shown (pushed).
    private var companyOnTop: Bool {
        if let r = store.path(for: store.tab).last {
            switch r {
            case .company, .companyAt, .companyPart: return true
            default: return false
            }
        }
        return false
    }

    private func triggerHolds(_ t: CoachTour) -> Bool {
        switch t.trigger {
        case .tab(let tab):
            return atRoot(tab)
        case .unlock(let id, let tab):
            guard atRoot(tab), let e = store.engine else { return false }
            return Unlocks.unlockedFeatures(e.state).contains(id)
        case .route(let r):
            switch r {
            case .company: return companyOnTop
            case .app(let a): return store.showsApp(a)
            }
        }
    }

    // MARK: Marks on screen

    /// True when the mark's view is on screen (an anchor whose page is off to the side does not count).
    private func available(_ m: CoachMark, _ geo: GeometryProxy) -> Bool {
        guard let a = m.anchor(in: anchors) else { return false }
        let onScreen: CGRect = geo[a].intersection(CGRect(origin: .zero, size: geo.size))
        return !onScreen.isNull && onScreen.width > 8 && onScreen.height > 8
    }

    /// The first mark at or after `from` that is on screen.
    private func nextIndex(_ t: CoachTour, from: Int, _ geo: GeometryProxy) -> Int? {
        guard from >= 0, from < t.marks.count else { return nil }
        for i in from..<t.marks.count where available(t.marks[i], geo) { return i }
        return nil
    }

    private func eligible(_ t: CoachTour, _ geo: GeometryProxy) -> Bool {
        if seen.contains(t.id) || !triggerHolds(t) { return false }
        return nextIndex(t, from: cursor[t.id] ?? 0, geo) != nil
    }

    private func pick(_ geo: GeometryProxy) -> CoachTour? {
        let list: [CoachTour] = CoachTours.all.filter { (t: CoachTour) -> Bool in eligible(t, geo) }
        if let a = activeID, let t = list.first(where: { (x: CoachTour) -> Bool in x.id == a }) { return t }
        return list.first
    }

    /// How many marks after `i` are on screen now.
    private func remaining(_ t: CoachTour, after i: Int, _ geo: GeometryProxy) -> Int {
        var n: Int = 0
        var k: Int = i + 1
        while k < t.marks.count {
            if available(t.marks[k], geo) { n += 1 }
            k += 1
        }
        return n
    }

    // MARK: Tutorial

    /// The mark the tutorial shows now: the first of the step's places that is on screen.
    private func tutorialMark(_ step: TutorialStep, _ geo: GeometryProxy) -> CoachMark? {
        CoachTours.tutorial(step).first { (m: CoachMark) -> Bool in available(m, geo) }
    }

    private var tutorialPosition: Int { (TutorialStep.allCases.firstIndex(where: { (s: TutorialStep) -> Bool in s == store.tutorialStep }) ?? 0) + 1 }

    /// Keeps the player on the guided path: the first product is chosen on the Sales page of the company, and Next day is on Home.
    private func guideNavigation() {
        guard let step = store.tutorialStep, !blocked, store.tab == .company else { return }
        let atRoot: Bool = store.path(for: .company).isEmpty
        if step.locksPlay, atRoot, let id = firstCompanyID {
            store.openCompany(id, section: .salesMarket)
        } else if step == .nextDay, !atRoot {
            store.setPath([], for: .company)
        }
    }

    /// The guide has nothing left to point at when the company is gone.
    private func endIfAbandoned() {
        if store.tutorialActive && firstCompanyID == nil { store.tutorialFinish() }
    }

    // MARK: Body

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let step: TutorialStep? = store.tutorialStep
            let tutMark: CoachMark? = step.flatMap { (s: TutorialStep) -> CoachMark? in tutorialMark(s, geo) }
            // While the tutorial runs it leads: the other tours wait for it to end.
            let tour: CoachTour? = step == nil ? pick(geo) : nil
            let index: Int? = tour.flatMap { (t: CoachTour) -> Int? in nextIndex(t, from: cursor[t.id] ?? 0, geo) }
            let tutKey: String = step.flatMap { (s: TutorialStep) -> String? in tutMark.map { (m: CoachMark) -> String in "tutorial.\(s.rawValue).\(m.stop)" } } ?? ""
            let key: String = blocked ? "" : (step != nil ? tutKey : (tour?.id ?? ""))
            let drawn: Bool = !key.isEmpty && readyKey == key
            ZStack {
                if let m = tutMark {
                    CoachMarks(marks: [m], anchors: anchors, step: 0, visible: drawn,
                               position: tutorialPosition, total: TutorialStep.allCases.count,
                               onNext: { }, onSkip: { store.tutorialFinish() })
                } else if let t = tour, let i = index {
                    let later: Int = remaining(t, after: i, geo)
                    let done: Int = passed[t.id] ?? 0
                    CoachMarks(marks: [shownMark(t, i, last: later == 0)], anchors: anchors, step: 0, visible: drawn,
                               position: done + 1, total: done + 1 + later,
                               onNext: { advance(t, from: i, geo) }, onSkip: { finish(t) })
                }
            }
            .allowsHitTesting(drawn)
            // A tour waits for its trigger to hold for a moment, and again after every popup.
            .task(id: key) {
                guard !key.isEmpty else { readyKey = ""; return }
                let wait: Double = key.hasPrefix("tutorial.") ? 0.25 : (CoachTours.all.first(where: { (t: CoachTour) -> Bool in t.id == key })?.delay ?? 0.6)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                if !Task.isCancelled { readyKey = key }
            }
            .onChange(of: tour?.id) { _, id in activeID = id }
        }
        .onChange(of: store.showsApp(.inbox)) { _, open in
            if open { store.tutorialAdvance(from: .openInbox) }
        }
        .onChange(of: store.tutorialStep) { _, _ in guideNavigation() }
        .onChange(of: blocked) { _, _ in guideNavigation() }
        .onChange(of: store.path(for: .company).count) { _, _ in guideNavigation() }
        .onAppear {
            endIfAbandoned()
            if store.showsApp(.inbox) { store.tutorialAdvance(from: .openInbox) }
            guideNavigation()
        }
    }

    /// The mark as drawn: pointing at its fallback when its own view is not there, and "Next" reading "Done" on the last one on screen.
    private func shownMark(_ t: CoachTour, _ i: Int, last: Bool) -> CoachMark {
        var m: CoachMark = t.marks[i]
        if anchors[m.stop] == nil, let f = m.fallback { m.stop = f }
        if last && m.button == "Next" { m.button = "Done" }
        return m
    }

    private func advance(_ t: CoachTour, from i: Int, _ geo: GeometryProxy) {
        if nextIndex(t, from: i + 1, geo) != nil {
            cursor[t.id] = i + 1
            passed[t.id] = (passed[t.id] ?? 0) + 1
        } else {
            finish(t)
        }
    }

    private func finish(_ t: CoachTour) {
        FirstRunFlags.mark(t.key)
        seen.insert(t.id)
        activeID = nil
    }
}
