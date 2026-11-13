import SwiftUI
import GameCore
import Countries
import Events
import Simulation

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
                let live: [JointVenture.Meeting] = st.meetings.filter { !$0.closed }.sorted { ($0.closesAt ?? 0) < ($1.closesAt ?? 0) }
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
                            if part != .history && st.members.count > 1 {
                                Button { Haptics.tap(); callOpen = true } label: { Text("Put something to the board").frame(maxWidth: .infinity) }
                                    .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                                    .accessibilityIdentifier("jv-call")
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
        .centerSheet(isPresented: $callOpen, title: "Put to the board", size: .tall) { JVCallSheet(companyID: companyID).environmentObject(store) }
        .task { JointVentureCoordinator.shared.attach(online.service); await JointVentureCoordinator.shared.sync(store) }
    }

    @ViewBuilder private func upcoming(_ e: GameEngine, _ co: Company, _ st: JointVenture.State, _ live: [JointVenture.Meeting], _ week: Int) -> some View {
        if live.isEmpty {
            Card(padding: Theme.Space.l) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Next board meeting").capsLabel()
                    Text(JVClock.text(e.jvNextMeeting())).textStyle(.figure, tint: Theme.ink)
                    Text("The board meets every Monday. Nothing is on the agenda yet; an item needs a day's notice, so a late one waits for the meeting after.")
                        .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        ForEach(live) { (m: JointVenture.Meeting) in meetingCard(e, co, m) }
    }

    @ViewBuilder private func urgent(_ e: GameEngine, _ co: Company, _ st: JointVenture.State, _ live: [JointVenture.Meeting], _ week: Int) -> some View {
        if live.isEmpty {
            EmptyState(glyph: Glyph.group, title: "No emergency meeting", message: "Any owner can call one when something cannot wait. Every other owner is notified and has 24 hours to vote.", centered: false)
        }
        ForEach(live) { (m: JointVenture.Meeting) in meetingCard(e, co, m) }
    }

    @ViewBuilder private func history(_ e: GameEngine, _ co: Company, _ st: JointVenture.State) -> some View {
        let closed: [JointVenture.Meeting] = st.meetings.filter { $0.closed }.sorted { ($0.closedWeek ?? 0) > ($1.closedWeek ?? 0) }
        if closed.isEmpty {
            EmptyState(glyph: Glyph.group, title: "No meetings yet", message: "What each meeting decided is kept here.", centered: false)
        }
        ForEach(closed) { (m: JointVenture.Meeting) in meetingCard(e, co, m) }
    }

    private func meetingCard(_ e: GameEngine, _ co: Company, _ m: JointVenture.Meeting) -> some View {
        let names: [String: String] = Dictionary(uniqueKeysWithValues: e.jvStakes(companyID: co.id).map { ($0.id, $0.isYou ? "You" : $0.name) })
        let canVote: Bool = JVClock.votingOpen(m, week: e.state.week)
        return Card(padding: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(m.planned ? "Weekly board meeting" : "Emergency meeting").capsLabel()
                Text(JVClock.heading(m, company: co.name))
                    .textStyle(.headline, tint: Theme.ink).fixedSize(horizontal: false, vertical: true)
                Text(m.closed ? "Counted \(GameCalendar.dateString(week: m.closedWeek ?? m.deadline))." : "Vote by \(JVClock.closes(m)). It passes with yes votes from more than half of all shares; a vote not cast counts as an abstention.")
                    .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
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
            FlowVotes(votes: it.votes, names: names, closed: m.closed, sealed: !m.closed && it.remoteMeeting != nil)
            if !m.closed, let t = e.jvTally(companyID: co.id, meetingID: m.id, itemID: it.id) {
                Text("Yes so far: \(Int(saturating: t.yesPercent.rounded()))% of all shares. It needs more than 50%.").textStyle(.caption, tint: Theme.inkSoft)
            }
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

private struct FlowVotes: View {
    var votes: [String: JVRules.Choice]
    var names: [String: String]
    var closed: Bool
    // Votes of real players stay sealed on the server until the meeting closes.
    var sealed: Bool = false

    var body: some View {
        let all: [String] = names.keys.sorted { (a: String, b: String) -> Bool in a == JointVenture.Member.me ? true : b == JointVenture.Member.me ? false : (names[a] ?? "") < (names[b] ?? "") }
        let ids: [String] = sealed ? all.filter { (id: String) -> Bool in id == JointVenture.Member.me } : all
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
            if sealed { Text("How each partner voted shows when the meeting closes.").textStyle(.caption, tint: Theme.inkFaint) }
        }
    }
}

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
                Text(JVClock.heading(m, company: co.name))
                    .popupText(.body).fixedSize(horizontal: false, vertical: true)
                Text("An item passes only with yes votes from more than half of all shares. A vote not cast by \(JVClock.closes(m)) counts as an abstention.")
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

    private func standing(_ e: GameEngine, _ it: JointVenture.Item) -> some View {
        let t = e.jvTally(companyID: companyID, meetingID: meetingID, itemID: it.id)
        let words: String = t.map { "Of all shares: for \(Int(saturating: $0.yesPercent.rounded()))% · against \(Int(saturating: $0.noPercent.rounded()))% · not voted \(Int(saturating: (100 - $0.yesPercent - $0.noPercent).rounded()))%" } ?? ""
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
        Task { @MainActor in await JointVentureCoordinator.shared.sync(store) }
        store.tell("Votes recorded", lines.joined(separator: "\n") + "\nVoting closes \(JVClock.closes(m))" + (m.urgent ? ", or as soon as more than half of all shares have voted yes" : "") + ". What passes is carried out by the game.", tone: "good")
    }
}

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

    private static let kinds: [JVRules.Kind] = [.price, .dividend, .hire, .sell, .dissolve]

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            let cur: Currency = e.currency(for: co)
            let top: Double = kind == .dividend ? e.maximumDividend(companyID: companyID) : cur.scaledPrice(500_000)
            let offered: [JVRules.Kind] = e.jvIsRemote(companyID: companyID) ? Self.kinds.filter { (k: JVRules.Kind) -> Bool in k != .sell } : Self.kinds
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                ForEach(offered, id: \.self) { (k: JVRules.Kind) in
                    ChoiceCard(title: k.title, subtitle: JVRules.effect(k, amount: amount, steps: down ? -1 : 1, money: { cur.tidyDisplay($0) }), selected: kind == k) { kind = k; amount = min(max(amount, 0), top) }
                }
                if kind == .price { SegmentedPill(items: ["Down", "Up"], title: { $0 }, selection: Binding(get: { down ? "Down" : "Up" }, set: { down = $0 == "Down" })) }
                if kind == .dividend {
                    if top > 0 {
                        LedgerSlider(value: $amount, in: 0...top, step: max(1, cur.scaledPrice(1_000)), valueText: cur.tidyDisplay(amount))
                    } else {
                        Text("There is no profit to pay out.").popupText(.risk)
                    }
                }
                Text("Why").capsLabel()
                TextField("A line for the other owners", text: $reason).textFieldStyle(.roundedBorder)
                Text("The dividend policy and group rules are put to the board from where they are set.").popupText(.caption)
                Color.clear.frame(height: 0)
                    .popupFooter {
                        BoardChoiceFooter(nextMeeting: e.jvNextMeeting(), onMeeting: { put(urgent: false) }, onNow: { put(urgent: true) }, onCancel: { dismiss() })
                    }
            }
        }
    }

    private func put(urgent: Bool) {
        let id: Int = companyID
        let k: JVRules.Kind = kind, a: Double = amount, d: Bool = down, r: String = reason
        guard let made = store.act({ (g: inout GameEngine) -> (item: JointVenture.Item?, problem: String?) in g.jvMakeItem(companyID: id, kind: k, amount: a, steps: d ? -1 : 1) }) else { return }
        guard let item = made.item else { Haptics.warning(); store.tell("Cannot be put", made.problem ?? "That cannot be put to a vote now.", tone: "warn"); return }
        if !urgent {
            let ok: Bool = store.act({ (g: inout GameEngine) -> Bool in g.jvQueue(companyID: id, item: item) }) ?? false
            guard ok else { Haptics.warning(); store.tell("Not added", "There is no board to put it to.", tone: "warn"); return }
            Haptics.success()
            dismiss()
            Task { @MainActor in await JointVentureCoordinator.shared.sync(store) }
            store.tell("Added to the next board meeting", "\"\(item.title)\" is on the agenda. It passes with yes votes from more than half of all shares; your own shares already count for it.", tone: "good")
            return
        }
        let result = store.act { (g: inout GameEngine) -> JointVenture.CallResult in g.jvCallUrgent(companyID: id, reason: r, items: [item]) }
        switch result {
        case .called?:
            Haptics.success()
            dismiss()
            Task { @MainActor in await JointVentureCoordinator.shared.sync(store) }
            store.tell("Emergency meeting called", "The other owners have been notified and have 24 hours to vote. It passes with yes votes from more than half of all shares; a vote not cast counts as an abstention.", tone: "good")
        case .refused(let why)?:
            Haptics.warning()
            store.tell("Not called", why, tone: "warn")
        case nil: break
        }
    }
}

