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
    /// Monthly pay (0 when the engine holds none).
    public var monthlyWage: Double = 0
    /// A manager, department head, chain, regional or group person (not store staff).
    public var isManagement: Bool = false
    /// Short note about the person ("8 items missing", "working notice"); "steady" when all is well.
    public var note: String = ""
    /// The note is something to act on (paperwork missing, sick, notice, worn out).
    public var needsAttention: Bool = false
    /// The person record, for the portrait; nil for post-holders known only by name.
    public var personID: Int? = nil
}

public extension GameEngine {
    /// Everyone who works for the player that a search can find: each live company's manager, department heads and staff, then the people above
    /// the companies (chain and regional managers, the group managing director, group office staff) with their employer. An empty query lists no one.
    func teamPeopleSearch(query: String) -> [TeamSearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return teamPeople().filter { $0.name.lowercased().contains(q) || $0.role.lowercased().contains(q) || $0.employer.lowercased().contains(q) }
    }

    /// Everyone who works for the player, one record each (the Team tab's People directory; `teamPeopleSearch` filters this same list).
    func teamPeople() -> [TeamSearchResult] {
        var all: [TeamSearchResult] = []
        for co in state.companies where co.status.isLive {
            if let mid = co.managerID, let p = state.people[mid] {
                let leaving = !co.value("mgrNotice").isNull
                all.append(.init(id: "m\(co.id)", name: p.name, role: tradeInfo(companyID: co.id).map { ManagerModel.title($0) } ?? "Manager", scope: "store", employer: co.name, companyID: co.id, chainID: nil,
                                 monthlyWage: co.managerMonthlyWage, isManagement: true, note: leaving ? "working notice" : "steady", needsAttention: leaving, personID: mid))
            }
            for slot in teamSlots(companyID: co.id) {
                if let pid = slot.personID, let p = state.people[pid] {
                    all.append(.init(id: "t\(co.id)-\(slot.id)", name: p.name, role: slot.title, scope: "company", employer: co.name, companyID: co.id, chainID: nil,
                                     monthlyWage: slot.monthlyWage, isManagement: true, note: "steady", personID: pid))
                }
            }
            for m in co.staff {
                let role = m.role.prefix(1).uppercased() + m.role.dropFirst()
                let missing = StaffExtras.missing(m).count
                var note = "steady"
                var attention = true
                if missing > 0 { note = "\(missing) item\(missing == 1 ? "" : "s") missing" }
                else if m.noticeWeeks > 0 { note = "working notice" }
                else if (m.sickUntilWeek ?? -1) >= state.week { note = "off sick" }
                else if m.tiredness > 75 { note = "worn out" }
                else { attention = false }
                all.append(.init(id: "s\(co.id)-\(m.id)", name: state.people[m.id]?.name ?? role, role: role, scope: "store", employer: co.name, companyID: co.id, chainID: nil,
                                 monthlyWage: m.monthlyWage, note: note, needsAttention: attention, personID: m.id))
            }
        }
        // People above and beside the companies: chain people, regional managers, the group managing director, group office staff. The company
        // posts in the overview are the same people as the managers and department heads listed above, so only these scopes are added.
        for m in teamOverview().members where ["chain", "region", "group"].contains(m.scope) {
            all.append(.init(id: "o-\(m.id)", name: m.name, role: m.role, scope: m.scope, employer: m.employer, companyID: m.companyID, chainID: m.chainID,
                             monthlyWage: m.monthlyWage, isManagement: true, note: "steady"))
        }
        return all
    }
}
