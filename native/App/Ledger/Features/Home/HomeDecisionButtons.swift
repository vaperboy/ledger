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
            ForEach(DecisionOrder.shown(m), id: \.self) { (index: Int) in
                option(e, m, index, m.options[index])
            }
            PopupOptionButton(title: "Later", identifier: "home-decision-later") { store.laterDecision(m) }
            Text(laterLine(e, m)).popupText(.caption)
        }
    }

    private func option(_ e: GameEngine, _ m: Message, _ index: Int, _ opt: JSONValue) -> some View {
        let label: String = e.displayText(opt["l"].string, companyID: m.companyID)
        let detail: String = e.displayText(opt["d"].string, companyID: m.companyID)
        let lines: [String] = MessageCard.preview(e, m, opt).filter { (l: String) -> Bool in !detail.contains(l) }
        return VStack(alignment: .leading, spacing: PopupSpace.tight) {
            DecisionAnswerButton(title: label, identifier: "home-decision-\(index)") {
                DecisionAnswering.choose(store, e, m, index, ask: { (a: PendingAction) in pending = a }, done: { })
            }
            if !detail.isEmpty { Text(detail.tidyMoney).popupText(.caption) }
            ForEach(lines, id: \.self) { (line: String) in
                Text(line.tidyMoney).popupText(.effect)
            }
        }
    }

    private func laterLine(_ e: GameEngine, _ m: Message) -> String {
        guard let exp = m.expiresWeek else { return "Later keeps it in your Inbox." }
        let left: Int = exp - e.state.week
        return left > 1 ? "Later keeps it in your Inbox for \(left) weeks." : "Later keeps it in your Inbox until the end of the week."
    }
}
