import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Who sits on a board, as thin rows: you first (with a "Works here" chip where you run the company yourself), then the co-owners, the
/// CEO, the department heads and the managers who attend. The table is fixed by the game: nobody is hired onto it or paid for sitting.
struct BoardTable: View {
    var engine: GameEngine
    var key: String

    var body: some View {
        let active: Bool = engine.boardIsActive(key: key)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            LedgerSection("Who sits on it", rule: false) {
                VStack(spacing: 0) {
                    ownerRow()
                    ForEach(engine.boardVoters(key: key)) { (v: ManagerModel.Voter) in
                        line(first: false, lead: { personLead(v.personID, v.name) }, title: v.name, sub: v.title + (v.votes ? " \u{00B7} votes" : " \u{00B7} advises"))
                    }
                }
            }
            Text(active ? "Co-owners vote by their shares; the rest advise." : "You decide alone. The board advises.")
                .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
        }
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

    private func line<Lead: View>(first: Bool, @ViewBuilder lead: () -> Lead, title: String, sub: String, chip: String = "") -> some View {
        HStack(spacing: Theme.Space.m) {
            lead()
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title).textStyle(.headline).lineLimit(1)
                if !sub.isEmpty { Text(sub).textStyle(.caption, tint: Theme.inkFaint).lineLimit(2) }
            }
            if !chip.isEmpty { Chip(text: chip, tint: Theme.inkSoft) }
            Spacer(minLength: Theme.Space.s)
        }
        .padding(.vertical, Theme.Space.s)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .overlay(alignment: .top) { if !first { Hairline() } }
    }

    /// True when you run one of the board's companies yourself (no manager, hours above zero).
    private var ownerWorksHere: Bool {
        ManagerModel.boardCompanies(engine.state, key: key).contains { (c: Company) -> Bool in c.status.isLive && c.type != "hold" && c.managerID == nil && c.ownerHours > 0 }
    }

    /// You, with your share of the owners: what the co-owners hold leaves the rest to you.
    private func ownerRow() -> some View {
        let name: String = engine.state.player.name
        let others: Double = engine.boardVoters(key: key).filter { (v: ManagerModel.Voter) -> Bool in v.type == "owner" }.reduce(0) { (a: Double, v: ManagerModel.Voter) -> Double in a + v.percent }
        let mine: Int = Int(saturating: max(0, min(100, 100 - others)).rounded())
        return line(first: true, lead: { avatar(initials(name)) }, title: name, sub: "Owner \u{00B7} \(mine)%", chip: ownerWorksHere ? "Works here" : "")
    }
}
