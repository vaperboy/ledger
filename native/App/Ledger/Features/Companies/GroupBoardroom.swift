import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct GroupBoardroom: View {
    var engine: GameEngine
    var entity: GroupEntity

    private var companies: [Company] {
        entity.members.compactMap { (id: Int) -> Company? in engine.state.company(id) }.filter { (c: Company) -> Bool in c.status.isLive }
    }

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

struct BoardroomContent: View {
    var engine: GameEngine
    var key: String
    var keys: [String]
    var companies: [Company]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if !key.isEmpty { BoardTable(engine: engine, key: key) }
            BoardDecisions(engine: engine, keys: keys)
            BoardReviews(engine: engine, companies: companies)
        }
    }
}

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
        dismiss()
        store.outcome(chosen: picks.map { (x: OwnerMeetings.Choice) -> String in x.label }.joined(separator: ", "), result: lines.joined(separator: "\n"))
    }
}

struct BoardMeetingScreen: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var keys: [String]
    @State private var started = false
    @State private var joining = true
    @State private var progress: Double = 0
    @State private var points: [ManagerModel.BoardDecision] = []
    @State private var guests: [ManagerModel.Attendee] = []
    @State private var index = 0
    @State private var current: ManagerModel.MeetingRuling?
    @State private var rulings: [ManagerModel.MeetingRuling] = []
    private static let seconds: Double = 4
    private static let steps: Int = 20

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if joining {
                joinView
            } else if index < points.count {
                questionView(points[index])
            } else {
                summaryView
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.page)
        .frame(maxWidth: 760).frame(maxWidth: .infinity)
        .ledgerBackground()
        .appScreen(title: "Board meeting", subtitle: points.isEmpty ? "" : "\(points.count) \(points.count == 1 ? "question" : "questions")", tab: .group)
        .task { await open() }
    }

    private var joinView: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Waiting for the shareholders to join.").textStyle(.headline)
            ProgressView(value: progress).tint(Theme.accent)
            ForEach(guests.prefix(6)) { (a: ManagerModel.Attendee) in
                tableRow(a, status: a.present && progress >= a.arrives ? "Joined" : "Waiting\u{2026}")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("boardroom-meeting-progress")
    }

    private func questionView(_ d: ManagerModel.BoardDecision) -> some View {
        let table: [ManagerModel.Attendee] = current.map { (r: ManagerModel.MeetingRuling) -> [ManagerModel.Attendee] in r.attendees.filter { !$0.isYou } } ?? (store.engine?.boardMeetingGuests([d]) ?? [])
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Question \(index + 1) of \(points.count)").textStyle(.label, tint: Theme.inkFaint)
            Text(d.title.tidyMoney).textStyle(.headline).fixedSize(horizontal: false, vertical: true)
            Text(d.effect.tidyMoney).textStyle(.caption, tint: Theme.inkSoft).lineLimit(3)
            if !d.reason.isEmpty { Text(d.advisor + ": " + d.reason.tidyMoney).textStyle(.caption, tint: Theme.inkFaint).lineLimit(2) }
            Hairline()
            if table.isEmpty {
                Text("You hold every share. Your vote decides.").textStyle(.caption, tint: Theme.inkSoft)
            } else {
                ForEach(table.prefix(5)) { (a: ManagerModel.Attendee) in
                    tableRow(a, status: current == nil ? (a.present ? "Here" : "Away") : (a.present ? (a.yes ? "Voted yes" : "Voted no") : "Away"))
                }
                if table.count > 5 { Text("and \(table.count - 5) more").textStyle(.caption, tint: Theme.inkFaint) }
            }
            Hairline()
            if let r = current {
                Text(r.line.tidyMoney).textStyle(.body, tint: r.kind == .carried ? Theme.gain : Theme.caution, weight: .medium)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("boardroom-meeting-result")
                Button(index + 1 < points.count ? "Next question" : "See summary") { Haptics.tap(); current = nil; index += 1 }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .accessibilityIdentifier("boardroom-meeting-next")
            } else {
                DecisionChoices(labels: ["Vote yes", "Vote no"], identifier: { (i: Int) -> String in i == 0 ? "boardroom-vote-yes" : "boardroom-vote-no" },
                                pick: { (i: Int) in vote(i == 0) })
            }
        }
    }

    private var summaryView: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Meeting closed").textStyle(.headline)
            if rulings.isEmpty {
                Text("Nothing was left on the table.").textStyle(.caption, tint: Theme.inkSoft)
            }
            ForEach(rulings) { (r: ManagerModel.MeetingRuling) in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Circle().fill(r.kind == .carried ? Theme.gain : Theme.caution).frame(width: 6, height: 6)
                    Text(r.line.tidyMoney).textStyle(.caption, tint: Theme.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
            Button("Close") { Haptics.tap(); dismiss() }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .accessibilityIdentifier("boardroom-meeting-close")
        }
    }

    private func tableRow(_ a: ManagerModel.Attendee, status: String) -> some View {
        HStack(spacing: Theme.Space.s) {
            Text(a.name).textStyle(.caption, tint: Theme.ink).lineLimit(1)
            Spacer(minLength: Theme.Space.s)
            Text("\(Int(saturating: a.percent.rounded()))% \u{00B7} " + status).textStyle(.caption, tint: Theme.inkSoft).lineLimit(1)
        }
    }

    private func open() async {
        guard !started else { return }
        started = true
        let k: [String] = keys
        _ = store.act { (e: inout GameEngine) -> Bool in e.beginBoardMeeting(keys: k); return true }
        guard let e = store.engine else { joining = false; return }
        points = e.boardMeetingAgenda(keys: k)
        guests = e.boardMeetingGuests(points)
        if !guests.isEmpty {
            let step: UInt64 = UInt64(Self.seconds / Double(Self.steps) * 1_000_000_000)
            for n in 1...Self.steps {
                try? await Task.sleep(nanoseconds: step)
                if Task.isCancelled { break }
                withAnimation(.linear(duration: 0.2)) { progress = Double(n) / Double(Self.steps) }
            }
        }
        joining = false
    }

    private func vote(_ yes: Bool) {
        guard index < points.count, current == nil else { return }
        let d: ManagerModel.BoardDecision = points[index]
        let k: String = d.key
        let id: String = d.id
        let r: ManagerModel.MeetingRuling? = store.act { (e: inout GameEngine) -> ManagerModel.MeetingRuling? in e.voteOnBoardPoint(key: k, id: id, yes: yes) } ?? nil
        guard let r else { index += 1; return }
        if r.kind == .carried { Haptics.success() } else { Haptics.warning() }
        rulings.append(r)
        current = r
    }
}

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
