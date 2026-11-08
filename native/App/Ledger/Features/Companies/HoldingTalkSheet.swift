import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// A talk with someone at a company whose board the holding sits on: pick the person and the subject, hear them out, then answer.
/// Same people, topics and dialogue as the owner's talks; the engine refuses it when the holding has no seat.
struct HoldingTalkSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.popupClose) private var popupClose
    var holdingID: Int
    var companyID: Int
    @State private var personID: Int?
    @State private var topic: String?

    var body: some View {
        let name: String = store.engine?.state.company(companyID)?.name ?? "Board"
        Group {
            if let e = store.engine {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    if let p = personID, let t = topic {
                        sceneView(e, p, t)
                    } else if let p = personID {
                        topicList(e, p)
                    } else {
                        peopleList(e)
                    }
                }
            }
        }
        .centerSheetTitle("Talk at \(name)")
    }

    @ViewBuilder private func peopleList(_ e: GameEngine) -> some View {
        switch e.holdingOwnerCounterparts(holdingID: holdingID, companyID: companyID) {
        case .success(let people):
            if people.isEmpty {
                Text("Nobody sits at this table yet.").popupText(.body)
            }
            VStack(spacing: 0) {
                ForEach(people) { (c: OwnerMeetings.Counterpart) in
                    PopupChoiceRow(title: c.name, subtitle: c.title, identifier: "holding-talk-\(c.id)") { personID = c.id }
                }
            }
            Text("The holding speaks as an owner of the company.").popupText(.caption)
        case .failure(let f):
            Text(f.reason).popupText(.risk).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func topicList(_ e: GameEngine, _ person: Int) -> some View {
        switch e.holdingOwnerTopics(holdingID: holdingID, companyID: companyID, personID: person) {
        case .success(let topics):
            VStack(spacing: 0) {
                ForEach(topics) { (t: OwnerMeetings.Topic) in
                    PopupChoiceRow(title: t.label, subtitle: t.waitWeeks > 0 ? "Again in \(t.waitWeeks) \(t.waitWeeks == 1 ? "week" : "weeks")" : t.hint,
                                   enabled: t.waitWeeks == 0) { topic = t.id }
                }
            }
        case .failure(let f):
            Text(f.reason).popupText(.risk).fixedSize(horizontal: false, vertical: true)
        }
        Button("Back") { Haptics.tap(); personID = nil }.buttonStyle(TertiaryButtonStyle(fullWidth: true))
    }

    @ViewBuilder private func sceneView(_ e: GameEngine, _ person: Int, _ t: String) -> some View {
        switch e.holdingOwnerScene(holdingID: holdingID, companyID: companyID, personID: person, topic: t) {
        case .success(let sc):
            DialogueQuote(speaker: sc.speaker, lines: sc.lines)
            Text("Your answer").popupText(.subtitle).padding(.top, Theme.Space.xs)
            VStack(spacing: 0) {
                ForEach(sc.choices) { (c: OwnerMeetings.Choice) in
                    PopupChoiceRow(title: c.label, subtitle: c.preview) { choose(person, sc.topic, c.id, c.label) }
                }
            }
        case .failure(let f):
            Text(f.reason).popupText(.risk).fixedSize(horizontal: false, vertical: true)
        }
        Button("Back") { Haptics.tap(); topic = nil }.buttonStyle(TertiaryButtonStyle(fullWidth: true))
    }

    private func choose(_ person: Int, _ topic: String, _ choice: String, _ label: String) {
        let hid: Int = holdingID
        let cid: Int = companyID
        let r: Result<OwnerMeetings.Outcome, HoldingStakes.Failure>? = store.act { (e: inout GameEngine) -> Result<OwnerMeetings.Outcome, HoldingStakes.Failure> in
            e.holdingOwnerChoose(holdingID: hid, companyID: cid, personID: person, topic: topic, choice: choice)
        }
        switch r {
        case .success(let o)?:
            if o.tone == "bad" { Haptics.warning() } else { Haptics.success() }
            popupClose?()
            store.outcome(chosen: label, result: o.text)
        case .failure(let f)?:
            Haptics.warning(); store.show(f.reason, tone: "warn")
        case nil:
            break
        }
    }
}