enum JVClock {
    static func text(_ d: Date) -> String { d.formatted(date: .abbreviated, time: .shortened) }

    static func closes(_ m: JointVenture.Meeting) -> String {
        m.closesAt.map { (t: Double) -> String in text(Date(timeIntervalSince1970: t)) } ?? GameCalendar.dateString(week: m.deadline)
    }

    static func votingOpen(_ m: JointVenture.Meeting, week: Int, now: Date = Date()) -> Bool {
        if m.closed { return false }
        if let closes = m.closesAt { return now.timeIntervalSince1970 < closes }
        return m.opened <= week && week <= m.deadline
    }

    static func heading(_ m: JointVenture.Meeting, company: String) -> String {
        if m.planned { return "\(company) weekly board meeting, \(closes(m))" }
        return "\(m.calledByTitle) called an emergency meeting: \(m.reason)"
    }
}

// The two ways a change reaches the board: the weekly meeting, or a 24-hour emergency meeting.
struct BoardChoiceFooter: View {
    @Environment(\.outsidePalette) private var P
    var nextMeeting: Date
    var onMeeting: () -> Void
    var onNow: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button(action: { Haptics.tap(); onMeeting() }) { Text("Add to next board meeting").lineLimit(1).minimumScaleFactor(0.8) }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .accessibilityIdentifier("board-add")
            Button(action: { Haptics.tap(); onNow() }) { Text("Decide now").lineLimit(1).minimumScaleFactor(0.8) }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true, tint: P.loss))
                .accessibilityIdentifier("board-now")
            Text("Next board meeting: \(JVClock.text(nextMeeting)). Decide now notifies every other owner and gives them 24 hours.")
                .popupText(.caption).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button(action: onCancel) { Text("Cancel") }
                .buttonStyle(PopupTextActionStyle(tint: P.inkSoft))
                .accessibilityIdentifier("confirm-cancel")
        }
        .padding(.top, 8)
    }
}

