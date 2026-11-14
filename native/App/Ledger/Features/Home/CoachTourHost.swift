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
    @State private var idleKey: String = ""

    private var blocked: Bool {
        host.hasVisible || store.popupOpen || !store.unlockQueue.isEmpty || store.workerPopup != nil || store.isAdvancing
    }

    /// Supplier pages are a side trip: the player looks or chooses there, so no guide mark covers them.
    private var onSupplierPage: Bool {
        guard let r = store.path(for: store.tab).last else { return false }
        switch r {
        case .supplier, .supplierOwner: return true
        default: return false
        }
    }

    private func atRoot(_ t: AppTab) -> Bool { store.tab == t && store.path(for: t).isEmpty }

    private var companyOnTop: Bool { store.path(for: store.tab).last?.companyID != nil }

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

    private func onScreen(_ m: CoachMark, _ geo: GeometryProxy) -> CGRect? {
        guard let a = m.anchor(in: anchors) else { return nil }
        let r: CGRect = geo[a].intersection(CGRect(origin: .zero, size: geo.size))
        return !r.isNull && r.width > 8 && r.height > 8 ? r : nil
    }

    private func available(_ m: CoachMark, _ geo: GeometryProxy) -> Bool { onScreen(m, geo) != nil }

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

    /// The most exact mark of the step whose control is on screen now.
    private func guideMark(_ step: TutorialStep, _ geo: GeometryProxy) -> (mark: CoachMark, hole: CGRect)? {
        for m in CoachTours.tutorial(step) {
            if let r = onScreen(m, geo) { return (m, r.insetBy(dx: -4, dy: -4)) }
        }
        return nil
    }

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            let step: TutorialStep? = store.tutorialStep
            let guide: (mark: CoachMark, hole: CGRect)? = step.flatMap { (s: TutorialStep) -> (mark: CoachMark, hole: CGRect)? in guideMark(s, geo) }
            let tour: CoachTour? = step == nil ? pick(geo) : nil
            let index: Int? = tour.flatMap { (t: CoachTour) -> Int? in nextIndex(t, from: cursor[t.id] ?? 0, geo) }
            let guideKey: String = step.flatMap { (s: TutorialStep) -> String? in guide.map { (g: (mark: CoachMark, hole: CGRect)) -> String in "tutorial.\(s.rawValue).\(g.mark.stop)" } } ?? ""
            let key: String = blocked ? "" : (step != nil ? (onSupplierPage ? "" : guideKey) : (tour?.id ?? ""))
            let drawn: Bool = !key.isEmpty && readyKey == key
            ZStack {
                if drawn, let s = step, let g = guide {
                    GuideMarkView(mark: g.mark, hole: g.hole, size: geo.size,
                                  position: (TutorialStep.allCases.firstIndex(of: s) ?? 0) + 1, total: Tutorial.stepCount,
                                  pointing: idleKey == key, onSkip: { store.tutorialFinish() })
                } else if let t = tour, let i = index {
                    let later: Int = remaining(t, after: i, geo)
                    let done: Int = passed[t.id] ?? 0
                    CoachMarks(marks: [shownMark(t, i, last: later == 0)], anchors: anchors, step: 0, visible: drawn,
                               position: done + 1, total: done + 1 + later,
                               onNext: { advance(t, from: i, geo) }, onSkip: { finish(t) })
                        .allowsHitTesting(drawn)
                }
            }
            .task(id: key) { await settle(key) }
            .onChange(of: tour?.id) { _, id in activeID = id }
        }
        .onChange(of: store.tutorialStep) { _, _ in store.noteTutorialRoute() }
        .onAppear {
            let live: Bool = store.engine?.state.companies.contains(where: { (c: Company) -> Bool in c.status.isLive }) ?? false
            if store.tutorialActive && !live { store.tutorialFinish() }
            store.noteTutorialRoute()
        }
    }

    /// Shows a mark after a short settle; a guide mark then points at its control once the player has waited.
    private func settle(_ key: String) async {
        readyKey = ""
        idleKey = ""
        guard !key.isEmpty else { return }
        let guide: Bool = key.hasPrefix("tutorial.")
        let wait: UInt64 = guide ? GuideTiming.settleNanos : UInt64((CoachTours.all.first(where: { (t: CoachTour) -> Bool in t.id == key })?.delay ?? 0.6) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: wait)
        guard !Task.isCancelled else { return }
        readyKey = key
        guard guide else { return }
        try? await Task.sleep(nanoseconds: GuideTiming.idleNanos)
        guard !Task.isCancelled else { return }
        idleKey = key
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
