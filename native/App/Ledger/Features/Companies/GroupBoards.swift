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
        let keys = engine.boardKeys.filter { engine.boardIsActive(key: $0) }
        let waiting = Dictionary(uniqueKeysWithValues: keys.map { ($0, engine.boardMeetings(key: $0).filter { $0.status.isEmpty }.count) })
        let ordered = keys.sorted { (waiting[$0] ?? 0, $0.hasPrefix("ch:") ? 1 : 0) > (waiting[$1] ?? 0, $1.hasPrefix("ch:") ? 1 : 0) }
        LedgerSection(title: "Boards", trailing: { Text("\(keys.count)").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint) }) {
            VStack(alignment: .leading, spacing: 0) {
                if keys.isEmpty {
                    Text("A board forms once you register a chain or somebody else owns part of a company.").font(.caption).foregroundStyle(Theme.ivoryFaint).padding(.bottom, 6)
                }
                ForEach(Array(ordered.enumerated()), id: \.element) { n, key in
                    if n > 0 { Hairline() }
                    NavigationLink { BoardView(key: key) } label: { BoardLinkRow(engine: engine, key: key) }.buttonStyle(.plain)
                }
                Hairline()
                Button(action: openInvest) {
                    GroupLinkRow(title: "Stakes in other groups and the big meeting offer", sub: "In the Bank app. Owners, dividends and buy-backs are in each company's Finances.")
                }.buttonStyle(.plain)
            }
        }
    }
}

/// One board as a row: whose board, seats, and what waits for a decision.
struct BoardLinkRow: View {
    var engine: GameEngine
    var key: String

    var body: some View {
        let seats = engine.boardSeats(key: key).count
        let waiting = engine.boardMeetings(key: key).filter { $0.status.isEmpty }.count
        let kind = key.hasPrefix("ch:") ? "Chain board" : "Company board"
        GroupLinkRow(title: engine.boardName(key: key),
                     sub: "\(kind) · \(seats) \(seats == 1 ? "seat" : "seats") filled" + (waiting > 0 ? " · \(waiting) to decide" : ""),
                     subTint: waiting > 0 ? Theme.caution : Theme.ivoryFaint)
    }
}

/// One board: what waits for a decision, how often it meets, who sits at the table, adding advisers, and what it says to a big move.
/// Opened from Group > Boards, from the chain page and from a company's owners.
struct BoardView: View {
    @EnvironmentObject var store: GameStore
    var key: String
    @State private var message = ""
    @State private var candidates: [Person] = []
    @State private var pending: PendingAction?

