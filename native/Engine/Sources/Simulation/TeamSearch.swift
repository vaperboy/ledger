import Foundation
import GameCore
import Businesses

public struct TeamSearchResult: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var role: String
    public var scope: String
    public var employer: String
    public var companyID: Int?
    public var chainID: Int?
    public var monthlyWage: Double = 0
    public var isManagement: Bool = false
    public var note: String = ""
    public var needsAttention: Bool = false
    public var personID: Int? = nil
}

public extension GameEngine {
    func teamPeopleSearch(query: String) -> [TeamSearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return teamPeople().filter { $0.name.lowercased().contains(q) || $0.role.lowercased().contains(q) || $0.employer.lowercased().contains(q) }
    }

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
                var note = "steady"
                var attention = true
                if m.noticeWeeks > 0 { note = "working notice" }
                else if (m.sickUntilWeek ?? -1) >= state.week { note = "off sick" }
                else if m.tiredness > 75 { note = "worn out" }
                else { attention = false }
                all.append(.init(id: "s\(co.id)-\(m.id)", name: state.people[m.id]?.name ?? role, role: role, scope: "store", employer: co.name, companyID: co.id, chainID: nil,
                                 monthlyWage: m.monthlyWage, note: note, needsAttention: attention, personID: m.id))
            }
        }
        for m in teamOverview().members where ["chain", "region", "group"].contains(m.scope) {
            all.append(.init(id: "o-\(m.id)", name: m.name, role: m.role, scope: m.scope, employer: m.employer, companyID: m.companyID, chainID: m.chainID,
                             monthlyWage: m.monthlyWage, isManagement: true, note: "steady", personID: m.personID))
        }
        return all
    }
}
