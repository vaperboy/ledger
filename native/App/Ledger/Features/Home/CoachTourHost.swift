import SwiftUI
import GameCore
import Businesses
import Simulation

/// The four-mark first-run tour of the iPhone shell: Next day, what happened, what needs you, the Phone tab. It starts once the first
/// company exists and the Home tab is showing, waits (hidden) while any popup is up or a day is playing, and is never shown again after
/// it ends or is skipped. A game that is already under way when the tour would start is marked seen without showing it.
struct CoachTourHost: ViewModifier {
    @Environment(\.popupHost) private var popupHost
    @State private var finished: Bool = FirstRunFlags.seen(FirstRunFlags.tour)

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(CoachAnchorKey.self) { (anchors: [CoachStop: Anchor<CGRect>]) in
            if !finished, let host = popupHost {
                CoachTourLayer(host: host, anchors: anchors, onFinish: {
                    FirstRunFlags.mark(FirstRunFlags.tour)
                    finished = true
                })
            }
        }
    }
}

private struct CoachTourLayer: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject var host: PopupHost
    var anchors: [CoachStop: Anchor<CGRect>]
    var onFinish: () -> Void
    @State private var step = 0

    private static let marks: [CoachMark] = [
        CoachMark(stop: .nextDay, text: "This button runs your day. Press it.", passThrough: true, button: ""),
        CoachMark(stop: .happened, text: "This is what happened"),
        CoachMark(stop: .needsYou, text: "This card is what needs you: answers live here"),
        CoachMark(stop: .phoneTab, text: "The phone holds your bank, news and more: two apps are open for you now", passThrough: true, button: "Done"),
    ]

    private var hasCompany: Bool {
        guard let e = store.engine else { return false }
        return e.state.companies.contains { (c: Company) -> Bool in c.type != "hold" && c.status.isLive }
    }

    /// Anything that must be read or answered first: a popup, a queued announcement, a day in progress.
    private var blocked: Bool {
        host.hasVisible || store.popupOpen || !store.unlockQueue.isEmpty || store.customPickerOpen || store.workerPopup != nil || store.isAdvancing
    }

    private var onRightTab: Bool { step >= 3 || store.tab == .company }

    var body: some View {
        let show: Bool = hasCompany && onRightTab && !blocked
        CoachMarks(marks: Self.marks, anchors: anchors, step: step, visible: show,
                   onNext: { advance() }, onSkip: { onFinish() })
            .onChange(of: store.isAdvancing) { _, running in
                if running && step == 0 { step = 1 }
            }
            .onChange(of: store.tab) { _, t in
                if step == 3 && t == .phone { onFinish() }
            }
            .onAppear {
                // A game already past its first day has nothing to introduce.
                if let e = store.engine, e.state.week > 0 || e.state.day > 0 { onFinish() }
            }
    }

    private func advance() {
        if step + 1 < Self.marks.count { step += 1 } else { onFinish() }
    }
}
