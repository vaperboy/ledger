import SwiftUI
import GameCore
import Businesses
import Simulation

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
    @State private var cursor: [String: Int] = [:]
    @State private var passed: [String: Int] = [:]
    @State private var activeID: String?
    @State private var readyKey: String = ""

    private var firstCompanyID: Int? {
        guard let e = store.engine else { return nil }
        return e.state.companies.first { (c: Company) -> Bool in c.status.isLive }?.id
    }

    private var blocked: Bool {
        host.hasVisible || store.popupOpen || !store.unlockQueue.isEmpty || store.workerPopup != nil || store.isAdvancing
    }

    /// Supplier pages are a side trip inside a guide step: the player chooses or looks there, so no mark covers them.
    private var onSupplierPage: Bool {
        guard let r = store.path(for: store.tab).last else { return false }
        switch r {
        case .supplier, .supplierOwner: return true
        default: return false
        }
    }

    private func atRoot(_ t: AppTab) -> Bool { store.tab == t && store.path(for: t).isEmpty }

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

    private func available(_ m: CoachMark, _ geo: GeometryProxy) -> Bool {
        guard let a = m.anchor(in: anchors) else { return false }
        let onScreen: CGRect = geo[a].intersection(CGRect(origin: .zero, size: geo.size))
        return !onScreen.isNull && onScreen.width > 8 && onScreen.height > 8
    }

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

    private func remaining(_ t: CoachTour, after i: Int, _ geo: GeometryProxy) -> Int {
        var n: Int = 0
        var k: Int = i + 1
        while k < t.marks.count {
            if available(t.marks[k], geo) { n += 1 }
            k += 1
        }
        return n
    }

    private func tutorialMark(_ step: TutorialStep, _ geo: GeometryProxy) -> CoachMark? {
        CoachTours.tutorial(step).first { (m: CoachMark) -> Bool in available(m, geo) }
    }

    private var tutorialPosition: Int { (TutorialStep.allCases.firstIndex(where: { (s: TutorialStep) -> Bool in s == store.tutorialStep }) ?? 0) + 1 }

    private func noteCompanyOpened() {
        if companyOnTop { store.tutorialAdvance(from: .openCompany) }
    }

    private func noteInboxOpened() {
        if store.showsApp(.inbox) { store.tutorialAdvance(from: .openInbox) }
    }

    private func endIfAbandoned() {
        if store.tutorialActive && firstCompanyID == nil { store.tutorialFinish() }
    }

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let step: TutorialStep? = store.tutorialStep
            let tutMark: CoachMark? = step.flatMap { (s: TutorialStep) -> CoachMark? in tutorialMark(s, geo) }
            let tour: CoachTour? = step == nil ? pick(geo) : nil
            let index: Int? = tour.flatMap { (t: CoachTour) -> Int? in nextIndex(t, from: cursor[t.id] ?? 0, geo) }
            let tutKey: String = step.flatMap { (s: TutorialStep) -> String? in tutMark.map { (m: CoachMark) -> String in "tutorial.\(s.rawValue).\(m.stop)" } } ?? ""
            let key: String = blocked ? "" : (step != nil ? (onSupplierPage ? "" : tutKey) : (tour?.id ?? ""))
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
            .task(id: key) {
                guard !key.isEmpty else { readyKey = ""; return }
                let wait: Double = key.hasPrefix("tutorial.") ? 0.25 : (CoachTours.all.first(where: { (t: CoachTour) -> Bool in t.id == key })?.delay ?? 0.6)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                if !Task.isCancelled { readyKey = key }
            }
            .onChange(of: tour?.id) { _, id in activeID = id }
        }
        .onChange(of: store.path(for: store.tab).count) { _, _ in noteCompanyOpened(); noteInboxOpened() }
        .onChange(of: store.tab) { _, _ in noteCompanyOpened(); noteInboxOpened() }
        .onAppear {
            endIfAbandoned()
            noteCompanyOpened()
            noteInboxOpened()
        }
    }

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
