import SwiftUI
import GameCore
import Countries
import Events
import Simulation

/// Board meetings of a joint venture: the next planned meeting and the open ones, urgent meetings (and calling one), and the history with what each
/// vote decided. Votes are cast in a popup; a vote not cast by the deadline counts as an abstention. Rules: `JVRules`, `JointVenture`.
struct JointVentureMeetingsView: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    var companyID: Int

    enum Part: String, CaseIterable, Hashable { case upcoming = "Upcoming", urgent = "Urgent", history = "History" }
    struct Target: Identifiable { var id: Int }

    @State private var part: Part = .upcoming
    @State private var voteTarget: Target?
    @State private var callOpen = false

    var body: some View {
        Group {
            if let e = store.engine, let co = e.state.company(companyID), let st = e.jointVenture(companyID: companyID) {
                let week: Int = e.state.week
                let live: [JointVenture.Meeting] = st.meetings.filter { !$0.closed }.sorted { $0.week < $1.week }
                let waiting: (Bool) -> Bool = { (urgent: Bool) -> Bool in live.contains { $0.urgent == urgent && $0.items.contains { $0.votes[JointVenture.Member.me] == nil } } }
                VStack(spacing: 0) {
                    SegmentedPill(items: Part.allCases, title: { $0.rawValue }, selection: $part, identifier: { "jv-part-\($0.rawValue.lowercased())" },
                                  badges: { (p: Part) -> Bool in p == .upcoming ? waiting(false) : p == .urgent ? waiting(true) : false })
                        .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.xxs).padding(.bottom, Theme.Space.s)
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Space.m) {
                            switch part {
                            case .upcoming: upcoming(e, co, st, live.filter { !$0.urgent }, week)
                            case .urgent: urgent(e, co, st, live.filter { $0.urgent }, week)
                            case .history: history(e, co, st)
                            }
                        }
                        .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.xs).padding(.bottom, Theme.Space.l)
                        .frame(maxWidth: 1100).frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                }
                .appScreen(title: "Board meetings", subtitle: co.name)
            } else {
                EmptyState(glyph: Glyph.group, title: "No board yet", message: "Invite a friend to this company first.").frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
            }
        }
        .centerSheet(item: $voteTarget, title: "Your vote") { (t: Target) in JVVoteSheet(companyID: companyID, meetingID: t.id).environmentObject(store) }
        .centerSheet(isPresented: $callOpen, title: "Emergency meeting", size: .tall) { JVCallSheet(companyID: companyID).environmentObject(store) }
        .task { JointVentureCoordinator.shared.attach(online.service); await JointVentureCoordinator.shared.sync(store) }
    }

    // MARK: Parts

    @ViewBuilder private func upcoming(_ e: GameEngine, _ co: Company, _ st: JointVenture.State, _ live: [JointVenture.Meeting], _ week: Int) -> some View {
        if live.isEmpty {
            Card(padding: Theme.Space.l) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Next planned meeting").capsLabel()
                    if let d = st.nextPlanned {
                        Text(GameCalendar.dateString(week: d)).textStyle(.figure, tint: Theme.ink)
                        Text("The agenda goes to every owner on \(GameCalendar.dateString(week: max(week, d - JVRules.plannedNoticeWeeks))). Planned meetings run every quarter.")
                            .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("None yet. Planned meetings start once a partner has joined.").textStyle(.caption, tint: Theme.inkSoft)
                    }
                }
            }
        }
        ForEach(live) { (m: JointVenture.Meeting) in meetingCard(e, co, m) }
        if st.queue.count > 0 {
            Text("Waiting for the next meeting: " + st.queue.map { $0.title.lowercased() }.joined(separator: ", ") + ".").textStyle(.caption, tint: Theme.inkSoft)
        }
    }

    @ViewBuilder private func urgent(_ e: GameEngine, _ co: Company, _ st: JointVenture.State, _ live: [JointVenture.Meeting], _ week: Int) -> some View {
        if live.isEmpty {
            EmptyState(glyph: Glyph.group, title: "No emergency meeting", message: "Any owner, and the chair or CFO, can call one when something cannot wait.", centered: false)
        }
        ForEach(live) { (m: JointVenture.Meeting) in meetingCard(e, co, m) }
        if st.members.count > 1 {
            Button { Haptics.tap(); callOpen = true } label: { Text("Call an emergency meeting").frame(maxWidth: .infinity) }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                .accessibilityIdentifier("jv-call")
        }
    }

    @ViewBuilder private func history(_ e: GameEngine, _ co: Company, _ st: JointVenture.State) -> some View {
        let closed: [JointVenture.Meeting] = st.meetings.filter { $0.closed }.sorted { ($0.closedWeek ?? 0) > ($1.closedWeek ?? 0) }
        if closed.isEmpty {
            EmptyState(glyph: Glyph.group, title: "No meetings yet", message: "What each meeting decided is kept here.", centered: false)
        }
        ForEach(closed) { (m: JointVenture.Meeting) in meetingCard(e, co, m) }
    }

    // MARK: A meeting

    private func meetingCard(_ e: GameEngine, _ co: Company, _ m: JointVenture.Meeting) -> some View {
        let names: [String: String] = Dictionary(uniqueKeysWithValues: e.jvStakes(companyID: co.id).map { ($0.id, $0.isYou ? "You" : $0.name) })
        let canVote: Bool = !m.closed && m.opened <= e.state.week && e.state.week <= m.deadline
        return Card(padding: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(m.planned ? "Planned meeting" : "Emergency meeting").capsLabel()
                Text(m.planned ? "\(co.name) board meeting on \(GameCalendar.dateString(week: m.week))" : "\(m.calledByTitle) called an emergency meeting: \(m.reason)")
                    .textStyle(.headline, tint: Theme.ink).fixedSize(horizontal: false, vertical: true)
                Text(m.closed ? "Counted \(GameCalendar.dateString(week: m.closedWeek ?? m.deadline))." : "Vote by \(GameCalendar.dateString(week: m.deadline)). A vote not cast counts as an abstention.")
                    .textStyle(.caption, tint: Theme.inkSoft)
                if m.items.isEmpty { Text("Nothing to decide this time.").textStyle(.body, tint: Theme.inkSoft) }
                ForEach(m.items) { (it: JointVenture.Item) in itemBlock(e, co, m, it, names) }
                if canVote && m.items.contains(where: { $0.votes[JointVenture.Member.me] == nil }) {
                    Button { Haptics.tap(); voteTarget = Target(id: m.id) } label: { Text("Vote").frame(maxWidth: .infinity) }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                        .accessibilityIdentifier("jv-vote")
                } else if canVote && !m.items.isEmpty {
                    Button { Haptics.tap(); voteTarget = Target(id: m.id) } label: { Text("Change my vote").frame(maxWidth: .infinity) }
                        .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                }
            }
        }
    }

    private func itemBlock(_ e: GameEngine, _ co: Company, _ m: JointVenture.Meeting, _ it: JointVenture.Item, _ names: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(it.title).textStyle(.body, tint: Theme.ink, weight: .medium)
            Text("If this passes: \(it.effect)").textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            if it.takesMoneyOut { Text("Money leaves the company for its owners, so it needs the vote.").textStyle(.caption, tint: Theme.warn) }
            FlowVotes(votes: it.votes, names: names, closed: m.closed)
            if let out = it.outcome {
                HStack(spacing: 6) {
                    StockArrow(up: out.passes, good: out.passes)
                    Text(out.word + (it.result.isEmpty || !out.passes ? "." : ". " + it.result)).textStyle(.caption, tint: out.passes ? Theme.gain : Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 4)
    }
}

/// Who voted how: a green up arrow for, a red down arrow against, a word for abstained or not yet.
private struct FlowVotes: View {
    var votes: [String: JVRules.Choice]
    var names: [String: String]
    var closed: Bool

    var body: some View {
        let ids: [String] = names.keys.sorted { (a: String, b: String) -> Bool in a == JointVenture.Member.me ? true : b == JointVenture.Member.me ? false : (names[a] ?? "") < (names[b] ?? "") }
        VStack(alignment: .leading, spacing: 2) {
            ForEach(ids, id: \.self) { (id: String) in
                HStack(spacing: 6) {
                    switch votes[id] {
                    case .yes?: StockArrow(up: true, good: true); Text("\(names[id] ?? id) voted for").textStyle(.caption, tint: Theme.inkSoft)
                    case .no?: StockArrow(up: false, good: false); Text("\(names[id] ?? id) voted against").textStyle(.caption, tint: Theme.inkSoft)
                    case .abstain?: Text("\(names[id] ?? id) abstained").textStyle(.caption, tint: Theme.inkFaint)
                    case nil: Text(closed ? "\(names[id] ?? id) did not vote: counted as an abstention" : "\(names[id] ?? id) has not voted yet").textStyle(.caption, tint: Theme.inkFaint)
                    }
                }
            }
        }
    }
}

// MARK: - The voting popup

/// The agenda of one meeting with what each item does, how the votes stand in words, and For / Against / Abstain for each.
struct JVVoteSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var companyID: Int
    var meetingID: Int
    @State private var picks: [Int: JVRules.Choice] = [:]

    private static let titles: [String] = ["For", "Against", "Abstain"]
    private func choice(_ title: String) -> JVRules.Choice { title == "For" ? .yes : title == "Against" ? .no : .abstain }
    private func title(_ c: JVRules.Choice) -> String { c == .yes ? "For" : c == .no ? "Against" : "Abstain" }

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID), let m = e.jointVenture(companyID: companyID)?.meetings.first(where: { $0.id == meetingID }) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text(m.planned ? "\(co.name) board meeting on \(GameCalendar.dateString(week: m.week))" : "\(m.calledByTitle) called an emergency meeting: \(m.reason)")
                    .popupText(.body).fixedSize(horizontal: false, vertical: true)
                Text("Decisions go by shares among the votes cast. At least half of all shares must vote. A vote not cast by \(GameCalendar.dateString(week: m.deadline)) counts as an abstention.")
                    .popupText(.caption)
                ForEach(m.items) { (it: JointVenture.Item) in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(it.title).popupText(.body)
                        Text("If this passes: \(it.effect)").popupText(.caption)
                        if it.takesMoneyOut { Text("Money leaves the company for its owners.").popupText(.risk) }
                        standing(e, it)
                        SegmentedPill(items: Self.titles, title: { $0 }, selection: Binding(
                            get: { title(picks[it.id] ?? it.votes[JointVenture.Member.me] ?? .abstain) },
                            set: { picks[it.id] = choice($0) }))
                    }
                    .padding(.vertical, 4)
                }
                Color.clear.frame(height: 0)
                    .popupFooter {
                        PopupFooter(cancel: "Later", action: "Cast my votes", onCancel: { dismiss() }, onAction: { cast(m) }, actionID: "jv-cast")
                    }
            }
        } else {
            Text("This meeting is over.").popupText(.body)
        }
    }

    /// How the vote stands, in words: shares for and against among all.
    private func standing(_ e: GameEngine, _ it: JointVenture.Item) -> some View {
        let t = e.jvTally(companyID: companyID, meetingID: meetingID, itemID: it.id)
        let words: String = t.map { "For \(Int($0.yesPercent.rounded()))% · against \(Int($0.noPercent.rounded()))% · not yet decided \(Int((100 - $0.yesPercent - $0.noPercent).rounded()))%" } ?? ""
        return HStack(spacing: 6) {
            if let t, t.yes > t.no { StockArrow(up: true, good: true) } else if let t, t.no > t.yes { StockArrow(up: false, good: false) }
            Text(words).popupText(.caption)
        }
    }

    private func cast(_ m: JointVenture.Meeting) {
        let id: Int = companyID, mid: Int = meetingID
        var lines: [String] = []
        for it in m.items {
            let c: JVRules.Choice = picks[it.id] ?? it.votes[JointVenture.Member.me] ?? .abstain
            store.act { (g: inout GameEngine) -> Bool in g.jvVote(companyID: id, meetingID: mid, itemID: it.id, choice: c) }
            lines.append("\(it.title): \(title(c).lowercased())")
        }
        Haptics.success()
        dismiss()
        store.tell("Votes recorded", lines.joined(separator: "\n") + "\nThe votes are counted after \(GameCalendar.dateString(week: m.deadline)). What passes is carried out by the game; you can change a vote until then.", tone: "good")
    }
}

