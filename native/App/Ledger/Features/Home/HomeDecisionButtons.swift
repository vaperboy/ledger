import SwiftUI
import GameCore
import Countries
import Events
import Simulation

struct HomeDecisionButtons: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var message: Message
    @State private var pending: PendingAction?

    static func fits(_ e: GameEngine, _ m: Message) -> Bool {
        guard m.status == "open", m.options.count == 2 else { return false }
        return m.options.allSatisfy { (o: JSONValue) -> Bool in e.displayText(o["l"].string, companyID: m.companyID).count <= 26 }
    }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(Array(message.options.enumerated()), id: \.offset) { (pair: (offset: Int, element: JSONValue)) in
                let label: String = engine.displayText(pair.element["l"].string, companyID: message.companyID)
                if pair.offset == 0 {
                    Button(label) { answer(pair.offset) }
                        .buttonStyle(PrimaryButtonStyle(size: .compact, fullWidth: true))
                        .accessibilityIdentifier("home-decision-\(pair.offset)")
                } else {
                    Button(label) { answer(pair.offset) }
                        .buttonStyle(SecondaryButtonStyle(size: .compact, fullWidth: true))
                        .accessibilityIdentifier("home-decision-\(pair.offset)")
                }
            }
        }
        .confirmAction($pending)
    }

    private func answer(_ index: Int) {
        Haptics.tap()
        DecisionAnswering.choose(store, engine, message, index, ask: { (a: PendingAction) in pending = a }, done: { })
    }
}
