import Foundation
import GameCore
import Countries

/// The rule and the door for hiring on the owner's behalf: ONLY a hired manager (or, in a chain, the boss above a store with no manager) hires
/// for the company, and never into a full office. The headcount to hire towards is the staffing plan's (`StaffingPlan`); this decides whether one
/// more person of a role may be taken now and does the hire, through `AutoHire` and so through `Hiring.hire`.
/// A person on notice (or whose fixed term is about to end) no longer counts towards the headcount, so the replacement is sought while they are still working.
public enum ManagerHiring {
    public enum Verdict: Equatable, Sendable {
        /// The post is empty: fill it.
        case replace
        /// Someone is on their way out and the post is covered until they go: hire the replacement now. The text says who and why.
        case early(String)
        /// No hire, and why (for the owner's messages and the tests).
        case no(String)
        public var allowed: Bool { if case .no = self { return false }; return true }
    }

    /// Weeks before a fixed term ends from which the person counts as leaving.
    static let endingSoonWeeks = 4
    /// Utilisation from which the company has the work for one more person.
    public static let demandUtilisation = 0.75

    /// Why this team member is about to leave, nil if they are not.
    static func departure(_ s: GameState, _ m: StaffMember) -> String? {
        if m.noticeWeeks > 0 { return "has handed in notice" }
        if let end = FixedTerm.endWeek(m), end - s.week <= endingSoonWeeks { return "the fixed term ends" }
        return nil
    }

    /// The permanent people in a role (seasonal crews are counted by the plan's seasonal row).
    static func heads(_ co: Company, role: String) -> [StaffMember] { co.staff.filter { $0.role == role && $0.value("seas").isNull } }

    /// The company has the work for one more person: it is using nearly all it can do, or demand is above what it can serve.
    public static func demandLimited(_ co: Company) -> Bool {
        let lw = co.value("lastW")
        guard !lw.isNull else { return false }
        return lw["util"].double >= demandUtilisation || (lw["cap"].double > 0 && lw["D"].double > lw["cap"].double * 0.85)
    }

    /// May the manager hire one more `role` now, with `target` the number of them the team calls for?
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

    /// The one door for a manager's hire: checks the rule and the plan's timing, weighs the candidates with the manager's skill, hires, and pays the
    /// recruiting fee. Nil when the rule says no, the search has not run long enough, or nobody came to terms.
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

    /// What the owner sees in the notes when the hire was early.
    static func earlyNote(_ v: Verdict) -> String { if case .early(let t) = v { return " (early: \(t))" }; return "" }
}
