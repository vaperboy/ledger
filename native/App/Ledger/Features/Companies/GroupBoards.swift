import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Board seat rules shared by the board room and the entity page, so both ask and answer in the same words.
extension GameStore {
    /// The confirmation for taking a holder off a board. Own staff keep their job; an outside holder is paid their notice; without a
    /// majority it is refused (told in a popup, nil returned).
    func removeSeatPrompt(key: String, personID: Int, name: String) -> PendingAction? {
        guard let engine else { return nil }
        let terms: SeatRemovalTerms = engine.seatRemovalTerms(key: key, personID: personID)
        if !terms.allowed { show(terms.reason, tone: "warn"); return nil }
        let cost: String = terms.cost > 0 ? " Notice pay: \(short(terms.cost))." : ""
        return PendingAction(title: "Remove \(name) from the board?", message: terms.summary + cost, button: "Remove from board", destructive: true, alwaysAsk: true) { [weak self] in
            guard let self else { return }
            let result: SettingResult? = self.act { $0.removeSeatHolder(key: key, personID: personID) }
            _ = self.settle(result, "\(name) is off the board.")
        }
    }

    /// Offers a seat and words the outcome; `joined` is true when the person now sits.
    func fillSeatOutcome(key: String, person: Person, fee: Double) -> (text: String, joined: Bool) {
        let name: String = person.name
        let pid: Int = person.id
        let res: ManagerModel.SeatResult? = act { $0.fillSeat(key: key, personID: pid, monthlyFee: fee) }
        switch res {
        case .ok?: return ("\(name) joins the board.", true)
        case .full?: return ("That seat is full.", false)
        case .refused?: return ("\(name) wants more.", false)
        case .votedDown(let n)?: return ("The owners voted \(name) down (\(n)% behind them).", false)
        default: return ("\(name) is not available.", false)
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
    /// The seat picker's second tab: your own employees and managers who qualify (they keep their job).
    @State private var ownTab = false
    @State private var ownList: [BoardCandidate] = []
    @State private var ownSeat = ""
    @State private var pending: PendingAction?
    @State private var freshSeats: Set<String> = []

    var body: some View {
        if let engine = store.engine, engine.boardIsActive(key: key) {
            let companies: [Company] = ManagerModel.boardCompanies(engine.state, key: key)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    hero(engine)
                    if !message.isEmpty { NoteCard(text: message) }
                    agenda(engine)
                    followUps(engine)
                    table(engine)
                    meets(engine)
                    bigMoves(engine, companies: companies)
                    minutes(engine)
                    ownersLink(companies)
                }
                // Blocks sit on the page; only the open meetings keep a surface (they wait for you).
                .environment(\.insideCard, true)
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.page)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).noSidewaysDrag()
            .ledgerBackground()
            .appScreen(title: engine.boardName(key: key), subtitle: key.hasPrefix("ch:") ? "Board of the chain · \(companies.count) \(companies.count == 1 ? "store" : "stores")" : "Board of the company", tab: .group)
            .confirmAction($pending)
        } else {
            Text("This board no longer meets.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    @ViewBuilder private func ownersLink(_ companies: [Company]) -> some View {
        if key.hasPrefix("co:"), let co = companies.first {
            Button { Haptics.tap(); store.openGroupEntity(companyID: co.id, section: "ownership") } label: {
                CardRow(glyph: Glyph.reports, title: "Owners and shares of \(co.name)")
            }.buttonStyle(PressableStyle())
        }
    }

    // MARK: Hero

    /// How many points wait for the board is the one figure of the page.
    private func hero(_ engine: GameEngine) -> some View {
        let n: Int = engine.boardOpenDecisions(key: key)
        return VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text("To decide").textStyle(.label, tint: Theme.inkFaint)
            Text(n == 0 ? "Nothing waits" : "\(n) \(n == 1 ? "point" : "points")").textStyle(.display, tint: n == 0 ? Theme.inkSoft : nil)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(n == 0 ? "The board meets when a seat brings a proposal or a concern." : "Approve or decline each point below.")
                .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: To decide

    /// Concerns are answered with "Act on it" / "Leave it"; proposals with "Approve" / "Decline".
    private func isConcern(_ it: ManagerModel.MeetingItem) -> Bool { ["morale", "overtime", "leaving"].contains(it.action) }
    private func approveWord(_ it: ManagerModel.MeetingItem) -> String { isConcern(it) ? "Act on it" : "Approve" }
    private func declineWord(_ it: ManagerModel.MeetingItem) -> String { isConcern(it) ? "Leave it" : "Decline" }

    @ViewBuilder private func agenda(_ engine: GameEngine) -> some View {
        let open: [ManagerModel.BoardMeeting] = engine.boardMeetings(key: key).filter { $0.isOpen }
        let preview: [ManagerModel.MeetingItem] = engine.boardAgendaPreview(key: key)
        MoreBlock("Agenda", card: false) {
            ForEach(open) { m in meeting(m, engine) }
            if preview.isEmpty {
                if open.isEmpty { Text("No meeting is due.").textStyle(.caption, tint: Theme.inkFaint) }
            } else {
                PrimaryAction(title: "Hold a board meeting \u{00B7} \(preview.count) \(preview.count == 1 ? "point" : "points")", identifier: "board-hold-meeting") {
                    let id: Int? = store.act { $0.holdBoardMeeting(key: key) } ?? nil
                    if id == nil { message = "Nothing to meet about right now." } else { message = "The board met. Its agenda is below."; Haptics.success() }
                }
            }
        }
    }

    private func emergencyButtons(_ m: ManagerModel.BoardMeeting) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(Array(m.options.enumerated()), id: \.offset) { (i: Int, o: String) in
                Button(o) {
                    pending = PendingAction(title: "Decide: \(o)?", message: "An emergency decision of the board takes effect at once and cannot be undone.", button: "Decide", destructive: true) {
                        let r: String? = store.act { $0.pickEmergency(key: key, meetingID: m.id, option: i) } ?? nil
                        let said: String = r == "hire" ? "Decided. Pick a new manager in the company's Team." : "Decided: \(o)."
                        message = said
                        Haptics.success()
                        store.outcome(chosen: "Decide: \(o)", result: said)
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
            case .refused(let why)?: message = "Not done: " + why; store.show(message, tone: "warn"); return
            case .gone?: message = "That point is no longer on the agenda."; store.show(message, tone: "warn"); return
            default: message = "Done."
            }
            store.outcome(chosen: approveWord(it), result: message)
        }
    }

    private func decline(_ m: ManagerModel.BoardMeeting, _ it: ManagerModel.MeetingItem) {
        let r = store.act { $0.decideMeetingItem(key: key, meetingID: m.id, item: it.id, approve: false) }
        if case .gone? = r { message = "That point is no longer on the agenda."; store.show(message, tone: "warn"); return }
        message = isConcern(it) ? "Left as it is. It goes in the minutes." : "Declined. It goes in the minutes."
        store.outcome(chosen: declineWord(it), result: message)
    }

    private func itemRow(_ m: ManagerModel.BoardMeeting, _ it: ManagerModel.MeetingItem, _ engine: GameEngine) -> some View {
        let co: Company? = engine.state.company(it.companyID)
        var costText: String = "Nothing"
        if it.cost > 0, let co { costText = store.short(it.cost, in: co) }
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(it.text.tidyMoney).textStyle(.body, tint: Theme.ink).fixedSize(horizontal: false, vertical: true)
            if !it.raisedBy.isEmpty { Text("Raised by \(it.raisedBy)").textStyle(.caption, tint: Theme.inkFaint) }
            if !it.effect.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    detailLine("If you approve", it.effect.tidyMoney)
                    detailLine("Cost now", costText)
                    detailLine("Risk", it.risk)
                }
            }
            HStack(spacing: Theme.Space.m) {
                Button(approveWord(it)) { approve(m, it, engine) }.buttonStyle(QuietButtonStyle())
                Button(declineWord(it)) { decline(m, it) }.buttonStyle(GreyOutlineButtonStyle())
            }
        }
    }

    @ViewBuilder private func detailLine(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(label).textStyle(.caption, tint: Theme.inkFaint, weight: .medium).frame(width: 92, alignment: .leading)
                Text(value).textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func meeting(_ m: ManagerModel.BoardMeeting, _ engine: GameEngine) -> some View {
        Card(padding: Theme.Space.l, radius: Theme.Radius.hero, fill: Theme.surface) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    IconCircle(glyph: m.isEmergency ? Glyph.warning : Glyph.calendar, size: 36, tint: m.isEmergency ? Theme.caution : Theme.gold)
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(m.title.tidyMoney).textStyle(.body, tint: Theme.ink, weight: .medium).fixedSize(horizontal: false, vertical: true)
                        Text(GameCalendar.dateString(week: m.week)).textStyle(.caption, tint: Theme.inkSoft)
                        if !m.why.isEmpty && m.why != "Regular meeting" { Text(m.why.tidyMoney).textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true) }
                        if !m.attendees.isEmpty {
                            let present: String = "Present: " + m.attendees.joined(separator: " · ")
                            Text(present).textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
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
                    Card(padding: Theme.Space.m, radius: Theme.Radius.card) {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            Text(f.text.tidyMoney).textStyle(.body, tint: Theme.ink).fixedSize(horizontal: false, vertical: true)
                            let lapse: String = f.assignee + " · lapses " + GameCalendar.dateString(week: f.due)
                            Text(lapse).textStyle(.caption, tint: Theme.inkFaint)
                            HStack(spacing: Theme.Space.m) {
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
        return Card(padding: Theme.Space.m, radius: Theme.Radius.card) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).textStyle(.body, tint: Theme.ink, weight: .medium)
                    Spacer(minLength: 8)
                    Text(date).textStyle(.caption, tint: Theme.inkFaint)
                }
                ForEach(Array(lines.enumerated()), id: \.offset) { (_: Int, line: String) in
                    Text(line).textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                }
                if lines.isEmpty { Text("Nothing was decided.").textStyle(.caption, tint: Theme.inkFaint) }
            }
        }
    }

    private func closedJobLine(_ f: ManagerModel.FollowUp) -> some View {
        let state: String = f.status == "done" ? "done" : "lapsed"
        let note: String = f.note.isEmpty ? "" : " (" + f.note + ")"
        let text: String = "Follow-up " + state + ": " + f.text.tidyMoney + note
        return Text(text).textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func minutes(_ engine: GameEngine) -> some View {
        let all: [ManagerModel.BoardMeeting] = engine.boardMeetings(key: key)
        let done: [ManagerModel.BoardMeeting] = Array(all.filter { !$0.isOpen }.prefix(6))
        let closedJobs: [ManagerModel.FollowUp] = engine.boardFollowUps(key: key).filter { !$0.status.isEmpty }
        let jobs: [ManagerModel.FollowUp] = Array(closedJobs.suffix(4).reversed())
        let empty: Bool = done.isEmpty && jobs.isEmpty
        MoreBlock("Minutes and outcomes", card: false) {
            if empty { NoteCard(text: "No minutes yet.") }
            ForEach(done) { m in minutesCard(m) }
            ForEach(jobs) { f in closedJobLine(f) }
        }
    }

    // MARK: Who sits at the table

    private func voterCard(_ v: ManagerModel.Voter, seats: [ManagerModel.Seat]) -> some View {
        HStack(spacing: Theme.Space.m) {
            voterPortrait(v)
                .orgEdge(freshSeats.contains(v.id) ? Theme.gold : nil, radius: 17)
            VStack(alignment: .leading, spacing: 1) {
                Text(v.name).textStyle(.body, tint: Theme.ink, weight: .medium).lineLimit(1)
                Text("\(v.title) · \(v.votes ? "votes" : "advises")").textStyle(.caption, tint: Theme.inkSoft).lineLimit(2)
                // An adviser's fee and record sit under their own name.
                if let pid = v.personID, let a = seats.first(where: { $0.id == pid && $0.isAdviser }) {
                    Text("Fee \(store.short(a.monthlyFee)) a month \u{00B7} took \(a.adviceTaken) of your calls, refused \(a.adviceRefused)")
                        .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let pid = v.personID, seats.contains(where: { $0.id == pid }) {
                Button("Remove") {
                    if let ask = store.removeSeatPrompt(key: key, personID: pid, name: v.name) { pending = ask }
                }
                .buttonStyle(TertiaryButtonStyle(size: .compact, tint: Theme.loss))
                .accessibilityLabel("Remove \(v.name) from the board")
            }
        }
    }

    @ViewBuilder private func voterPortrait(_ v: ManagerModel.Voter) -> some View {
        if let pid = v.personID, let p = store.engine?.state.people[pid] {
            ThumbnailView(kind: .person, key: p.role, size: 34, initials: v.name, face: p.faceKey)
        } else {
            IconCircle(glyph: v.votes ? Glyph.person : Glyph.people, size: 34, tint: v.votes ? Theme.gold : Theme.ivoryMuted)
        }
    }

    private func seatFinder(_ engine: GameEngine) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SegmentedPill(items: [false, true], title: { (own: Bool) -> String in own ? "Your people" : "Search" }, selection: $ownTab)
            Text(ownTab ? "Staff of this company sit for half the fee" : "A search costs a fee")
                .textStyle(.caption, tint: Theme.inkSoft)
            // One row opens the list of seats; picking a seat searches for it (or lists your own people for it).
            Menu {
                ForEach(engine.seatRoles) { r in
                    Button(r.title) {
                        if ownTab { loadOwn(engine, seat: r.id); return }
                        let found: [Person]? = store.act { $0.searchForSeat(key: key, role: r.id) } ?? nil
                        if let found { candidates = found; message = found.isEmpty ? "Nobody suitable answered." : "" } else { message = "Not enough cash for a search." }
                    }
                }
            } label: {
                LedgerRow(leading: .symbol(ownTab ? "person.2" : "magnifyingglass"), title: ownTab ? "Pick a seat for one of your people" : "Search for a seat",
                          chevron: true)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("board-seat-finder")
        }
    }

    /// The company whose board this is (for a chain, its first store): the engine finds the board again from it.
    private func loadOwn(_ engine: GameEngine, seat: String) {
        guard let cid = ManagerModel.boardCompanies(engine.state, key: key).first?.id else { return }
        ownList = engine.boardCandidates(companyID: cid, seat: seat).filter { (c: BoardCandidate) -> Bool in c.isOwnStaff }
        ownSeat = seat
        message = ownList.isEmpty ? "None of your people qualify for that seat yet." : ""
    }

    private func ownRow(_ c: BoardCandidate) -> some View {
        let fee: Double = c.feePerYear / 12
        return HStack(spacing: Theme.Space.m) {
            Text("\(c.name) \u{00B7} \(c.qualification)").textStyle(.caption, tint: Theme.ink).lineLimit(2)
            Spacer(minLength: 8)
            Button("Seat \u{00B7} \(store.short(fee)) a month") {
                pending = PendingAction(title: "Seat \(c.name) on the board?", message: "They keep their job and also sit on the board. Cost: \(store.short(fee)) a month in fees.", button: "Seat them", amount: fee, currency: store.engine?.homeCurrency) { seatOwn(c) }
            }.buttonStyle(TinyButtonStyle()).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private func seatOwn(_ c: BoardCandidate) {
        guard let e = store.engine, let cid = ManagerModel.boardCompanies(e.state, key: key).first?.id else { return }
        let seat: String = ownSeat
        let r: SettingResult? = store.act { $0.appointOwnToBoard(companyID: cid, seat: seat, personID: c.personID) }
        switch r {
        case .applied?: message = "\(c.name) joins the board."; ownList = []; Haptics.success()
        case .refused(let why)?: message = why
        default: message = "\(c.name) could not be seated."
        }
        store.outcome(chosen: "Seat them", result: message)
    }

    private func candidateRow(_ p: Person) -> some View {
        let fee: Double = p.num("fee13")
        return HStack(spacing: Theme.Space.m) {
            Text("\(p.name) · \(p.str("advBg"))").textStyle(.caption, tint: Theme.ink).lineLimit(2)
            Spacer(minLength: 8)
            Button("Seat · \(store.short(fee)) a month") {
                pending = PendingAction(title: "Seat \(p.name) on the board?", message: "Cost: \(store.short(fee)) a month in fees, for as long as they sit. The owners vote on it, and may refuse. You can let an adviser go later.", button: "Seat them", amount: fee, currency: store.engine?.homeCurrency) { seat(p, fee: fee) }
            }.buttonStyle(TinyButtonStyle()).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    @ViewBuilder private func table(_ engine: GameEngine) -> some View {
        let seats: [ManagerModel.Seat] = engine.boardSeats(key: key)
        MoreBlock("At the table") {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                ForEach(Array(engine.boardVoters(key: key).enumerated()), id: \.element.id) { (n: Int, v: ManagerModel.Voter) in
                    if n > 0 { CardLine() }
                    voterCard(v, seats: seats).transition(AnyTransition.orgNode)
                }
                CardLine()
                seatFinder(engine)
                if ownTab {
                    ForEach(ownList) { c in ownRow(c) }
                } else {
                    ForEach(candidates) { p in candidateRow(p) }
                }
            }
            .orgArrivals(engine.boardVoters(key: key).map { $0.id }, fresh: $freshSeats)
        }
    }

    private func seat(_ p: Person, fee: Double) {
        let r = store.fillSeatOutcome(key: key, person: p, fee: fee)
        message = r.text
        store.outcome(chosen: "Seat them", result: r.text)
        if r.joined { candidates = []; Haptics.success() }
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
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SegmentedPill(items: [false, true], title: { $0 ? "Regularly" : "When needed" }, selection: modeBinding)
                if regular {
                    SegmentedPill(items: [false, true], title: { $0 ? "Quarterly" : "Every 4 weeks" }, selection: freqBinding)
                }
                Text(regular ? "The board meets on a schedule and puts its own items on the agenda." : "The board meets only when you call it or something needs it.")
                    .textStyle(.caption, tint: Theme.inkFaint)
            }
        }
    }

    // MARK: Big moves

    private func voteRow(label: String, vote: ManagerModel.BoardVote) -> some View {
        let pct: Double = vote.percentYes
        let tail: String = (vote.passes ? "would pass" : "would not pass") + (vote.decidingOwner.map { " · \($0) decides" } ?? "")
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            RateBar(label: label, fraction: pct / 100, tint: vote.passes ? Theme.gain : Theme.caution)
            Text("\(Int(pct.rounded()))% yes · \(tail)").textStyle(.caption, tint: vote.passes ? Theme.gain : Theme.warn)
        }
    }

    @ViewBuilder private func bigMoves(_ engine: GameEngine, companies: [Company]) -> some View {
        if let co = companies.first {
            let votes = [("sell", "Selling"), ("close", "Closing")].map { (label: $0.1, vote: engine.boardVote(kind: $0.0, companyID: co.id)) }.filter { $0.vote.active }
            let power = engine.ownersPower(companyID: co.id)
            if !votes.isEmpty || !(power?.text.isEmpty ?? true) {
                MoreBlock("What the board says to a big move") {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        ForEach(Array(votes.enumerated()), id: \.offset) { _, v in voteRow(label: v.label, vote: v.vote) }
                        if let p = power, !p.text.isEmpty {
                            Text("Other owners: " + p.text).textStyle(.caption, tint: Theme.inkFaint)
                        }
                    }
                }
            }
        }
    }
}
