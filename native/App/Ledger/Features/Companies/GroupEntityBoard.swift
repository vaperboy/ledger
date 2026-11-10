import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

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

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return String(parts).uppercased()
    }

    private func avatar(_ text: String) -> some View {
        Text(text).textStyle(.caption, tint: Theme.accent, weight: .medium)
            .frame(width: 32, height: 32)
            .background(Circle().fill(Theme.surface))
    }

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

    private var ownerWorksHere: Bool {
        ManagerModel.boardCompanies(engine.state, key: key).contains { (c: Company) -> Bool in c.status.isLive && c.managerID == nil && c.ownerHours > 0 }
    }

    private func ownerRow() -> some View {
        let name: String = engine.state.player.name
        let others: Double = engine.boardVoters(key: key).filter { (v: ManagerModel.Voter) -> Bool in v.type == "owner" }.reduce(0) { (a: Double, v: ManagerModel.Voter) -> Double in a + v.percent }
        let mine: Int = Int(saturating: max(0, min(100, 100 - others)).rounded())
        return line(first: true, lead: { PlayerAvatar(name: name, isYou: true, size: 32) }, title: name, sub: "Owner \u{00B7} \(mine)%", chip: ownerWorksHere ? "Works here" : "")
    }
}
