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
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if !message.isEmpty { NoteCard(text: message) }
            if active { roomLink(key) }
            LedgerSection("Board seats", rule: false) {
                VStack(spacing: 0) {
                    ownerRow
                    if active { seatRows(key) }
                }
            }
            if !active {
                Text("Nobody else owns part of this company, so there are no seats to fill and no binding votes. A full board forms once you register a chain or a co-owner joins; until then your managers advise and you decide.")
                    .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
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
        Text(text).textStyle(.caption, tint: Theme.accent, weight: .medium)
            .frame(width: 32, height: 32)
            .background(Circle().fill(Theme.surface))
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
        Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkFaint)
            .frame(width: 32, height: 32)
            .overlay(Circle().strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }

    private func line<Lead: View, Trail: View>(first: Bool, @ViewBuilder lead: () -> Lead, title: String, sub: String, chip: String = "", @ViewBuilder trail: () -> Trail) -> some View {
        HStack(spacing: Theme.Space.m) {
            lead()
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title).textStyle(.headline).lineLimit(1)
                if !sub.isEmpty { Text(sub).textStyle(.caption, tint: Theme.inkFaint).lineLimit(2) }
            }
            if !chip.isEmpty { Chip(text: chip, tint: Theme.inkSoft) }
            Spacer(minLength: Theme.Space.s)
            trail()
        }
        .padding(.vertical, Theme.Space.s)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .overlay(alignment: .top) { if !first { Hairline() } }
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
                Text("Appoint").textStyle(.body, tint: Theme.accent, weight: .medium)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
            })
        }.buttonStyle(PressableStyle())
    }

    @ViewBuilder private func trailFor(_ v: ManagerModel.Voter, seats: [ManagerModel.Seat], key: String) -> some View {
        if let pid = v.personID, seats.contains(where: { (s: ManagerModel.Seat) -> Bool in s.id == pid }) {
            Button("Remove") { askToRemove(v, pid: pid, key: key) }
                .buttonStyle(TertiaryButtonStyle(size: .compact, tint: Theme.loss))
                .accessibilityLabel("Remove \(v.name) from the board")
                .lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityIdentifier("board-remove-seat")
        } else {
            EmptyView()
        }
    }

    private func askToRemove(_ v: ManagerModel.Voter, pid: Int, key: String) {
        if let ask = store.removeSeatPrompt(key: key, personID: pid, name: v.name) { pending = ask }
    }

    private func roomLink(_ key: String) -> some View {
        let waiting: Int = engine.boardOpenDecisions(key: key)
        let sub: String = waiting > 0 ? "\(waiting) \(waiting == 1 ? "point waits" : "points wait") for your decision" : "Agenda, minutes and how often it meets"
        return NavigationLink { BoardView(key: key) } label: {
            LedgerRow(leading: .glyph(Glyph.achievements), title: "Board room", subtitle: sub, badge: waiting, chevron: true)
                .overlay(alignment: .top) { Hairline() }
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
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(r?.text ?? "").popupText(.caption).lineLimit(2)
            if cands.isEmpty {
                EmptyState(glyph: Glyph.person, title: "Nobody lined up for this seat yet", message: "A search finds candidates; it costs a fee.", centered: false)
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
        return HStack(spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name).popupText(.rowValue).lineLimit(1)
                Text("\(p.str("advBg")) \u{00B7} \(store.short(fee * 12)) a year").popupText(.caption).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            Button("Appoint") { seat(p, fee) }.buttonStyle(TinyButtonStyle(tint: Theme.gold))
        }
        .padding(.vertical, Theme.Space.xs)
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
        let r = store.fillSeatOutcome(key: key, person: p, fee: fee)
        store.show(r.text, tone: r.joined ? "good" : "warn")
        if r.joined { Haptics.success(); dismiss() }
        refresh += 1
    }
}