    var body: some View {
        if let engine = store.engine, engine.boardIsActive(key: key) {
            let companies = ManagerModel.boardCompanies(engine.state, key: key)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    if !message.isEmpty { Text(message).font(.caption).foregroundStyle(Theme.ivoryMuted) }
                    agenda(engine)
                    table(engine)
                    meets(engine)
                    bigMoves(engine, companies: companies)
                    if key.hasPrefix("co:"), let co = companies.first {
                        NavigationLink(value: CompanyRoute.companyAt(co.id, .finances)) {
                            GroupLinkRow(title: "Owners and shares of \(co.name)", sub: "Who owns what, dividends and buy-backs, in the company's Finances.")
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
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

    // MARK: To decide

    @ViewBuilder private func agenda(_ engine: GameEngine) -> some View {
        let open = engine.boardMeetings(key: key).filter { $0.status.isEmpty }
        LedgerSection(title: "To decide", trailing: { Text("\(open.count)").font(.system(size: 11)).foregroundStyle(open.isEmpty ? Theme.ivoryFaint : Theme.caution) }) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if open.isEmpty { Text("Nothing waits for the board.").font(.caption).foregroundStyle(Theme.ivoryFaint) }
                ForEach(open) { m in meeting(m) }
                Button("Hold a board meeting") {
                    let id: Int? = store.act { $0.holdBoardMeeting(key: key) } ?? nil
                    if id == nil { message = "Nothing to meet about yet." } else { message = ""; Haptics.success(); store.show("The board met. Its agenda is below.", tone: "good") }
                }.buttonStyle(SmallGoldButtonStyle())
            }
        }
    }

    @ViewBuilder private func meeting(_ m: ManagerModel.BoardMeeting) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(m.title.tidyMoney).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ivory)
            if !m.why.isEmpty { Text(m.why.tidyMoney).font(.caption).foregroundStyle(Theme.ivoryMuted) }
            if m.isEmergency {
                ForEach(Array(m.options.enumerated()), id: \.offset) { i, o in
                    Button(o) {
                        pending = PendingAction(title: "Decide: \(o)?", message: "An emergency decision of the board takes effect at once and cannot be undone.", button: "Decide") {
                            let r: String? = store.act { $0.pickEmergency(key: key, meetingID: m.id, option: i) } ?? nil
                            message = r == "hire" ? "Decided. Pick a new manager in the company's Team." : "Decided: \(o)."
                            Haptics.success()
                        }
                    }.buttonStyle(SmallOutlineButtonStyle())
                }
            } else {
                ForEach(m.items.filter { $0.status.isEmpty }) { it in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(it.text.tidyMoney).font(.caption).foregroundStyle(Theme.ivory)
                        HStack {
                            Button("Approve") {
                                let r = store.act { $0.decideMeetingItem(key: key, meetingID: m.id, item: it.id, approve: true) }
                                switch r {
                                case .followUp(let what)?: message = "Approved. Follow up on it (\(what)) in the company."
                                case .done(let what)?: message = what.isEmpty ? "Approved." : what
                                case .gone?: message = "That item is no longer on the agenda."
                                default: message = "Approved."
                                }
                            }.buttonStyle(SmallGoldButtonStyle())
                            Button("Decline") {
                                let r = store.act { $0.decideMeetingItem(key: key, meetingID: m.id, item: it.id, approve: false) }
                                if case .gone? = r { message = "That item is no longer on the agenda." } else { message = "Declined." }
                            }.buttonStyle(SmallOutlineButtonStyle())
                        }
                    }
                }
            }
        }.padding(.vertical, 4)
    }

    // MARK: Who sits at the table

    @ViewBuilder private func table(_ engine: GameEngine) -> some View {
        let seats = engine.boardSeats(key: key)
        LedgerSection("At the table") {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                ForEach(engine.boardVoters(key: key)) { v in
                    HStack {
                        Text("\(v.name) · \(v.title)").font(.system(size: 12.5)).foregroundStyle(Theme.ivory).lineLimit(1)
                        Spacer()
                        Text(v.votes ? "votes" : "advises").font(.caption).foregroundStyle(Theme.ivoryFaint)
                        if let pid = v.personID, seats.contains(where: { $0.id == pid && $0.isAdviser }) {
                            Button("Let go") {
                                pending = PendingAction(title: "Let \(v.name) go from the board?", message: "Their monthly fee stops and their advice leaves with them.", button: "Let go", destructive: true) {
                                    store.act { $0.removeFromBoard(key: key, personID: pid) }
                                    message = "\(v.name) left the board."
                                }
                            }.buttonStyle(SmallOutlineButtonStyle()).frame(width: 90)
                        }
                    }
                }
                ForEach(seats.filter { $0.isAdviser }) { s in
                    Text("\(s.title) · fee \(store.short(s.monthlyFee)) a month · took \(s.adviceTaken) of your calls, refused \(s.adviceRefused)").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
                Text("Add to the board (a search costs a fee)").font(.caption).foregroundStyle(Theme.ivoryMuted).padding(.top, 4)
                WrapRow {
                    Group {
                        ForEach(engine.seatRoles) { r in
                            Button(r.title) {
                                let found: [Person]? = store.act { $0.searchForSeat(key: key, role: r.id) } ?? nil
                                if let found { candidates = found; message = found.isEmpty ? "Nobody suitable answered." : "" } else { message = "Not enough cash for a search." }
                            }.buttonStyle(SmallOutlineButtonStyle()).fixedSize()
                        }
                    }
                }
                ForEach(candidates) { p in
                    let fee = p.num("fee13")
                    HStack {
                        Text("\(p.name) · \(p.str("advBg"))").font(.caption).foregroundStyle(Theme.ivory).lineLimit(2)
                        Spacer()
                        Button("Seat · \(store.short(fee)) a month") {
                            pending = PendingAction(title: "Seat \(p.name) on the board?", message: "Cost: \(store.short(fee)) a month in fees, for as long as they sit. The owners vote on it, and may refuse. You can let an adviser go later.", button: "Seat them") { seat(p, fee: fee) }
                        }.buttonStyle(SmallGoldButtonStyle()).fixedSize()
                    }
                }
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
        let regular = board["mode"].string == "regular"
        let quarterly = board["freq"].int >= 13
        LedgerSection("Meets") {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack {
                    Button("When needed") { store.settle(store.act { $0.setBoardMode(key: key, regular: false) }, "The board meets when needed.", same: "It already meets when needed.") }.buttonStyle(SmallOutlineButtonStyle()).opacity(regular ? 0.5 : 1)
                    Button("Regularly") { store.settle(store.act { $0.setBoardMode(key: key, regular: true) }, "The board meets regularly.", same: "It already meets regularly.") }.buttonStyle(SmallOutlineButtonStyle()).opacity(regular ? 1 : 0.5)
                }
                if regular {
                    HStack {
                        Button("Every 4 weeks") { store.settle(store.act { $0.setBoardMode(key: key, quarterly: false) }, "The board meets every 4 weeks.", same: "It already meets every 4 weeks.") }.buttonStyle(SmallOutlineButtonStyle()).opacity(quarterly ? 0.5 : 1)
                        Button("Quarterly") { store.settle(store.act { $0.setBoardMode(key: key, quarterly: true) }, "The board meets quarterly.", same: "It already meets quarterly.") }.buttonStyle(SmallOutlineButtonStyle()).opacity(quarterly ? 1 : 0.5)
                    }
                }
                Text(regular ? "The board meets on a schedule and puts its own items on the agenda." : "The board meets only when you call it or something needs it.")
                    .font(.caption2).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    // MARK: Big moves

    @ViewBuilder private func bigMoves(_ engine: GameEngine, companies: [Company]) -> some View {
        if let co = companies.first {
            let votes = [("sell", "Selling"), ("close", "Closing")].map { (label: $0.1, vote: engine.boardVote(kind: $0.0, companyID: co.id)) }.filter { $0.vote.active }
            let power = engine.ownersPower(companyID: co.id)
            if !votes.isEmpty || !(power?.text.isEmpty ?? true) {
                LedgerSection("What the board says to a big move") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(votes.enumerated()), id: \.offset) { _, v in
                            Text("\(v.label): \(Int(v.vote.percentYes.rounded()))% yes · " + (v.vote.passes ? "would pass" : "would not pass") + (v.vote.decidingOwner.map { " · \($0) decides" } ?? ""))
                                .font(.caption).foregroundStyle(v.vote.passes ? Theme.gain : Theme.caution)
                        }
                        if let p = power, !p.text.isEmpty {
                            Text("Other owners: " + p.text).font(.caption2).foregroundStyle(Theme.ivoryFaint)
                        }
                    }
                }
            }
        }
    }
}
