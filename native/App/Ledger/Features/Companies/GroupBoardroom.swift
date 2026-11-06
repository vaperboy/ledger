import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The Boardroom tab of an entity: sit down with the people who run each company (a short dialogue, then a choice with a visible consequence),
/// call the board round, and propose replacing a CEO. Logic: `OwnerMeetings`, `ManagerModel.boardVote` / `proposeCEOChange`. With co-owners the
/// votes are binding and weighted by shares; when you own it alone the board only advises and you decide. The seats and the agenda stay below.
struct GroupBoardroom: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var entity: GroupEntity
    @State private var talk: TalkRef?
    @State private var round: RoundRef?
    @State private var pending: PendingAction?

    struct TalkRef: Identifiable, Hashable {
        var companyID: Int
        var personID: Int
        var id: String { "\(companyID)-\(personID)" }
    }
    struct RoundRef: Identifiable, Hashable {
        var companyID: Int
        var id: Int { companyID }
    }

    var body: some View {
        let cos: [Company] = entity.members.compactMap { (id: Int) -> Company? in engine.state.company(id) }.filter { (c: Company) -> Bool in c.status.isLive && c.type != "hold" }
        VStack(alignment: .leading, spacing: 14) {
            ForEach(cos) { (c: Company) in
                companyCard(c, showName: cos.count > 1)
            }
            GroupEntityBoard(engine: engine, entity: entity)
        }
        .confirmAction($pending)
        .centerSheet(item: $talk) { (t: TalkRef) in
            OwnerTalkSheet(companyID: t.companyID, personID: t.personID) { (id: Int) in proposeReplace(id) }.environmentObject(store)
        }
        .centerSheet(item: $round) { (r: RoundRef) in
            BoardRoundSheet(companyID: r.companyID).environmentObject(store)
        }
    }

    // MARK: One company

    private func companyCard(_ c: Company, showName: Bool) -> some View {
        let people: [OwnerMeetings.Counterpart] = engine.ownerCounterparts(companyID: c.id)
        let advisory: Bool = engine.boardIsAdvisory(companyID: c.id)
        let dir: String? = engine.companyDirective(companyID: c.id)
        return VStack(alignment: .leading, spacing: 8) {
            if showName { Text(c.name.uppercased()).font(.system(size: 10.5, weight: .medium)).tracking(1.4).foregroundStyle(Theme.gold) }
            Text(advisory ? "You own it alone, so the board advises and you decide. Votes bind once a co-owner joins." : "Co-owners vote by their shares. Ask the board before a big move.")
                .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
            if let dir { Chip(text: "Direction: " + OwnerMeetings.directiveLabel(dir), tint: Theme.gold) }
            Button { Haptics.tap(); round = RoundRef(companyID: c.id) } label: {
                CardRow(glyph: Glyph.achievements, title: "Call the board", subtitle: "Everyone reports from their seat; ask what they think of a big move")
            }.buttonStyle(PressableStyle()).accessibilityIdentifier("boardroom-call-\(c.id)")
            if people.isEmpty {
                Text("Nobody runs \(c.name) but you. Appoint a manager or department heads under Management to talk with them.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            } else {
                Card(padding: 4, radius: Theme.Radius.hero) {
                    VStack(spacing: 0) {
                        ForEach(Array(people.enumerated()), id: \.element.id) { (n: Int, p: OwnerMeetings.Counterpart) in
                            personRow(c, p, first: n == 0)
                        }
                    }
                }
            }
        }
    }

    private func personRow(_ c: Company, _ p: OwnerMeetings.Counterpart, first: Bool) -> some View {
        let cid: Int = c.id
        let pid: Int = p.id
        return Button { Haptics.tap(); talk = TalkRef(companyID: cid, personID: pid) } label: {
            HStack(spacing: 10) {
                if let person = engine.state.people[pid] {
                    ThumbnailView(kind: .person, key: person.role, size: 32, initials: p.name, face: person.faceKey)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                    Text(p.title).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text("Talk").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.gold).frame(minWidth: 44, minHeight: 36, alignment: .trailing)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(minHeight: 46)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { if !first { Rectangle().fill(Theme.divider).frame(height: 1) } }
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("boardroom-talk-\(pid)")
    }

    // MARK: Replacing the CEO

    private func proposeReplace(_ companyID: Int) {
        let id: Int = companyID
        let name: String = engine.state.company(id)?.name ?? "the company"
        let alone: Bool = engine.boardIsAdvisory(companyID: id)
        let msg: String = alone ? "You decide alone. The manager is let go with notice and severance by the country's labour law, and you run \(name) until someone new is appointed."
            : "The co-owners vote by their shares. If it passes the manager is let go with notice and severance; if it fails the CEO learns you tried and you cannot ask again for eight weeks."
        pending = PendingAction(title: "Replace the CEO of \(name)?", message: msg, button: alone ? "Replace" : "Put it to the vote", destructive: true) {
            let r: ManagerModel.CEOChange? = store.act { $0.proposeCEOChange(companyID: id) }
            switch r {
            case .dismissed?: Haptics.success(); store.show("The CEO of \(name) was replaced. Appoint a successor under Management.", tone: "good")
            case .voteFailed(let p)?: Haptics.warning(); store.show("The co-owners voted it down: \(p)% of the shares were for it.", tone: "warn")
            case .blocked(let w)?: Haptics.warning(); store.show("You asked recently. Try again in \(w) \(w == 1 ? "week" : "weeks").", tone: "warn")
            case .refused(let why)?: Haptics.warning(); store.show(why, tone: "warn")
            case nil: break
            }
        }
    }
}

// MARK: - The talk with one person

/// A private meeting: pick what to talk about (by the person's position), hear them out, then choose. The consequence is shown before you pick.
struct OwnerTalkSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var companyID: Int
    var personID: Int
    var onReplace: (Int) -> Void
    @State private var topic: String?
    @State private var outcome: OwnerMeetings.Outcome?
    @State private var voting = false

    var body: some View {
        let who: OwnerMeetings.Counterpart? = store.engine?.ownerCounterparts(companyID: companyID).first { (c: OwnerMeetings.Counterpart) -> Bool in c.id == personID }
        Group {
            if let e = store.engine, let who {
                content(e, who)
            } else {
                Text("They are not here any more.").popupText(.body)
            }
        }
        .centerSheetTitle(who.map { (w: OwnerMeetings.Counterpart) -> String in "\(w.name), \(w.title)" } ?? "Meeting")
    }

    @ViewBuilder private func content(_ e: GameEngine, _ who: OwnerMeetings.Counterpart) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let o = outcome {
                outcomeView(o)
            } else if voting {
                voteView(e)
            } else if let t = topic, let sc = e.ownerScene(companyID: companyID, personID: personID, topic: t) {
                sceneView(sc)
            } else {
                topicList(e, who)
            }
        }
    }

    private func topicList(_ e: GameEngine, _ who: OwnerMeetings.Counterpart) -> some View {
        let topics: [OwnerMeetings.Topic] = e.ownerTopics(companyID: companyID, personID: personID)
        let isCEO: Bool = e.state.company(companyID)?.managerID == personID
        return VStack(alignment: .leading, spacing: 8) {
            Text("What do you want to talk about?").popupText(.subtitle)
            ForEach(topics) { (t: OwnerMeetings.Topic) in
                ChoiceCard(title: t.label, subtitle: t.waitWeeks > 0 ? "You talked about this lately. Again in \(t.waitWeeks) \(t.waitWeeks == 1 ? "week" : "weeks")." : t.hint, selected: false) { topic = t.id }
                    .disabled(t.waitWeeks > 0)
            }
            if isCEO {
                ChoiceCard(title: "Replace them as CEO", subtitle: "See what the board and co-owners think first", selected: false) { voting = true }
            }
        }
    }

    private func sceneView(_ sc: OwnerMeetings.Scene) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(sc.lines.enumerated()), id: \.offset) { (_: Int, l: String) in
                Text("\(sc.speaker): \"\(l)\"").popupText(.body).fixedSize(horizontal: false, vertical: true)
            }
            Text("Your answer").popupText(.subtitle).padding(.top, 4)
            ForEach(sc.choices) { (c: OwnerMeetings.Choice) in
                ChoiceCard(title: c.label, subtitle: c.preview, selected: false) { choose(sc.topic, c.id) }
            }
            QuietButton(title: "Back", fullWidth: true) { topic = nil }
        }
    }

    private func choose(_ topic: String, _ choice: String) {
        let c: Int = companyID
        let p: Int = personID
        let r: OwnerMeetings.Outcome? = store.act { $0.ownerChoose(companyID: c, personID: p, topic: topic, choice: choice) } ?? nil
        if let r {
            if r.tone == "bad" { Haptics.warning() } else { Haptics.success() }
            outcome = r
        }
    }

    private func outcomeView(_ o: OwnerMeetings.Outcome) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(o.text).popupText(o.tone == "bad" ? .risk : .effect).fixedSize(horizontal: false, vertical: true)
            if o.resigned { dismissButton } else {
                QuietButton(title: "Talk about something else", fullWidth: true) { outcome = nil; topic = nil }
                QuietButton(title: "Done", fullWidth: true) { dismiss() }
            }
        }
    }

    private var dismissButton: some View { QuietButton(title: "Close", fullWidth: true) { dismiss() } }

    private func voteView(_ e: GameEngine) -> some View {
        let v: ManagerModel.BoardVote = e.ceoVote(companyID: companyID)
        return VStack(alignment: .leading, spacing: 8) {
            BoardVoteLines(vote: v, kind: "ceo")
            Button(v.active ? "Put it to the vote" : "Replace them") { Haptics.tap(); dismiss(); onReplace(companyID) }
                .buttonStyle(TinyButtonStyle(tint: Theme.loss))
            QuietButton(title: "Back", fullWidth: true) { voting = false }
        }
    }
}

