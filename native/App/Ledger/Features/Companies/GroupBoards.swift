import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Group > Boards: every board that sits over a chain or a company, decisions first, each opening its own page. Owners, dividends and
/// buy-backs stay in each company's Money; stakes in other groups and the big-meeting offer stay under Money, Invest. Logic: `ManagerModel` boards.
struct BoardsGroupSection: View {
    var engine: GameEngine
    var openInvest: () -> Void

    var body: some View {
        let keys: [String] = engine.boardKeys.filter { engine.boardIsActive(key: $0) }
        let waiting: [String: Int] = Dictionary(uniqueKeysWithValues: keys.map { ($0, engine.boardOpenDecisions(key: $0)) })
        let ordered: [String] = keys.sorted { (waiting[$0] ?? 0, $0.hasPrefix("ch:") ? 1 : 0) > (waiting[$1] ?? 0, $1.hasPrefix("ch:") ? 1 : 0) }
        let total: Int = waiting.values.reduce(0, +)
        MoreBlock(title: "Boards", card: false, trailing: { RedBubble(count: total, size: .small) }) {
            if keys.isEmpty {
                NoteCard(text: "A board forms once you register a chain or somebody else owns part of a company.")
            }
            ForEach(ordered, id: \.self) { key in
                NavigationLink { BoardView(key: key) } label: { BoardLinkRow(engine: engine, key: key) }.buttonStyle(.plain)
            }
            Button(action: openInvest) {
                CardRow(glyph: Glyph.bank, title: "Stakes in other groups and the big meeting offer", subtitle: "In the Bank app. Owners, dividends and buy-backs are in each company's Finances.")
            }.buttonStyle(.plain)
        }
    }
}

/// One board as a row: whose board, seats, and what waits for a decision (a red count).
struct BoardLinkRow: View {
    var engine: GameEngine
    var key: String

    var body: some View {
        let seats: Int = engine.boardSeats(key: key).count
        let waiting: Int = engine.boardOpenDecisions(key: key)
        let jobs: Int = engine.boardFollowUps(key: key).filter { $0.status.isEmpty }.count
        let kind: String = key.hasPrefix("ch:") ? "Chain board" : "Company board"
        let sub: String = "\(kind) · \(seats) \(seats == 1 ? "seat" : "seats") filled" + (waiting > 0 ? " · \(waiting) to decide" : "") + (jobs > 0 ? " · \(jobs) follow-up \(jobs == 1 ? "job" : "jobs")" : "")
        CardRow(glyph: key.hasPrefix("ch:") ? Glyph.group : Glyph.achievements, title: engine.boardName(key: key), subtitle: sub, badge: waiting)
    }
}

/// One board: what waits for a decision, how often it meets, who sits at the table, adding advisers, and what it says to a big move.
/// Opened from Group > Boards, from the chain page and from a company's owners. Laid out as a board room: the agenda first as
/// decision cards, the table as seat cards, the meeting rhythm as a switch, and the vote odds as bars.
struct BoardView: View {
    @EnvironmentObject var store: GameStore
    var key: String
    @State private var message = ""
    @State private var candidates: [Person] = []
    @State private var pending: PendingAction?

