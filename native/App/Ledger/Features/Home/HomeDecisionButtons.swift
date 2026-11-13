import SwiftUI
import GameCore
import Countries
import Events
import Simulation

/// One decision on Home: its answers, plus "Later", which moves it to the inbox until it expires.
struct HomeDecisionPopup: View {
    @EnvironmentObject var store: GameStore
    var messageID: Int
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine, let m = e.state.inbox.first(where: { (x: Message) -> Bool in x.id == messageID }), m.status == "open" {
                GamePopup(title: e.displayText(m.title, companyID: m.companyID), showsClose: false, category: .medium, tone: m.tone == "bad" ? .warning : .info,
                          onClose: { store.laterDecision(m) }) {
                    content(e, m)
                }
            }
        }
        .confirmAction($pending)
    }

    private func content(_ e: GameEngine, _ m: Message) -> some View {
        PopupBody {
            let intro: String = e.displayText(m.body, companyID: m.companyID)
            if !intro.isEmpty { Text(intro.tidyMoney).popupText(.subtitle) }
            if m.companyID != 0, let co = e.state.company(m.companyID) {
                Text(co.name).popupText(.caption)
            }
            DecisionChoices(labels: DecisionAnswering.labels(e, m),
                            identifier: { (i: Int) -> String in "home-decision-\(i)" },
                            later: { store.laterDecision(m) },
                            laterIdentifier: "home-decision-later",
                            pick: { (i: Int) in DecisionAnswering.choose(store, e, m, i, ask: { (a: PendingAction) in pending = a }, done: { }) })
        }
    }
}
