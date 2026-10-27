import SwiftUI
import GameCore
import Businesses
import Simulation

/// Group > Boards: every board that sits over a chain or a company, decisions first, each opening its own page. Owners, dividends and
/// buy-backs stay in each company's Money; stakes in other groups and the big-meeting offer stay under Money, Invest. Logic: `ManagerModel` boards.
struct BoardsGroupSection: View {
    var engine: GameEngine
    var openInvest: () -> Void

    var body: some View {
        let keys: [String] = engine.boardKeys.filter { engine.boardIsActive(key: $0) }
        let waiting: [String: Int] = Dictionary(uniqueKeysWithValues: keys.map { ($0, engine.boardMeetings(key: $0).filter { $0.status.isEmpty }.count) })
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
        let waiting: Int = engine.boardMeetings(key: key).filter { $0.status.isEmpty }.count
        let kind: String = key.hasPrefix("ch:") ? "Chain board" : "Company board"
        let sub: String = "\(kind) · \(seats) \(seats == 1 ? "seat" : "seats") filled" + (waiting > 0 ? " · \(waiting) to decide" : "")
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
                    table(engine)
                    meets(engine)
                    bigMoves(engine, companies: companies)
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

    @ViewBuilder private func agenda(_ engine: GameEngine) -> some View {
        let open: [ManagerModel.BoardMeeting] = engine.boardMeetings(key: key).filter { $0.status.isEmpty }
        MoreBlock(title: "To decide", card: false, trailing: { RedBubble(count: open.count, size: .small) }) {
            if open.isEmpty { NoteCard(text: "Nothing waits for the board.", glyph: Glyph.check) }
            ForEach(open) { m in meeting(m) }
            QuietButton(title: "Hold a board meeting") {
                let id: Int? = store.act { $0.holdBoardMeeting(key: key) } ?? nil
                if id == nil { message = "Nothing to meet about yet." } else { message = ""; Haptics.success(); store.show("The board met. Its agenda is below.", tone: "good") }
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

    private func approve(_ m: ManagerModel.BoardMeeting, _ it: ManagerModel.MeetingItem) {
        let r = store.act { $0.decideMeetingItem(key: key, meetingID: m.id, item: it.id, approve: true) }
        switch r {
        case .followUp(let what)?: message = "Approved. Follow up on it (\(what)) in the company."
        case .done(let what)?: message = what.isEmpty ? "Approved." : what
        case .gone?: message = "That item is no longer on the agenda."
        default: message = "Approved."
        }
    }

    private func decline(_ m: ManagerModel.BoardMeeting, _ it: ManagerModel.MeetingItem) {
        let r = store.act { $0.decideMeetingItem(key: key, meetingID: m.id, item: it.id, approve: false) }
        if case .gone? = r { message = "That item is no longer on the agenda." } else { message = "Declined." }
    }

    private func itemRow(_ m: ManagerModel.BoardMeeting, _ it: ManagerModel.MeetingItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(it.text.tidyMoney).font(.system(size: 13)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Approve") { approve(m, it) }.buttonStyle(QuietButtonStyle())
                Button("Decline") { decline(m, it) }.buttonStyle(GreyOutlineButtonStyle())
            }
        }
    }

    @ViewBuilder private func meeting(_ m: ManagerModel.BoardMeeting) -> some View {
        Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    IconCircle(glyph: m.isEmergency ? Glyph.warning : Glyph.calendar, size: 36, tint: m.isEmergency ? Theme.caution : Theme.gold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.title.tidyMoney).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                        if !m.why.isEmpty { Text(m.why.tidyMoney).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true) }
                    }
                }
                if m.isEmergency {
                    emergencyButtons(m)
                } else {
                    ForEach(m.items.filter { $0.status.isEmpty }) { it in
                        CardLine()
                        itemRow(m, it)
                    }
                }
            }
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