// MARK: - Calling an emergency meeting

/// Pick what to put to the partners and why. Any owner, and the chair or CFO, may call one; it opens at once and closes in a week.
struct JVCallSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var companyID: Int
    @State private var kind: JVRules.Kind = .price
    @State private var down = true
    @State private var amount: Double = 0
    @State private var reason = ""
    @State private var nextPlanned = false

    private static let kinds: [JVRules.Kind] = [.price, .dividend, .capital, .hire, .sell, .dissolve]

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            let cur: Currency = e.currency(for: co)
            let top: Double = kind == .dividend ? e.maximumDividend(companyID: companyID) : cur.scaledPrice(500_000)
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                ForEach(Self.kinds, id: \.self) { (k: JVRules.Kind) in
                    ChoiceCard(title: k.title, subtitle: JVRules.effect(k, amount: amount, steps: down ? -1 : 1, money: { cur.tidyDisplay($0) }), selected: kind == k) { kind = k; amount = min(max(amount, 0), top) }
                }
                if kind == .price { SegmentedPill(items: ["Down", "Up"], title: { $0 }, selection: Binding(get: { down ? "Down" : "Up" }, set: { down = $0 == "Down" })) }
                if kind == .dividend || kind == .capital {
                    if top > 0 {
                        LedgerSlider(value: $amount, in: 0...top, step: max(1, cur.scaledPrice(1_000)), valueText: cur.tidyDisplay(amount))
                    } else {
                        Text("There is no retained profit to pay out.").popupText(.risk)
                    }
                }
                Text("Why").capsLabel()
                TextField("A line for your partners", text: $reason).textFieldStyle(.roundedBorder)
                if e.jointVenture(companyID: companyID)?.nextPlanned != nil {
                    Toggle("Put it to the next planned meeting instead", isOn: $nextPlanned).tint(Theme.accent)
                }
                Color.clear.frame(height: 0)
                    .popupFooter {
                        PopupFooter(cancel: "Cancel", action: nextPlanned ? "Add to the agenda" : "Call the meeting", onCancel: { dismiss() }, onAction: { call(cur) }, actionID: "jv-call-go")
                    }
            }
        }
    }

    private func call(_ cur: Currency) {
        let id: Int = companyID
        let k: JVRules.Kind = kind, a: Double = amount, d: Bool = down, r: String = reason
        let later: Bool = nextPlanned
        guard let made = store.act({ (g: inout GameEngine) -> (item: JointVenture.Item?, problem: String?) in g.jvMakeItem(companyID: id, kind: k, amount: a, steps: d ? -1 : 1) }) else { return }
        guard let item = made.item else { Haptics.warning(); store.tell("Cannot be put", made.problem ?? "That cannot be put to a vote now.", tone: "warn"); return }
        if later {
            let ok: Bool = store.act({ (g: inout GameEngine) -> Bool in g.jvQueue(companyID: id, item: item) }) ?? false
            dismiss()
            if ok { store.tell("Added to the agenda", "\"\(item.title)\" will be on the next planned meeting. Every owner sees it with the agenda.", tone: "good") }
            return
        }
        let result = store.act { (g: inout GameEngine) -> JointVenture.CallResult in g.jvCallUrgent(companyID: id, reason: r, items: [item]) }
        switch result {
        case .called?:
            Haptics.success()
            dismiss()
            store.tell("Emergency meeting called", "Your partners have it in their inbox. They vote within a week; what passes is carried out by the game. A vote not cast counts as an abstention.", tone: "good")
        case .refused(let why)?:
            Haptics.warning()
            store.tell("Not called", why, tone: "warn")
        case nil: break
        }
    }
}
