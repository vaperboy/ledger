import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The Boardroom tab of an entity: who sits on the board, the one list of what it puts to you, and the quarterly review with each CEO.
/// With co-owners the votes bind and go by shares; when you own it alone the board only advises and you decide.
struct GroupBoardroom: View {
    var engine: GameEngine
    var entity: GroupEntity

    private var companies: [Company] {
        entity.members.compactMap { (id: Int) -> Company? in engine.state.company(id) }.filter { (c: Company) -> Bool in c.status.isLive && c.type != "hold" }
    }

    /// Every board the entity's companies sit on, once each.
    private var keys: [String] {
        var out: [String] = []
        for c in companies {
            if let k = engine.boardKey(companyID: c.id), !out.contains(k) { out.append(k) }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            Text("Board of " + entity.name).textStyle(.title).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("boardroom-title")
            BoardroomContent(engine: engine, key: engine.boardKey(companyID: entity.companyID) ?? "", keys: keys,
                             companies: entity.isChain ? Array(companies.prefix(1)) : companies)
        }
    }
}

/// What a board shows, shared by an entity's Boardroom tab and a chain's board page: the table, the decision list and the CEO reviews.
struct BoardroomContent: View {
    var engine: GameEngine
    /// The board whose table is shown.
    var key: String
    /// Every board whose decisions are listed.
    var keys: [String]
    /// The companies whose CEO you review with (a chain: its head store).
    var companies: [Company]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if !key.isEmpty { BoardTable(engine: engine, key: key) }
            BoardDecisions(engine: engine, keys: keys)
            BoardReviews(engine: engine, companies: companies)
        }
    }
}

// MARK: - The quarterly review

/// One row per CEO: the review is held with them once a quarter and sets the direction and the budget.
struct BoardReviews: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var companies: [Company]
    @State private var talk: ReviewRef?

    struct ReviewRef: Identifiable, Hashable {
        var companyID: Int
        var personID: Int
        var id: String { "\(companyID)-\(personID)" }
    }

    private struct ReviewRow: Identifiable {
        var company: Company
        var person: OwnerMeetings.Counterpart
        var wait: Int
        var id: String { "\(company.id)-\(person.id)" }
    }

    private var rows: [ReviewRow] {
        var out: [ReviewRow] = []
        for c in companies {
            for p in engine.ownerCounterparts(companyID: c.id) where p.position == "ceo" {
                out.append(ReviewRow(company: c, person: p, wait: engine.ownerTopics(companyID: c.id, personID: p.id).first?.waitWeeks ?? 0))
            }
        }
        return out
    }

    var body: some View {
        let list: [ReviewRow] = rows
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Quarterly review").textStyle(.label, tint: Theme.inkFaint)
            if list.isEmpty {
                EmptyState(glyph: Glyph.person, title: "Nobody runs it but you", message: "Appoint a manager in the Group to hold a review.", centered: false)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { (n: Int, r: ReviewRow) in
                        if n > 0 { Hairline().padding(.leading, 40 + Theme.Space.m) }
                        row(r, showCompany: companies.count > 1)
                    }
                }
            }
        }
        .centerSheet(item: $talk, category: .medium, tone: .info) { (t: ReviewRef) in
            OwnerReviewSheet(companyID: t.companyID, personID: t.personID).environmentObject(store)
        }
    }

    private func row(_ r: ReviewRow, showCompany: Bool) -> some View {
        let cid: Int = r.company.id
        let pid: Int = r.person.id
        var parts: [String] = []
        if showCompany { parts.append(r.company.name) }
        parts.append(r.person.title)
        if let dir = engine.companyDirective(companyID: cid) { parts.append("Direction: " + OwnerMeetings.directiveLabel(dir).lowercased()) }
        let sub: String = parts.joined(separator: " \u{00B7} ")
        let action: String = r.wait > 0 ? "Again in \(r.wait) \(r.wait == 1 ? "week" : "weeks")" : "Review"
        return Button { Haptics.tap(); talk = ReviewRef(companyID: cid, personID: pid) } label: {
            HStack(spacing: Theme.Space.m) {
                if let person = engine.state.people[pid] {
                    ThumbnailView(kind: .person, key: person.role, size: 40, initials: r.person.name, face: person.faceKey)
                }
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(r.person.name).textStyle(.headline).lineLimit(1)
                    Text(sub).textStyle(.caption, tint: Theme.inkFaint).lineLimit(2)
                }
                Spacer(minLength: Theme.Space.s)
                Text(action).textStyle(.body, tint: r.wait > 0 ? Theme.inkFaint : Theme.accent, weight: .medium)
                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
            }
            .padding(.vertical, Theme.Space.s)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(r.wait > 0)
        .accessibilityIdentifier("boardroom-review-\(pid)")
    }
}

