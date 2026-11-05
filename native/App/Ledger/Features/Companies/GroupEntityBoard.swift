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
    @State private var seatSheet: SeatRef?
    @State private var message = ""
    @State private var pending: PendingAction?

    private struct SeatRef: Identifiable, Hashable {
        var id: String
    }

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
        .centerSheet(item: $seatSheet) { (r: SeatRef) in SeatPickerSheet(key: key, role: r.id).environmentObject(store) }
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

    /// The person's portrait from the shared avatar (staff and managers alike); initials for a co-owner who is not a person record.
    @ViewBuilder private func personLead(_ id: Int?, _ name: String) -> some View {
        if let id, let p = engine.state.people[id] {
            ThumbnailView(kind: .person, key: p.role, size: 32, initials: name, face: p.faceKey)
        } else {
            avatar(initials(name))
        }
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
            line(first: false, lead: { personLead(v.personID, v.name) }, title: v.name, sub: v.title + (v.votes ? " \u{00B7} votes" : " \u{00B7} advises"), trail: {
                trailFor(v, seats: seats, key: key)
            })
        }
        ForEach(engine.seatRoles) { (r: ManagerModel.SeatRole) in
            let filled: Int = seats.filter { (s: ManagerModel.Seat) -> Bool in s.role == r.id }.count
            ForEach(0..<max(0, r.maxSeats - filled), id: \.self) { (_: Int) in
                emptySeat(r)
            }
        }
    }

    private func emptySeat(_ r: ManagerModel.SeatRole) -> some View {
        let id: String = r.id
        return Button { Haptics.tap(); seatSheet = SeatRef(id: id) } label: {
            line(first: false, lead: { plusRing() }, title: r.title, sub: r.text, trail: {
                Text("Appoint").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.gold)
                    .frame(minWidth: 64, minHeight: 36, alignment: .trailing)
            })
        }.buttonStyle(PressableStyle())
    }

    @ViewBuilder private func trailFor(_ v: ManagerModel.Voter, seats: [ManagerModel.Seat], key: String) -> some View {
        if let pid = v.personID, seats.contains(where: { (s: ManagerModel.Seat) -> Bool in s.id == pid }) {
            Button("Remove from board") { askToRemove(v, pid: pid, key: key) }
                .buttonStyle(TinyButtonStyle(tint: Theme.loss))
                .lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityIdentifier("board-remove-seat")
        } else {
            EmptyView()
        }
    }

    /// The question says what it means first: own staff keep their job; an outside holder is paid their notice; without a majority it is refused.
    private func askToRemove(_ v: ManagerModel.Voter, pid: Int, key: String) {
        let terms: SeatRemovalTerms = engine.seatRemovalTerms(key: key, personID: pid)
        if !terms.allowed {
            store.show(terms.reason, tone: "warn")
            return
        }
        let cost: String = terms.cost > 0 ? " Notice pay: \(store.short(terms.cost))." : ""
        let name: String = v.name
        pending = PendingAction(title: "Remove \(name) from the board?", message: terms.summary + cost, button: "Remove from board", destructive: true, alwaysAsk: true) {
            let result: SettingResult? = store.act { $0.removeSeatHolder(key: key, personID: pid) }
            _ = store.settle(result, "\(name) is off the board.")
        }
    }

    private func roomLink(_ key: String) -> some View {
        let waiting: Int = engine.boardOpenDecisions(key: key)
        let sub: String = waiting > 0 ? "\(waiting) \(waiting == 1 ? "point waits" : "points wait") for your decision" : "Agenda, minutes and how often it meets"
        return NavigationLink { BoardView(key: key) } label: {
            CardRow(glyph: Glyph.achievements, title: "Board room", subtitle: sub, badge: waiting)
        }.buttonStyle(PressableStyle()).accessibilityIdentifier("group-board-room")
    }
}

// MARK: - The popup for one empty seat

/// Who can take one empty board seat: the candidates of the last search for that role (a search costs a fee) with their yearly fee and an
/// Appoint button. The owners vote on a director; the result shows as a message.
struct SeatPickerSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var key: String
    var role: String
    @State private var refresh = 0

    var body: some View {
        let r: ManagerModel.SeatRole? = store.engine?.seatRoles.first { (x: ManagerModel.SeatRole) -> Bool in x.id == role }
        let cands: [Person] = (store.engine?.boardCandidates(key: key) ?? []).filter { (p: Person) -> Bool in p.str("adv13") == role }
        VStack(alignment: .leading, spacing: 8) {
            Text(r?.text ?? "").popupText(.caption).lineLimit(2)
            if cands.isEmpty {
                Text("Nobody lined up for this seat yet.").popupText(.caption)
            }
            ForEach(cands) { (p: Person) in
                candidateRow(p)
            }
            QuietButton(title: cands.isEmpty ? "Search for candidates" : "Search again", fullWidth: true) { search() }
        }
        .centerSheetTitle(r?.title ?? "Board seat")
        .id(refresh)
    }

    private func candidateRow(_ p: Person) -> some View {
        let fee: Double = p.num("fee13")
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name).popupText(.rowValue).lineLimit(1)
                Text("\(p.str("advBg")) \u{00B7} \(store.short(fee * 12)) a year").popupText(.caption).lineLimit(1)
            }
            Spacer(minLength: 6)
            Button("Appoint") { seat(p, fee) }.buttonStyle(TinyButtonStyle(tint: Theme.gold))
        }
        .padding(.vertical, 4)
    }

    private func search() {
        Haptics.tap()
        let k: String = key
        let r: String = role
        let found: [Person]? = store.act { $0.searchForSeat(key: k, role: r) } ?? nil
        if found == nil { store.show("Not enough cash for a search.", tone: "warn") }
        refresh += 1
    }

    private func seat(_ p: Person, _ fee: Double) {
        let k: String = key
        let pid: Int = p.id
        let name: String = p.name
        let res = store.act { $0.fillSeat(key: k, personID: pid, monthlyFee: fee) }
        switch res {
        case .ok?: store.show("\(name) joins the board.", tone: "good"); Haptics.success(); dismiss()
        case .full?: store.show("That seat is full.", tone: "warn")
        case .refused?: store.show("\(name) wants more.", tone: "warn")
        case .votedDown(let n)?: store.show("The owners voted \(name) down (\(n)% behind them).", tone: "warn")
        default: store.show("\(name) is not available.", tone: "warn")
        }
        refresh += 1
    }
}
