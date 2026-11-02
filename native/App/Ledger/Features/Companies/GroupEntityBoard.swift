import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// An entity's board as thin seat rows: an avatar circle (or a '+' ring for an open seat), the role, and "Appoint" in champagne at the right.
/// The owner comes first (with a "Works here" chip where he runs the company himself). Appointing uses the board engine (a search costs a
/// fee, the owners vote on a seat); the agenda, the minutes and the meeting rhythm stay on the board room page one tap away.
struct GroupEntityBoard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var entity: GroupEntity
    @State private var searchRole: String?
    @State private var candidates: [Person] = []
    @State private var message = ""
    @State private var pending: PendingAction?

    var body: some View {
        let key: String = engine.boardKey(companyID: entity.companyID) ?? ""
        let active: Bool = !key.isEmpty && engine.boardIsActive(key: key)
        VStack(alignment: .leading, spacing: 12) {
            if !message.isEmpty { NoteCard(text: message) }
            if active { roomLink(key) }
            Card(padding: 4, radius: Theme.Radius.hero) {
                VStack(spacing: 0) {
                    ownerRow
                    if active { seatRows(key) }
                }
            }
            if !active {
                Text("A full board forms once you register a chain or somebody else owns part of this company. Until then you decide alone.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmAction($pending)
        .onChange(of: message) { _, new in if !new.isEmpty { store.show(new, tone: "n") } }
    }

    // MARK: Rows

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return String(parts).uppercased()
    }

    private func avatar(_ text: String) -> some View {
        Text(text).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.gold)
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color(hex: 0x1E1F21)))
            .overlay(Circle().strokeBorder(Theme.borderStrong, lineWidth: 1))
    }

    private func plusRing() -> some View {
        Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ivoryFaint)
            .frame(width: 32, height: 32)
            .overlay(Circle().strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }

    private func line<Lead: View, Trail: View>(first: Bool, @ViewBuilder lead: () -> Lead, title: String, sub: String, chip: String = "", @ViewBuilder trail: () -> Trail) -> some View {
        HStack(spacing: 10) {
            lead()
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                if !sub.isEmpty { Text(sub).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(1) }
            }
            if !chip.isEmpty { Chip(text: chip, tint: Theme.gold) }
            Spacer(minLength: 6)
            trail()
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(minHeight: 46)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Theme.divider).frame(height: 1) } }
    }

    /// True when the owner himself works in one of the entity's companies (no manager, hours above zero).
    private var ownerWorksHere: Bool {
        for id in entity.members {
            guard let c = engine.state.company(id), c.status.isLive, c.type != "hold" else { continue }
            if c.managerID == nil && c.ownerHours > 0 { return true }
        }
        return false
    }

    private var ownerRow: some View {
        let name: String = engine.state.player.name
        return line(first: true, lead: { avatar(initials(name)) }, title: name, sub: "Owner", chip: ownerWorksHere ? "Works here" : "", trail: { EmptyView() })
    }

    @ViewBuilder private func seatRows(_ key: String) -> some View {
        let voters: [ManagerModel.Voter] = engine.boardVoters(key: key)
        let seats: [ManagerModel.Seat] = engine.boardSeats(key: key)
        ForEach(voters) { (v: ManagerModel.Voter) in
            line(first: false, lead: { avatar(initials(v.name)) }, title: v.name, sub: v.title + (v.votes ? " \u{00B7} votes" : " \u{00B7} advises"), trail: {
                trailFor(v, seats: seats, key: key)
            })
        }
        ForEach(engine.seatRoles) { (r: ManagerModel.SeatRole) in
            let filled: Int = seats.filter { (s: ManagerModel.Seat) -> Bool in s.role == r.id }.count
            if filled < r.maxSeats {
                line(first: false, lead: { plusRing() }, title: r.title, sub: r.text, trail: {
                    Button { search(key, r) } label: {
                        Text(searchRole == r.id ? "Searching" : "Appoint").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.gold)
                            .frame(minWidth: 64, minHeight: 36, alignment: .trailing)
                            .contentShape(Rectangle())
                    }.buttonStyle(PressableStyle())
                })
                if searchRole == r.id { candidateRows(key) }
            }
        }
    }

    @ViewBuilder private func trailFor(_ v: ManagerModel.Voter, seats: [ManagerModel.Seat], key: String) -> some View {
        if let pid = v.personID, seats.contains(where: { (s: ManagerModel.Seat) -> Bool in s.id == pid && s.isAdviser }) {
            Button("Let go") {
                pending = PendingAction(title: "Let \(v.name) go from the board?", message: "Their monthly fee stops and their advice leaves with them.", button: "Let go", destructive: true) {
                    store.act { $0.removeFromBoard(key: key, personID: pid) }
                    message = "\(v.name) left the board."
                }
            }.buttonStyle(TinyButtonStyle(tint: Theme.loss))
        } else {
            EmptyView()
        }
    }

    @ViewBuilder private func candidateRows(_ key: String) -> some View {
        if candidates.isEmpty {
            Text("Nobody suitable answered the search.").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint).padding(.horizontal, 12).padding(.vertical, 8)
        }
        ForEach(candidates) { (p: Person) in
            let fee: Double = p.num("fee13")
            HStack(spacing: 8) {
                Text("\(p.name) \u{00B7} \(p.str("advBg"))").font(.system(size: 12.5)).foregroundStyle(Theme.ivory).lineLimit(2)
                Spacer(minLength: 6)
                Button("Seat \u{00B7} \(store.short(fee)) a month") {
                    pending = PendingAction(title: "Seat \(p.name) on the board?", message: "Cost: \(store.short(fee)) a month in fees, for as long as they sit. The owners vote on it, and may refuse. You can let an adviser go later.", button: "Seat them", amount: fee, currency: engine.homeCurrency) { seat(key, p, fee) }
                }.buttonStyle(TinyButtonStyle()).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.surface.opacity(0.6))
        }
    }

    private func roomLink(_ key: String) -> some View {
        let waiting: Int = engine.boardOpenDecisions(key: key)
        let sub: String = waiting > 0 ? "\(waiting) \(waiting == 1 ? "point waits" : "points wait") for your decision" : "Agenda, minutes and how often it meets"
        return NavigationLink { BoardView(key: key) } label: {
            CardRow(glyph: Glyph.achievements, title: "Board room", subtitle: sub, badge: waiting)
        }.buttonStyle(PressableStyle()).accessibilityIdentifier("group-board-room")
    }

    // MARK: Engine calls

    private func search(_ key: String, _ r: ManagerModel.SeatRole) {
        Haptics.tap()
        let found: [Person]? = store.act { $0.searchForSeat(key: key, role: r.id) } ?? nil
        searchRole = r.id
        if let found {
            candidates = found
            message = ""
        } else {
            candidates = []
            message = "Not enough cash for a search."
        }
    }

    private func seat(_ key: String, _ p: Person, _ fee: Double) {
        let r = store.act { $0.fillSeat(key: key, personID: p.id, monthlyFee: fee) }
        switch r {
        case .ok?: message = "\(p.name) joins the board."; candidates = []; searchRole = nil; Haptics.success()
        case .full?: message = "That seat is full."
        case .refused?: message = "\(p.name) wants more."
        case .votedDown(let n)?: message = "The owners voted \(p.name) down (\(n)% behind them)."
        default: message = "\(p.name) is not available."
        }
    }
}