/// The review with the CEO: they report, then you pick a direction and a budget. The pick already in force is marked; only changed picks
/// are made, and the result is told once.
struct ReviewForm: View {
    var scene: OwnerMeetings.Scene
    var settle: ([OwnerMeetings.Choice]) -> Void
    @State private var direction: String?
    @State private var budget: String?

    init(scene: OwnerMeetings.Scene, settle: @escaping ([OwnerMeetings.Choice]) -> Void) {
        self.scene = scene
        self.settle = settle
        _direction = State(initialValue: ReviewForm.current(scene, "direction"))
        _budget = State(initialValue: ReviewForm.current(scene, "budget"))
    }

    /// The engine marks the choice in force with "Current." at the start of its preview.
    private static func current(_ scene: OwnerMeetings.Scene, _ group: String) -> String? {
        scene.choices.first { (c: OwnerMeetings.Choice) -> Bool in c.group == group && c.preview.hasPrefix("Current.") }?.id
    }

    private var changes: [OwnerMeetings.Choice] {
        let nowDirection: String? = ReviewForm.current(scene, "direction")
        let nowBudget: String? = ReviewForm.current(scene, "budget")
        return scene.choices.filter { (c: OwnerMeetings.Choice) -> Bool in
            (c.group == "direction" && c.id == direction && c.id != nowDirection) || (c.group == "budget" && c.id == budget && c.id != nowBudget)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            DialogueQuote(speaker: scene.speaker, lines: scene.lines)
            group("Direction", "direction", $direction)
            group("Budget", "budget", $budget)
            Button("Settle the review") { settle(changes) }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                .disabled(changes.isEmpty)
                .accessibilityIdentifier("boardroom-review-settle")
        }
    }

    private func group(_ title: String, _ group: String, _ selection: Binding<String?>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).popupText(.subtitle).padding(.bottom, Theme.Space.xs)
            ForEach(scene.choices.filter { (c: OwnerMeetings.Choice) -> Bool in c.group == group }) { (c: OwnerMeetings.Choice) in
                option(c, selected: selection.wrappedValue == c.id) { selection.wrappedValue = c.id }
            }
        }
    }

    private func option(_ c: OwnerMeetings.Choice, selected: Bool, pick: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); pick() } label: {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Theme.gold : Theme.ivoryDim)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(c.label).popupText(.button).fixedSize(horizontal: false, vertical: true)
                    Text(c.preview).popupText(.caption).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Theme.Space.s)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 0.5) }
        .accessibilityIdentifier("boardroom-choice-\(c.id)")
    }
}

/// The review held from the owner's seat.
struct OwnerReviewSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var companyID: Int
    var personID: Int

    var body: some View {
        let who: OwnerMeetings.Counterpart? = store.engine?.ownerCounterparts(companyID: companyID).first { (c: OwnerMeetings.Counterpart) -> Bool in c.id == personID }
        let topic: String? = store.engine?.ownerTopics(companyID: companyID, personID: personID).first?.id
        Group {
            if let e = store.engine, let t = topic, let sc = e.ownerScene(companyID: companyID, personID: personID, topic: t) {
                ReviewForm(scene: sc) { (picks: [OwnerMeetings.Choice]) in settle(t, picks) }
            } else {
                Text("They are not here any more.").popupText(.body)
            }
        }
        .centerSheetTitle(who.map { (w: OwnerMeetings.Counterpart) -> String in "Review with \(w.name)" } ?? "Review")
    }

    private func settle(_ topic: String, _ picks: [OwnerMeetings.Choice]) {
        let c: Int = companyID
        let p: Int = personID
        var lines: [String] = []
        var bad = false
        for pick in picks {
            let id: String = pick.id
            let r: OwnerMeetings.Outcome? = store.act { $0.ownerChoose(companyID: c, personID: p, topic: topic, choice: id) } ?? nil
            if let r { lines.append(r.text); if r.tone == "bad" { bad = true } }
        }
        guard !lines.isEmpty else { return }
        if bad { Haptics.warning() } else { Haptics.success() }
        // The review ends with one outcome popup: what you settled and what came of it.
        dismiss()
        store.outcome(chosen: picks.map { (x: OwnerMeetings.Choice) -> String in x.label }.joined(separator: ", "), result: lines.joined(separator: "\n"))
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
                Text(vote.passes ? "It would pass with \(Int(saturating: vote.percentYes.rounded()))% of the shares." : "It would fail: only \(Int(saturating: vote.percentYes.rounded()))% of the shares are for it.")
                    .popupText(vote.passes ? .effect : .risk)
                if vote.pushedThroughAlone { Text("Everyone else is against it: going ahead upsets the board.").popupText(.risk) }
            }
        }
    }

    private func line(_ l: ManagerModel.VoteLine, shares: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(l.name) \u{00B7} \(l.title)" + (shares ? " \(Int(saturating: l.percent.rounded()))%" : "") + ": " + (l.yes ? "Yes" : "No")).popupText(.rowLabel)
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
