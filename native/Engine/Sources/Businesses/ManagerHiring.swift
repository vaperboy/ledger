import Foundation
import GameCore
import Countries

public enum ManagerHiring {
    public enum Verdict: Equatable, Sendable {
        case replace
        case early(String)
        case no(String)
        public var allowed: Bool { if case .no = self { return false }; return true }
    }

    static let endingSoonWeeks = 4
    public static let demandUtilisation = 0.75

    static func departure(_ s: GameState, _ m: StaffMember) -> String? {
        if m.noticeWeeks > 0 { return "has handed in notice" }
        if let end = FixedTerm.endWeek(m), end - s.week <= endingSoonWeeks { return "the fixed term ends" }
        return nil
    }

    static func heads(_ co: Company, role: String) -> [StaffMember] { co.staff.filter { $0.role == role && $0.value("seas").isNull } }

    public static func demandLimited(_ co: Company) -> Bool {
        let lw = co.value("lastW")
        guard !lw.isNull else { return false }
        return lw["util"].double >= demandUtilisation || (lw["cap"].double > 0 && lw["D"].double > lw["cap"].double * 0.85)
    }

    public static func verdict(_ s: GameState, companyID: Int, role: String, target: Int, data: GameData) -> Verdict {
        guard let co = s.company(companyID), co.status == .open else { return .no("The company is not open.") }
        guard Delegation.hasManager(co) || HierarchyHiring.staffBoss(s, co, data: data) != nil else { return .no("Without a manager nobody hires: the owner decides.") }
        if Appointments.classify(role) == .assistant { return .no(Appointments.authority(s, companyID: companyID, role: role, data: data).reason + " Use a proposal (Appointments.propose).") }
        if let why = Workplaces.hireBlock(co, role: role, data: data) { return .no(why) }
        let all = heads(co, role: role)
        let leaving = all.compactMap { m in departure(s, m).map { (m, $0) } }
        guard all.count - leaving.count < target else { return .no("The team for this role is complete.") }
        if all.count < target { return .replace }
        let first = leaving[0]
        return .early("\(s.people[first.0.id]?.name ?? "A colleague") \(first.1)")
    }

    @discardableResult
    static func fill(_ s: inout GameState, companyID: Int, role: String, target: Int, candidates given: [Person]? = nil, data: GameData) -> (person: Person, verdict: Verdict)? {
        let v = verdict(s, companyID: companyID, role: role, target: target, data: data)
        guard v.allowed, let ci = s.companyIndex(companyID), StaffingPlan.searchDone(s, s.companies[ci], role: role) else { return nil }
        let cands = given ?? Hiring.search(role: role, company: s.companies[ci], mode: .network, faces: false, state: &s, data: data)
        guard !cands.isEmpty else { return nil }
        let mgr = s.companies[ci].managerID.flatMap { s.people[$0] } ?? HierarchyHiring.staffBoss(s, s.companies[ci], data: data).flatMap { s.people[$0.personID] }
        guard let p = AutoHire.hireWorker(role: role, companyID: companyID, candidates: cands, hirer: AutoHire.hirer(person: mgr), state: &s, data: data) else { return nil }
        StaffingPlan.hired(&s, companyIndex: ci, role: role, data: data)
        return (p, v)
    }

    static func earlyNote(_ v: Verdict) -> String { if case .early(let t) = v { return " (early: \(t))" }; return "" }
}