    var body: some View {
        if let engine = store.engine, engine.boardIsActive(key: key) {
            let companies: [Company] = ManagerModel.boardCompanies(engine.state, key: key)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !message.isEmpty { NoteCard(text: message) }
                    agenda(engine)
                    followUps(engine)
                    table(engine)
                    meets(engine)
                    bigMoves(engine, companies: companies)
                    minutes(engine)
                    ownersLink(companies)
                }
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .ledgerBackground()
            .appScreen(title: engine.boardName(key: key), subtitle: key.hasPrefix("ch:") ? "Board of the chain · \(companies.count) \(companies.count == 1 ? "store" : "stores")" : "Board of the company", tab: .group)
            .confirmAction($pending)
            // Every result is also a toast, so it is seen when the line at the top has scrolled away.
            .onChange(of: message) { _, new in if !new.isEmpty { store.show(new, tone: "n") } }
        } else {
            Text("This board no longer meets.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    @ViewBuilder private func ownersLink(_ companies: [Company]) -> some View {
        if key.hasPrefix("co:"), let co = companies.first {
            NavigationLink(value: CompanyRoute.companyAt(co.id, .finances)) {
                CardRow(glyph: Glyph.reports, title: "Owners and shares of \(co.name)", subtitle: "Who owns what, dividends and buy-backs, in the company's Finances.")
            }.buttonStyle(.plain)
        }
    }

    // MARK: To decide

    /// Concerns are answered with "Act on it" / "Leave it"; proposals with "Approve" / "Decline".
    private func isConcern(_ it: ManagerModel.MeetingItem) -> Bool { ["morale", "overtime", "leaving"].contains(it.action) }
    private func approveWord(_ it: ManagerModel.MeetingItem) -> String { isConcern(it) ? "Act on it" : "Approve" }
    private func declineWord(_ it: ManagerModel.MeetingItem) -> String { isConcern(it) ? "Leave it" : "Decline" }

    @ViewBuilder private func agenda(_ engine: GameEngine) -> some View {
        let open: [ManagerModel.BoardMeeting] = engine.boardMeetings(key: key).filter { $0.isOpen }
        let preview: [ManagerModel.MeetingItem] = engine.boardAgendaPreview(key: key)
        MoreBlock(title: "To decide", card: false, trailing: { RedBubble(count: engine.boardOpenDecisions(key: key), size: .small) }) {
            if open.isEmpty { NoteCard(text: "Nothing waits for the board.", glyph: Glyph.check) }
            ForEach(open) { m in meeting(m, engine) }
            if preview.isEmpty {
                Text("No meeting is due: the board meets when a seat brings a proposal or a concern.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            } else {
                QuietButton(title: "Hold a board meeting · \(preview.count) \(preview.count == 1 ? "point" : "points")") {
                    let id: Int? = store.act { $0.holdBoardMeeting(key: key) } ?? nil
                    if id == nil { message = "Nothing to meet about right now." } else { message = ""; Haptics.success(); store.show("The board met. Its agenda is below.", tone: "good") }
                }
            }
        }
    }

    private func emergencyButtons(_ m: ManagerModel.BoardMeeting) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(m.options.enumerated()), id: \.offset) { (i: Int, o: String) in
                Button(o) {
                    pending = PendingAction(title: "Decide: \(o)?", message: "An emergency decision of the board takes effect at once and cannot be undone.", button: "Decide") {
                        let r: String? = store.act { $0.pickEmergency(key: key, meetingID: m.id, option: i) } ?? nil
                        message = r == "hire" ? "Decided. Pick a new manager in the company's Team." : "Decided: \(o)."
                        Haptics.success()
                    }
                }.buttonStyle(GreyOutlineButtonStyle())
            }
        }
    }

    /// What approving does, in the words shown before the owner confirms: the effect, the cost now and the risk.
    private func details(_ it: ManagerModel.MeetingItem, in co: Company?) -> String {
        var lines: [String] = [it.text.tidyMoney]
        if !it.effect.isEmpty {
            lines.append("Effect: " + it.effect.tidyMoney)
            if it.cost > 0, let co { lines.append("Cost now: " + store.short(it.cost, in: co)) } else { lines.append("Cost now: nothing") }
        }
        if !it.risk.isEmpty { lines.append("Risk: " + it.risk) }
        return lines.joined(separator: "\n")
    }

    private func approve(_ m: ManagerModel.BoardMeeting, _ it: ManagerModel.MeetingItem, _ engine: GameEngine) {
        let co: Company? = engine.state.company(it.companyID)
        let cur: Currency? = co.map { engine.currency(for: $0) }
        pending = PendingAction(title: "\(approveWord(it))?", message: details(it, in: co), button: approveWord(it),
                                destructive: it.action == "sale" || it.action == "fireceo", amount: it.cost, currency: cur) {
            let r = store.act { $0.decideMeetingItem(key: key, meetingID: m.id, item: it.id, approve: true) }
            switch r {
            case .followUp(let what)?: message = what + " A follow-up job is listed below."; Haptics.success()
            case .done(let what)?: message = what.isEmpty ? "Done." : what; Haptics.success()
            case .refused(let why)?: message = "Not done: " + why
            case .gone?: message = "That point is no longer on the agenda."
            default: message = "Done."
            }
        }
    }

    private func decline(_ m: ManagerModel.BoardMeeting, _ it: ManagerModel.MeetingItem) {
        let r = store.act { $0.decideMeetingItem(key: key, meetingID: m.id, item: it.id, approve: false) }
        if case .gone? = r { message = "That point is no longer on the agenda." } else { message = isConcern(it) ? "Left as it is. It goes in the minutes." : "Declined. It goes in the minutes." }
    }

    private func itemRow(_ m: ManagerModel.BoardMeeting, _ it: ManagerModel.MeetingItem, _ engine: GameEngine) -> some View {
        let co: Company? = engine.state.company(it.companyID)
        var costText: String = "Nothing"
        if it.cost > 0, let co { costText = store.short(it.cost, in: co) }
        return VStack(alignment: .leading, spacing: 8) {
            Text(it.text.tidyMoney).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
            if !it.raisedBy.isEmpty { Text("Raised by \(it.raisedBy)").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }
            if !it.effect.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    detailLine("If you approve", it.effect.tidyMoney)
                    detailLine("Cost now", costText)
                    detailLine("Risk", it.risk)
                }
            }
            HStack(spacing: 10) {
                Button(approveWord(it)) { approve(m, it, engine) }.buttonStyle(QuietButtonStyle())
                Button(declineWord(it)) { decline(m, it) }.buttonStyle(GreyOutlineButtonStyle())
            }
        }
    }

    @ViewBuilder private func detailLine(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.ivoryFaint).frame(width: 92, alignment: .leading)
                Text(value).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func meeting(_ m: ManagerModel.BoardMeeting, _ engine: GameEngine) -> some View {
        Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    IconCircle(glyph: m.isEmergency ? Glyph.warning : Glyph.calendar, size: 36, tint: m.isEmergency ? Theme.caution : Theme.gold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.title.tidyMoney).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                        Text(GameCalendar.dateString(week: m.week)).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                        if !m.why.isEmpty && m.why != "Regular meeting" { Text(m.why.tidyMoney).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true) }
                        if !m.attendees.isEmpty {
                            let present: String = "Present: " + m.attendees.joined(separator: " · ")
                            Text(present).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if m.isEmergency {
                    emergencyButtons(m)
                } else {
                    ForEach(m.items.filter { $0.status.isEmpty && !$0.action.isEmpty }) { it in
                        CardLine()
                        itemRow(m, it, engine)
                    }
                }
            }
        }
    }

    // MARK: Follow-up jobs

    @ViewBuilder private func followUps(_ engine: GameEngine) -> some View {
        let open: [ManagerModel.FollowUp] = engine.boardFollowUps(key: key).filter { $0.status.isEmpty }
        if !open.isEmpty {
            MoreBlock(title: "Follow-up jobs", card: false, trailing: { RedBubble(count: open.count, size: .small) }) {
                ForEach(open) { f in
                    Card(padding: 12, radius: Theme.Radius.card) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(f.text.tidyMoney).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                            let lapse: String = f.assignee + " · lapses " + GameCalendar.dateString(week: f.due)
                            Text(lapse).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                            HStack(spacing: 10) {
                                NavigationLink(value: CompanyRoute.company(f.companyID)) { Text("Open company").font(.system(size: 13, weight: .medium)) }.buttonStyle(QuietButtonStyle())
                                Button("Mark done") {
                                    _ = store.act { $0.completeBoardFollowUp(key: key, id: f.id) }
                                    message = "Marked done."
                                }.buttonStyle(GreyOutlineButtonStyle())
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Minutes

    private func minutesCard(_ m: ManagerModel.BoardMeeting) -> some View {
        let lines: [String] = m.minutes.map { (line: String) -> String in "· " + line.tidyMoney }
        let title: String = m.title.tidyMoney
        let date: String = GameCalendar.dateString(week: m.week)
        return Card(padding: 12, radius: Theme.Radius.card) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory)
                    Spacer(minLength: 8)
                    Text(date).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                }
                ForEach(Array(lines.enumerated()), id: \.offset) { (_: Int, line: String) in
                    Text(line).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                }
                if lines.isEmpty { Text("Nothing was decided.").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }
            }
        }
    }

    private func closedJobLine(_ f: ManagerModel.FollowUp) -> some View {
        let state: String = f.status == "done" ? "done" : "lapsed"
        let note: String = f.note.isEmpty ? "" : " (" + f.note + ")"
        let text: String = "Follow-up " + state + ": " + f.text.tidyMoney + note
        return Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func minutes(_ engine: GameEngine) -> some View {
        let all: [ManagerModel.BoardMeeting] = engine.boardMeetings(key: key)
        let done: [ManagerModel.BoardMeeting] = Array(all.filter { !$0.isOpen }.prefix(6))
        let closedJobs: [ManagerModel.FollowUp] = engine.boardFollowUps(key: key).filter { !$0.status.isEmpty }
        let jobs: [ManagerModel.FollowUp] = Array(closedJobs.suffix(4).reversed())
        let empty: Bool = done.isEmpty && jobs.isEmpty
        MoreBlock("Minutes and outcomes", card: false) {
            if empty { NoteCard(text: "The minutes of each meeting are kept here once its points are decided.") }
            ForEach(done) { m in minutesCard(m) }
            ForEach(jobs) { f in closedJobLine(f) }
        }
    }

    // MARK: Who sits at the table

    private func voterCard(_ v: ManagerModel.Voter, seats: [ManagerModel.Seat]) -> some View {
        HStack(spacing: 12) {
            IconCircle(glyph: v.votes ? Glyph.person : Glyph.people, size: 34, tint: v.votes ? Theme.gold : Theme.ivoryMuted)
            VStack(alignment: .leading, spacing: 1) {
                Text(v.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                Text("\(v.title) · \(v.votes ? "votes" : "advises")").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).lineLimit(2)
            }
            Spacer(minLength: 8)
            if let pid = v.personID, seats.contains(where: { $0.id == pid && $0.isAdviser }) {
                Button("Let go") {
                    pending = PendingAction(title: "Let \(v.name) go from the board?", message: "Their monthly fee stops and their advice leaves with them.", button: "Let go", destructive: true) {
                        store.act { $0.removeFromBoard(key: key, personID: pid) }
                        message = "\(v.name) left the board."
                    }
                }.buttonStyle(TinyButtonStyle(tint: Theme.loss))
            }
        }
    }

    private func seatFinder(_ engine: GameEngine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add to the board (a search costs a fee)").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
            WrapRow {
                Group {
                    ForEach(engine.seatRoles) { r in
                        Button(r.title) {
                            let found: [Person]? = store.act { $0.searchForSeat(key: key, role: r.id) } ?? nil
                            if let found { candidates = found; message = found.isEmpty ? "Nobody suitable answered." : "" } else { message = "Not enough cash for a search." }
                        }.buttonStyle(TinyButtonStyle()).fixedSize()
                    }
                }
            }
        }
    }

    private func candidateRow(_ p: Person) -> some View {
        let fee: Double = p.num("fee13")
        return HStack(spacing: 10) {
            Text("\(p.name) · \(p.str("advBg"))").font(.system(size: 12.5)).foregroundStyle(Theme.ivory).lineLimit(2)
            Spacer(minLength: 8)
            Button("Seat · \(store.short(fee)) a month") {
                pending = PendingAction(title: "Seat \(p.name) on the board?", message: "Cost: \(store.short(fee)) a month in fees, for as long as they sit. The owners vote on it, and may refuse. You can let an adviser go later.", button: "Seat them") { seat(p, fee: fee) }
            }.buttonStyle(TinyButtonStyle()).fixedSize()
        }
    }

    @ViewBuilder private func table(_ engine: GameEngine) -> some View {
        let seats: [ManagerModel.Seat] = engine.boardSeats(key: key)
        MoreBlock("At the table") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(engine.boardVoters(key: key).enumerated()), id: \.element.id) { (n: Int, v: ManagerModel.Voter) in
                    if n > 0 { CardLine() }
                    voterCard(v, seats: seats)
                }
                ForEach(seats.filter { $0.isAdviser }) { s in
                    Text("\(s.title) · fee \(store.short(s.monthlyFee)) a month · took \(s.adviceTaken) of your calls, refused \(s.adviceRefused)").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                }
                CardLine()
                seatFinder(engine)
                ForEach(candidates) { p in candidateRow(p) }
            }
        }
    }

    private func seat(_ p: Person, fee: Double) {
        let r = store.act { $0.fillSeat(key: key, personID: p.id, monthlyFee: fee) }
        switch r {
        case .ok?: message = "\(p.name) joins the board."; candidates = []; Haptics.success()
        case .full?: message = "That seat is full."
        case .refused?: message = "\(p.name) wants more."
        case .votedDown(let n)?: message = "The owners voted \(p.name) down (\(n)% behind them)."
        default: message = "\(p.name) is not available."
        }
    }

    // MARK: How often it meets

    @ViewBuilder private func meets(_ engine: GameEngine) -> some View {
        let board = ManagerModel.board(engine.state, key: key)
        let regular: Bool = board["mode"].string == "regular"
        let quarterly: Bool = board["freq"].int >= 13
        let modeBinding = Binding<Bool>(get: { regular }, set: { v in
            if v { store.settle(store.act { $0.setBoardMode(key: key, regular: true) }, "The board meets regularly.", same: "It already meets regularly.") }
            else { store.settle(store.act { $0.setBoardMode(key: key, regular: false) }, "The board meets when needed.", same: "It already meets when needed.") }
        })
        let freqBinding = Binding<Bool>(get: { quarterly }, set: { v in
            if v { store.settle(store.act { $0.setBoardMode(key: key, quarterly: true) }, "The board meets quarterly.", same: "It already meets quarterly.") }
            else { store.settle(store.act { $0.setBoardMode(key: key, quarterly: false) }, "The board meets every 4 weeks.", same: "It already meets every 4 weeks.") }
        })
        MoreBlock("Meets") {
            VStack(alignment: .leading, spacing: 10) {
                SegmentedPill(items: [false, true], title: { $0 ? "Regularly" : "When needed" }, selection: modeBinding)
                if regular {
                    SegmentedPill(items: [false, true], title: { $0 ? "Quarterly" : "Every 4 weeks" }, selection: freqBinding)
                }
                Text(regular ? "The board meets on a schedule and puts its own items on the agenda." : "The board meets only when you call it or something needs it.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    // MARK: Big moves

    private func voteRow(label: String, vote: ManagerModel.BoardVote) -> some View {
        let pct: Double = vote.percentYes
        let tail: String = (vote.passes ? "would pass" : "would not pass") + (vote.decidingOwner.map { " · \($0) decides" } ?? "")
        return VStack(alignment: .leading, spacing: 4) {
            RateBar(label: label, fraction: pct / 100, tint: vote.passes ? Theme.gain : Theme.caution)
            Text("\(Int(pct.rounded()))% yes · \(tail)").font(.system(size: 11.5)).foregroundStyle(vote.passes ? Theme.gain : Theme.caution)
        }
    }

    @ViewBuilder private func bigMoves(_ engine: GameEngine, companies: [Company]) -> some View {
        if let co = companies.first {
            let votes = [("sell", "Selling"), ("close", "Closing")].map { (label: $0.1, vote: engine.boardVote(kind: $0.0, companyID: co.id)) }.filter { $0.vote.active }
            let power = engine.ownersPower(companyID: co.id)
            if !votes.isEmpty || !(power?.text.isEmpty ?? true) {
                MoreBlock("What the board says to a big move") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(votes.enumerated()), id: \.offset) { _, v in voteRow(label: v.label, vote: v.vote) }
                        if let p = power, !p.text.isEmpty {
                            Text("Other owners: " + p.text).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                        }
                    }
                }
            }
        }
    }
}
