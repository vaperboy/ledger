import Foundation
import GameCore
import Businesses

/// One person found by the Team tab's search box: who, in what job, and who employs them. Read-only.
public struct TeamSearchResult: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var role: String
    /// store, company, chain, region or group (the badge the Team lists use).
    public var scope: String
    /// The entity that employs them: the company, the chain, the holding, or the group office.
    public var employer: String
    /// The company a tap opens; nil for people who belong to no single company (group office, regional managers).
    public var companyID: Int?
    public var chainID: Int?
}

public extension GameEngine {
    /// Everyone who works for the player that a search can find: each live company's manager, department heads and staff, then the people above
    /// the companies (chain and regional managers, the group managing director, group office staff) with their employer. An empty query lists no one.
    func teamPeopleSearch(query: String) -> [TeamSearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var all: [TeamSearchResult] = []
        for co in state.companies where co.status.isLive {
            if let mid = co.managerID, let p = state.people[mid] {
                all.append(.init(id: "m\(co.id)", name: p.name, role: tradeInfo(companyID: co.id).map { ManagerModel.title($0) } ?? "Manager", scope: "store", employer: co.name, companyID: co.id, chainID: nil))
            }
            for slot in teamSlots(companyID: co.id) {
                if let pid = slot.personID, let p = state.people[pid] {
                    all.append(.init(id: "t\(co.id)-\(slot.id)", name: p.name, role: slot.title, scope: "company", employer: co.name, companyID: co.id, chainID: nil))
                }
            }
            for m in co.staff {
                let role = m.role.prefix(1).uppercased() + m.role.dropFirst()
                all.append(.init(id: "s\(co.id)-\(m.id)", name: state.people[m.id]?.name ?? role, role: role, scope: "store", employer: co.name, companyID: co.id, chainID: nil))
            }
        }
        // People above and beside the companies: chain people, regional managers, the group managing director, group office staff. The company
        // posts in the overview are the same people as the managers and department heads listed above, so only these scopes are added.
        for m in teamOverview().members where ["chain", "region", "group"].contains(m.scope) {
            all.append(.init(id: "o-\(m.id)", name: m.name, role: m.role, scope: m.scope, employer: m.employer, companyID: m.companyID, chainID: m.chainID))
        }
        return all.filter { $0.name.lowercased().contains(q) || $0.role.lowercased().contains(q) || $0.employer.lowercased().contains(q) }
    }
}
