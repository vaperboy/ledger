import SwiftUI
import GameCore
import Businesses
import Simulation

/// Group > Holdings: the boards that sit over each chain or company (seats, advisers, meetings, decisions) and what the owners can do.
/// Owners, dividends and buy-backs stay in each company's Money; the big-meeting offer stays under Money, Invest. Logic: `ManagerModel` boards.
struct BoardsGroupSection: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var openInvest: () -> Void
    @State private var open: String?
    @State private var message = ""
    @State private var candidates: [String: [Person]] = [:]

    var body: some View {
        let keys = engine.boardKeys.filter { engine.boardIsActive(key: $0) }
        LedgerSection("Boards and stakes") {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if !message.isEmpty { Text(message).font(.caption).foregroundStyle(Theme.ivoryMuted) }
                if keys.isEmpty {
                    Text("A board forms once somebody else owns part of a company or you register a chain.").font(.caption).foregroundStyle(Theme.ivoryFaint)
                }
                ForEach(keys, id: \.self) { key in
                    Hairline()
                    boardRow(key)
                }
                Hairline()
                Button(action: openInvest) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stakes in other groups and the big meeting offer").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                            Text("Under Money, Invest. Owners, dividends and buy-backs are in each company's Money.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                    }.padding(.vertical, 6).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func boardRow(_ key: String) -> some View {
        let seats = engine.boardSeats(key: key)
        let pending = engine.boardMeetings(key: key).filter { $0.status.isEmpty }.count
        Button { open = open == key ? nil : key } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.boardName(key: key)).font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                    Text("\(seats.count) \(seats.count == 1 ? "seat" : "seats") filled" + (pending > 0 ? " · \(pending) to decide" : ""))
                        .font(.system(size: 11)).foregroundStyle(pending > 0 ? Theme.caution : Theme.ivoryFaint)
                }
                Spacer()
                Image(systemName: open == key ? "chevron.up" : "chevron.down").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }.padding(.vertical, 6).contentShape(Rectangle())
        }.buttonStyle(.plain)
        if open == key { detail(key, seats: seats) }
    }

    @ViewBuilder private func detail(_ key: String, seats: [ManagerModel.Seat]) -> some View {
        let board = ManagerModel.board(engine.state, key: key)
        let regular = board["mode"].string == "regular"
        let quarterly = board["freq"].int >= 13
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Meets").font(.caption).foregroundStyle(Theme.ivoryMuted)
            HStack {
                Button("When needed") { store.act { $0.setBoardMode(key: key, regular: false) } }.buttonStyle(SmallOutlineButtonStyle()).opacity(regular ? 0.5 : 1)
                Button("Regularly") { store.act { $0.setBoardMode(key: key, regular: true) } }.buttonStyle(SmallOutlineButtonStyle()).opacity(regular ? 1 : 0.5)
            }
            if regular {
                HStack {
                    Button("Every 4 weeks") { store.act { $0.setBoardMode(key: key, quarterly: false) } }.buttonStyle(SmallOutlineButtonStyle()).opacity(quarterly ? 0.5 : 1)
                    Button("Quarterly") { store.act { $0.setBoardMode(key: key, quarterly: true) } }.buttonStyle(SmallOutlineButtonStyle()).opacity(quarterly ? 1 : 0.5)
                }
            }
            Text("At the table").font(.caption).foregroundStyle(Theme.ivoryMuted)
            ForEach(engine.boardVoters(key: key)) { v in
                HStack {
                    Text("\(v.name) · \(v.title)").font(.system(size: 12.5)).foregroundStyle(Theme.ivory).lineLimit(1)
                    Spacer()
                    Text(v.votes ? "votes" : "advises").font(.caption).foregroundStyle(Theme.ivoryFaint)
                    if let pid = v.personID, seats.contains(where: { $0.id == pid && $0.isAdviser }) {
                        Button("Let go") { store.act { $0.removeFromBoard(key: key, personID: pid) } }.buttonStyle(SmallOutlineButtonStyle()).frame(width: 90)
                    }
                }
            }
            ForEach(seats.filter { $0.isAdviser }) { s in
                Text("\(s.title) · fee \(store.short(s.monthlyFee)) a month · took \(s.adviceTaken) of your calls, refused \(s.adviceRefused)").font(.caption2).foregroundStyle(Theme.ivoryFaint)
            }
            Text("Add to the board (a search costs a fee)").font(.caption).foregroundStyle(Theme.ivoryMuted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(engine.seatRoles) { r in
                        Button(r.title) {
                            let found: [Person]? = store.act { $0.searchForSeat(key: key, role: r.id) } ?? nil
                            if let found { candidates[key] = found; message = "" } else { message = "Not enough cash for a search." }
                        }.buttonStyle(SmallOutlineButtonStyle()).fixedSize()
                    }
                }
            }
            ForEach(candidates[key] ?? []) { p in
                let fee = p.num("fee13")
                HStack {
                    Text("\(p.name) · \(p.str("advBg"))").font(.caption).foregroundStyle(Theme.ivory).lineLimit(2)
                    Spacer()
                    Button("Seat · \(store.short(fee)) a month") {
                        let r = store.act { $0.fillSeat(key: key, personID: p.id, monthlyFee: fee) }
                        switch r {
                        case .ok?: message = "\(p.name) joins the board."; candidates[key] = nil
                        case .full?: message = "That seat is full."
                        case .refused?: message = "\(p.name) wants more."
                        case .votedDown(let n)?: message = "The owners voted \(p.name) down (\(n)% behind them)."
                        default: message = "\(p.name) is not available."
                        }
                    }.buttonStyle(SmallGoldButtonStyle()).fixedSize()
                }
            }
            Button("Hold a board meeting") {
                let id: Int? = store.act { $0.holdBoardMeeting(key: key) } ?? nil
                message = id == nil ? "Nothing to meet about yet." : ""
            }.buttonStyle(SmallGoldButtonStyle())
            ForEach(engine.boardMeetings(key: key).filter { $0.status.isEmpty }) { m in meeting(key, m) }
            if let co = ManagerModel.boardCompanies(engine.state, key: key).first {
                Text("What the board says to a big move").font(.caption).foregroundStyle(Theme.ivoryMuted)
                ForEach([("sell", "Selling"), ("close", "Closing")], id: \.0) { kind, label in
                    let v = engine.boardVote(kind: kind, companyID: co.id)
                    if v.active {
                        Text("\(label): \(Int(v.percentYes.rounded()))% yes · " + (v.passes ? "would pass" : "would not pass") + (v.decidingOwner.map { " · \($0) decides" } ?? ""))
                            .font(.caption2).foregroundStyle(v.passes ? Theme.gain : Theme.caution)
                    }
                }
                if let p = engine.ownersPower(companyID: co.id), !p.text.isEmpty {
                    Text("Other owners: " + p.text).font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
            }
        }
        .padding(.leading, Theme.Space.s)
    }

    @ViewBuilder private func meeting(_ key: String, _ m: ManagerModel.BoardMeeting) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(m.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ivory)
            if !m.why.isEmpty { Text(m.why).font(.caption).foregroundStyle(Theme.ivoryMuted) }
            if m.isEmergency {
                ForEach(Array(m.options.enumerated()), id: \.offset) { i, o in
                    Button(o) {
                        let r: String? = store.act { $0.pickEmergency(key: key, meetingID: m.id, option: i) } ?? nil
                        if r == "hire" { message = "Pick a new manager under Team." }
                    }.buttonStyle(SmallOutlineButtonStyle())
                }
            } else {
                ForEach(m.items.filter { $0.status.isEmpty }) { it in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(it.text).font(.caption).foregroundStyle(Theme.ivory)
                        HStack {
                            Button("Approve") {
                                let r = store.act { $0.decideMeetingItem(key: key, meetingID: m.id, item: it.id, approve: true) }
                                if case .followUp(let what)? = r { message = "Approved. Follow up on it (\(what)) in the company." }
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
}