// MARK: - The board round

/// Everybody at the table reports from their seat, and you can ask what they would say to selling, closing or replacing the CEO.
struct BoardRoundSheet: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    @State private var kind: String?

    var body: some View {
        let name: String = store.engine?.state.company(companyID)?.name ?? "Board"
        Group {
            if let e = store.engine {
                VStack(alignment: .leading, spacing: 8) {
                    if let k = kind {
                        BoardVoteLines(vote: e.advisoryVote(kind: k, companyID: companyID), kind: k)
                        QuietButton(title: "Back", fullWidth: true) { kind = nil }
                    } else {
                        let lines: [OwnerMeetings.RoundLine] = e.boardRound(companyID: companyID)
                        if lines.isEmpty { Text("Nobody sits at this table yet. Appoint a manager or department heads under Management.").popupText(.caption) }
                        ForEach(lines) { (l: OwnerMeetings.RoundLine) in
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(l.name) \u{00B7} \(l.title)").popupText(.rowLabel)
                                Text("\"\(l.text)\"").popupText(.body).fixedSize(horizontal: false, vertical: true)
                            }.padding(.vertical, 2)
                        }
                        Text("Ask the board").popupText(.subtitle).padding(.top, 4)
                        ChoiceCard(title: "Should we sell it?", subtitle: "Each seat gives an opinion", selected: false) { kind = "sell" }
                        ChoiceCard(title: "Should we close it?", subtitle: "Each seat gives an opinion", selected: false) { kind = "close" }
                        ChoiceCard(title: "Should we replace the CEO?", subtitle: "Managers advise; co-owners vote by shares", selected: false) { kind = "ceo" }
                    }
                }
            }
        }
        .centerSheetTitle("Board of \(name)")
    }
}

