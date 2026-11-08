import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The quarterly review with the CEO of a company whose board the holding sits on: the same report, direction and budget as the owner's
/// review; the engine refuses it when the holding has no seat.
struct HoldingTalkSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.popupClose) private var popupClose
    var holdingID: Int
    var companyID: Int
    @State private var personID: Int?

    var body: some View {
        let name: String = store.engine?.state.company(companyID)?.name ?? "Board"
        Group {
            if let e = store.engine {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    if let p = personID {
                        reviewView(e, p)
                    } else {
                        peopleList(e)
                    }
                }
            }
        }
        .centerSheetTitle("Review at \(name)")
    }

    @ViewBuilder private func peopleList(_ e: GameEngine) -> some View {
        switch e.holdingOwnerCounterparts(holdingID: holdingID, companyID: companyID) {
        case .success(let people):
            let ceos: [OwnerMeetings.Counterpart] = people.filter { (c: OwnerMeetings.Counterpart) -> Bool in c.position == "ceo" }
            if ceos.isEmpty {
                Text("Nobody runs this company yet.").popupText(.body)
            }
            VStack(spacing: 0) {
                ForEach(ceos) { (c: OwnerMeetings.Counterpart) in
                    PopupChoiceRow(title: c.name, subtitle: c.title, identifier: "holding-talk-\(c.id)") { personID = c.id }
                }
            }
            Text("The holding speaks as an owner of the company.").popupText(.caption)
        case .failure(let f):
            Text(f.reason).popupText(.risk).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func reviewView(_ e: GameEngine, _ person: Int) -> some View {
        switch e.holdingOwnerTopics(holdingID: holdingID, companyID: companyID, personID: person) {
        case .success(let topics):
            if let t = topics.first {
                scene(e, person, t.id)
            } else {
                Text("They hold no review.").popupText(.body)
            }
        case .failure(let f):
            Text(f.reason).popupText(.risk).fixedSize(horizontal: false, vertical: true)
        }
        Button("Back") { Haptics.tap(); personID = nil }.buttonStyle(TertiaryButtonStyle(fullWidth: true))
    }

    @ViewBuilder private func scene(_ e: GameEngine, _ person: Int, _ topic: String) -> some View {
        switch e.holdingOwnerScene(holdingID: holdingID, companyID: companyID, personID: person, topic: topic) {
        case .success(let sc):
            ReviewForm(scene: sc) { (picks: [OwnerMeetings.Choice]) in settle(person, topic, picks) }
        case .failure(let f):
            Text(f.reason).popupText(.risk).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func settle(_ person: Int, _ topic: String, _ picks: [OwnerMeetings.Choice]) {
        let hid: Int = holdingID
        let cid: Int = companyID
        var lines: [String] = []
        var bad = false
        for pick in picks {
            let choice: String = pick.id
            let r: Result<OwnerMeetings.Outcome, HoldingStakes.Failure>? = store.act { (e: inout GameEngine) -> Result<OwnerMeetings.Outcome, HoldingStakes.Failure> in
                e.holdingOwnerChoose(holdingID: hid, companyID: cid, personID: person, topic: topic, choice: choice)
            }
            switch r {
            case .success(let o)?: lines.append(o.text); if o.tone == "bad" { bad = true }
            case .failure(let f)?: Haptics.warning(); store.show(f.reason, tone: "warn"); return
            case nil: break
            }
        }
        guard !lines.isEmpty else { return }
        if bad { Haptics.warning() } else { Haptics.success() }
        popupClose?()
        store.outcome(chosen: picks.map { (x: OwnerMeetings.Choice) -> String in x.label }.joined(separator: ", "), result: lines.joined(separator: "\n"))
    }
}
