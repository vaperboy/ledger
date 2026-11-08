import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The Boardroom tab of an entity: sit down with the people who run each company (a short dialogue, then a choice with a visible consequence),
/// ask the board, and propose replacing a CEO. Logic: `OwnerMeetings`, `ManagerModel.boardVote` / `proposeCEOChange`. With co-owners the
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
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            Text("Board of " + entity.name).textStyle(.title).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("boardroom-title")
            ForEach(cos) { (c: Company) in
                companyCard(c, showName: cos.count > 1)
            }
            GroupEntityBoard(engine: engine, entity: entity)
        }
        .confirmAction($pending)
        .centerSheet(item: $talk, category: .medium, tone: .info) { (t: TalkRef) in
            OwnerTalkSheet(companyID: t.companyID, personID: t.personID) { (id: Int) in proposeReplace(id) }.environmentObject(store)
        }
        .centerSheet(item: $round, category: .medium, tone: .info) { (r: RoundRef) in
            BoardRoundSheet(companyID: r.companyID).environmentObject(store)
        }
    }

    // MARK: One company

    private func companyCard(_ c: Company, showName: Bool) -> some View {
        let people: [OwnerMeetings.Counterpart] = engine.ownerCounterparts(companyID: c.id)
        let advisory: Bool = engine.boardIsAdvisory(companyID: c.id)
        let dir: String? = engine.companyDirective(companyID: c.id)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            if showName { Text(c.name).textStyle(.label, tint: Theme.inkFaint) }
            // The state of the board leads: who decides, then the direction it was given.
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(advisory ? "You decide, the board advises" : "Co-owners vote by their shares").textStyle(.figure)
                    .fixedSize(horizontal: false, vertical: true)
                Text(advisory ? "Votes bind once a co-owner joins." : "Ask the board before a big move.")
                    .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                if let dir { Text("Direction: " + OwnerMeetings.directiveLabel(dir)).textStyle(.caption, tint: Theme.ink).padding(.top, Theme.Space.xxs) }
            }
            .accessibilityElement(children: .combine)
            // The people come first: a talk is the main thing to do here; the board round follows as one row.
            Text("Talk to").textStyle(.label, tint: Theme.inkFaint).padding(.top, Theme.Space.s)
            if people.isEmpty {
                EmptyState(glyph: Glyph.person, title: "Nobody runs \(c.name) but you", message: "Appoint a manager under Management.", centered: false)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(people.enumerated()), id: \.element.id) { (n: Int, p: OwnerMeetings.Counterpart) in
                        if n > 0 { Hairline().padding(.leading, 40 + Theme.Space.m) }
                        personRow(c, p)
                    }
                }
            }
            VStack(spacing: 0) {
                Hairline().padding(.leading, 28 + Theme.Space.m)
                LedgerRow(leading: .glyph(Glyph.achievements), title: "Ask the board",
                          identifier: "boardroom-call-\(c.id)", action: { round = RoundRef(companyID: c.id) })
            }
        }
    }

    private func personRow(_ c: Company, _ p: OwnerMeetings.Counterpart) -> some View {
        let cid: Int = c.id
        let pid: Int = p.id
        return Button { Haptics.tap(); talk = TalkRef(companyID: cid, personID: pid) } label: {
            HStack(spacing: Theme.Space.m) {
                if let person = engine.state.people[pid] {
                    ThumbnailView(kind: .person, key: person.role, size: 40, initials: p.name, face: person.faceKey)
                }
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(p.name).textStyle(.headline).lineLimit(1)
                    Text(p.title).textStyle(.caption, tint: Theme.inkFaint).lineLimit(1)
                }
                Spacer(minLength: Theme.Space.s)
                Text("Talk").textStyle(.body, tint: Theme.accent, weight: .medium)
                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
            }
            .padding(.vertical, Theme.Space.s)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
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
        let button: String = alone ? "Replace" : "Put it to the vote"
        pending = PendingAction(title: "Replace the CEO of \(name)?", message: msg, button: button, destructive: true) {
            let r: ManagerModel.CEOChange? = store.act { $0.proposeCEOChange(companyID: id) }
            switch r {
            case .dismissed?: Haptics.success(); store.outcome(chosen: button, result: "The CEO of \(name) was replaced. Appoint a successor under Management.")
            case .voteFailed(let p)?: Haptics.warning(); store.outcome(chosen: button, result: "The co-owners voted it down: \(p)% of the shares were for it. The CEO stays.")
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
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if voting {
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
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            VStack(spacing: 0) {
                ForEach(topics) { (t: OwnerMeetings.Topic) in
                    PopupChoiceRow(title: t.label, subtitle: t.waitWeeks > 0 ? "Again in \(t.waitWeeks) \(t.waitWeeks == 1 ? "week" : "weeks")" : "",
                                   enabled: t.waitWeeks == 0) { topic = t.id }
                }
                if isCEO {
                    PopupChoiceRow(title: "Replace them as CEO") { voting = true }
                }
            }
        }
    }

    /// The person speaks first (their name once, then their words as quotes), then your answers with what each one does.
    private func sceneView(_ sc: OwnerMeetings.Scene) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            DialogueQuote(speaker: sc.speaker, lines: sc.lines)
            Text("Your answer").popupText(.subtitle).padding(.top, Theme.Space.xs)
            VStack(spacing: 0) {
                ForEach(sc.choices) { (c: OwnerMeetings.Choice) in
                    PopupChoiceRow(title: c.label, subtitle: c.preview) { choose(sc.topic, c.id, c.label) }
                }
            }
            Button("Back") { Haptics.tap(); topic = nil }.buttonStyle(TertiaryButtonStyle(fullWidth: true))
        }
    }

    private func choose(_ topic: String, _ choice: String, _ label: String) {
        let c: Int = companyID
        let p: Int = personID
        let r: OwnerMeetings.Outcome? = store.act { $0.ownerChoose(companyID: c, personID: p, topic: topic, choice: choice) } ?? nil
        if let r {
            if r.tone == "bad" { Haptics.warning() } else { Haptics.success() }
            // The talk ends with one outcome popup: what you answered and what came of it.
            dismiss()
            store.outcome(chosen: label, result: r.text)
        }
    }

    private func voteView(_ e: GameEngine) -> some View {
        let v: ManagerModel.BoardVote = e.ceoVote(companyID: companyID)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            BoardVoteLines(vote: v, kind: "ceo")
            Button(v.active ? "Put it to the vote" : "Replace them") { Haptics.tap(); dismiss(); onReplace(companyID) }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: Theme.loss))
            Button("Back") { Haptics.tap(); voting = false }.buttonStyle(TertiaryButtonStyle(fullWidth: true))
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
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    if let k = kind {
                        BoardVoteLines(vote: e.advisoryVote(kind: k, companyID: companyID), kind: k)
                        Button("Back") { Haptics.tap(); kind = nil }.buttonStyle(TertiaryButtonStyle(fullWidth: true))
                    } else {
                        let lines: [OwnerMeetings.RoundLine] = e.boardRound(companyID: companyID)
                        if lines.isEmpty {
                            EmptyState(glyph: Glyph.person, title: "Nobody sits at this table yet", message: "Appoint a manager under Management.", centered: false)
                        }
                        ForEach(lines) { (l: OwnerMeetings.RoundLine) in
                            DialogueQuote(speaker: "\(l.name) \u{00B7} \(l.title)", lines: [l.text])
                        }
                        Text("Ask the board").popupText(.subtitle).padding(.top, Theme.Space.xs)
                        VStack(spacing: 0) {
                            PopupChoiceRow(title: "Should we sell it?", identifier: "board-ask-sell") { kind = "sell" }
                            PopupChoiceRow(title: "Should we close it?", identifier: "board-ask-close") { kind = "close" }
                            PopupChoiceRow(title: "Should we replace the CEO?", subtitle: "Managers advise; co-owners vote by shares", identifier: "board-ask-ceo") { kind = "ceo" }
                        }
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
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(question).popupText(.subtitle)
            Text(vote.active ? "Co-owners vote by shares." : "You decide alone.").popupText(.caption)
            ForEach(vote.advice + vote.board) { (l: ManagerModel.VoteLine) in line(l, shares: false) }
            ForEach(vote.owners.filter { (l: ManagerModel.VoteLine) -> Bool in !l.isYou }) { (l: ManagerModel.VoteLine) in line(l, shares: true) }
            if vote.active {
                Text(vote.passes ? "It would pass with \(Int(vote.percentYes.rounded()))% of the shares." : "It would fail: only \(Int(vote.percentYes.rounded()))% of the shares are for it.")
                    .popupText(vote.passes ? .effect : .risk)
                if vote.pushedThroughAlone { Text("Everyone else is against it: going ahead upsets the board.").popupText(.risk) }
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

/// What someone says in a meeting: their name once, then each line as a quote beside a thin accent rule.
struct DialogueQuote: View {
    var speaker: String
    var lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(speaker).popupText(.rowLabel)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                ForEach(Array(lines.enumerated()), id: \.offset) { (_: Int, l: String) in
                    Text("\u{201C}\(l)\u{201D}").popupText(.body).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, Theme.Space.m)
            .overlay(alignment: .leading) { Rectangle().fill(Theme.accent.opacity(0.5)).frame(width: 1.5) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One option of a popup that leads on (a topic, an answer, a question to the board): a plain row with a chevron and a hairline above.
struct PopupChoiceRow: View {
    var title: String
    var subtitle: String = ""
    var enabled: Bool = true
    var identifier: String = ""
    var action: () -> Void

    var body: some View {
        Button { Haptics.tap(); action() } label: {
            HStack(spacing: Theme.Space.s) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(title).popupText(.button).fixedSize(horizontal: false, vertical: true)
                    if !subtitle.isEmpty { Text(subtitle).popupText(.caption).fixedSize(horizontal: false, vertical: true) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: Theme.ivoryDim)
            }
            .padding(.vertical, Theme.Space.s)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 0.5) }
        .modifier(OptionalIdentifier(identifier: identifier))
    }
}
