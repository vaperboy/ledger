import SwiftUI

extension GameStore {
    /// True while Home must keep showing the figures of the day before: a day is running, or a report, the daily report, an ambition
    /// prompt or a queued reward is still waiting for its Continue. It is derived from the store, so it can never be left on.
    var holdsHomeFigures: Bool {
        isAdvancing || reportSheet != nil || dailySheet != nil || ambitionPrompt || !celebrationQueue.isEmpty || !unlockQueue.isEmpty
    }
}

/// Shows the previous value while `store.holdsHomeFigures`, and the live value otherwise. When the hold ends the shown value changes
/// from the old to the new one, so `moneyFlash` inside `content` counts and flashes then (not under the report).
struct HeldValue<Content: View>: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.scenePhase) private var scenePhase
    var live: Double
    var content: (Double) -> Content
    @State private var held: Double?

    init(live: Double, @ViewBuilder content: @escaping (Double) -> Content) {
        self.live = live
        self.content = content
    }

    var body: some View {
        let blocked: Bool = store.holdsHomeFigures
        let shown: Double = blocked ? (held ?? live) : live
        content(shown)
            .onAppear { if held == nil { held = live } }
            .onChange(of: live) { _, new in if !store.holdsHomeFigures { held = new } }
            .onChange(of: blocked) { _, now in if !now { held = live } }
            .onChange(of: scenePhase) { _, phase in if phase == .active && !store.holdsHomeFigures { held = live } }
    }
}