struct BoardProposal: Identifiable {
    let id = UUID()
    var companyID: Int
    var boardName: String
    var change: JointVenture.Change
    var title: String
    var effect: String
}

// Asks how a dividend policy or group rule change goes to the owners of a co-owned company.
struct BoardProposalSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var proposal: BoardProposal
    var onDone: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(proposal.title).popupText(.title)
            if !proposal.effect.isEmpty { Text(proposal.effect).popupText(.body) }
            Text("\(proposal.boardName) has co-owners, so this is a proposal, not a setting. It passes only with yes votes from more than half of all shares. An owner who does not vote abstains.")
                .popupText(.caption)
            Color.clear.frame(height: 0)
                .popupFooter {
                    BoardChoiceFooter(nextMeeting: store.engine?.jvNextMeeting() ?? Date(), onMeeting: { send(urgent: false) }, onNow: { send(urgent: true) }, onCancel: { dismiss() })
                }
        }
    }

    private func send(urgent: Bool) {
        let p: BoardProposal = proposal
        let result = store.act { (g: inout GameEngine) -> JointVenture.ProposeResult in g.jvPropose(companyID: p.companyID, change: p.change, urgent: urgent) }
        switch result {
        case .applied?:
            Haptics.success()
            dismiss(); onDone()
            store.show(p.title + ".", tone: "good")
        case .added?:
            Haptics.success()
            dismiss(); onDone()
            store.tell("Added to the next board meeting", "\"\(p.title)\" is on the agenda of \(p.boardName). Nothing changes unless more than half of all shares vote yes.", tone: "good")
            Task { @MainActor in await JointVentureCoordinator.shared.sync(store) }
        case .called?:
            Haptics.success()
            dismiss(); onDone()
            store.tell("Emergency meeting called", "The other owners of \(p.boardName) have been notified and have 24 hours to vote on \"\(p.title)\". Nothing changes unless more than half of all shares vote yes.", tone: "good")
            Task { @MainActor in await JointVentureCoordinator.shared.sync(store) }
        case .refused(let why)?:
            Haptics.warning()
            store.tell("Not put to the board", why, tone: "warn")
        case nil: break
        }
    }
}