/// The lines of one vote: each adviser, board member and owner with a yes or no and the reason; then whether it passes.
struct BoardVoteLines: View {
    var vote: ManagerModel.BoardVote
    var kind: String

    private var question: String { kind == "sell" ? "Sell the company" : kind == "close" ? "Close the company" : kind == "ceo" ? "Replace the CEO" : "Take the loan" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question).popupText(.subtitle)
            Text(vote.active ? "Co-owners vote by their shares; the board advises." : "You own it alone: everyone advises and you decide.").popupText(.caption)
            ForEach(vote.advice + vote.board) { (l: ManagerModel.VoteLine) in line(l, shares: false) }
            ForEach(vote.owners.filter { (l: ManagerModel.VoteLine) -> Bool in !l.isYou }) { (l: ManagerModel.VoteLine) in line(l, shares: true) }
            if vote.active {
                Text(vote.passes ? "It would pass with \(Int(vote.percentYes.rounded()))% of the shares." : "It would fail: only \(Int(vote.percentYes.rounded()))% of the shares are for it.")
                    .popupText(vote.passes ? .effect : .risk)
                if vote.pushedThroughAlone { Text("Everyone else is against it. Going ahead alone upsets the board and the owners.").popupText(.risk) }
            }
        }
    }

    private func line(_ l: ManagerModel.VoteLine, shares: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(l.name) \u{00B7} \(l.title)" + (shares ? " \(Int(l.percent.rounded()))%" : "") + ": " + (l.yes ? "Yes" : "No")).popupText(.rowLabel)
            if !l.reason.isEmpty { Text(l.reason).popupText(.caption).fixedSize(horizontal: false, vertical: true) }
        }
    }
}
