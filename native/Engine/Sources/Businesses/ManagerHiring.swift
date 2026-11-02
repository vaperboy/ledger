import Foundation
import GameCore
import Countries

/// THE rule for hiring on the owner's behalf (owner decision, 3 Nov): ONLY a hired manager hires for the company. Without a manager nobody is
/// hired automatically (the owner gets the usual messages). A manager never overfills: a hire needs a free place (`Workplaces`) and a headcount
/// the company's team calls for. A manager may hire EARLY, before the leaver actually goes, only when someone is on their way out (notice,
/// retirement, a fixed term ending, burnout or a low mood) AND the company has the demand for the role (`demandLimited`).
/// Every automatic hirer that works for a running company goes through `hire`: `AutoStaff`, `ManagerModel.keepTeam` and the manager's "hire" proposal.
public enum ManagerHiring {
    public enum Verdict: Equatable, Sendable {
        /// The post is empty: fill it.
        case replace
        /// Someone is on their way out and the work is there: hire before they go. The text says who and why.
        case early(String)
        /// No hire, and why (for the owner's messages and the tests).
        case no(String)
        public var allowed: Bool { if case .no = self { return false }; return true }
    }

    /// Weeks ahead in which an ending fixed term or a retirement counts as "on the way out".
    public static let horizonWeeks = 13
    /// Tiredness from which someone is flagged as burning out.
    public static let burnoutTiredness = 60.0
    /// Utilisation from which the company has the work for one more person (the same bar the manager's own hire proposal uses).
    public static let demandUtilisation = 0.75

    /// Why this team member is on their way out, nil if they are not.
    public static func leaverReason(_ s: GameState, _ co: Company, _ m: StaffMember, data: GameData) -> String? {
        if m.noticeWeeks > 0 { return "has handed in notice" }
        if let end = FixedTerm.endWeek(m), end - s.week <= horizonWeeks { return "the fixed term ends" }
        if let n = s.people[m.id], Double(n.age) + Double(s.week - m.hiredWeek) / 52 >= 67 - Double(horizonWeeks) / 52 { return "is about to retire" }
        if m.tiredness >= burnoutTiredness { return "is burning out" }
        if let mood = StaffProfile.mood(s, companyID: co.id, staffID: m.id, data: data), mood.word == "Leaving" || (mood.word == "Unhappy" && mood.bad.count >= 3) { return "is unhappy and may leave" }
        return nil
    }

    /// The company has the work for one more person: it is using nearly all it can do, or demand is above what it can serve.
    public static func demandLimited(_ co: Company) -> Bool {
        let lw = co.value("lastW")
        guard !lw.isNull else { return false }
        return lw["util"].double >= demandUtilisation || (lw["cap"].double > 0 && lw["D"].double > lw["cap"].double * 0.85)
    }

    /// May the manager hire one more `role` now, with `target` the number of them the team calls for?
    public static func verdict(_ s: GameState, companyID: Int, role: String, target: Int, data: GameData) -> Verdict {
        guard let co = s.company(companyID), co.status == .open else { return .no("The company is not open.") }
        guard Delegation.hasManager(co) else { return .no("Without a manager nobody hires: the owner decides.") }
        if let why = Workplaces.hireBlock(co, data: data) { return .no(why) }
        let heads = co.staff.filter { $0.role == role && !$0.flag("seas") }
        if heads.count < target { return .replace }
        let leavers = heads.compactMap { m in leaverReason(s, co, m, data: data).map { (m, $0) } }
        guard let first = leavers.first else { return .no("The team for this role is complete.") }
        guard heads.count - leavers.count < target, heads.count < target + 1 else { return .no("The team for this role is complete without the leavers.") }
        guard demandLimited(co) else { return .no("There is not enough work to hire before \(s.people[first.0.id]?.name ?? "the leaver") goes.") }
        return .early("\(s.people[first.0.id]?.name ?? "A colleague") \(first.1)")
    }

    /// The one door for a manager's hire: checks the rule, weighs the candidates with the manager's skill, hires. Nil when the rule says no or nobody came to terms.
    @discardableResult
    static func fill(_ s: inout GameState, companyID: Int, role: String, target: Int, candidates given: [Person]? = nil, data: GameData) -> (person: Person, verdict: Verdict)? {
        let v = verdict(s, companyID: companyID, role: role, target: target, data: data)
        guard v.allowed, let ci = s.companyIndex(companyID) else { return nil }
        let cands = given ?? Hiring.search(role: role, company: s.companies[ci], mode: .network, faces: false, state: &s, data: data)
        guard !cands.isEmpty else { return nil }
        let mgr = s.companies[ci].managerID.flatMap { s.people[$0] }
        guard let p = AutoHire.hireWorker(role: role, companyID: companyID, candidates: cands, hirer: AutoHire.hirer(person: mgr), state: &s, data: data) else { return nil }
        return (p, v)
    }

    /// What the owner sees in the notes when the hire was early.
    static func earlyNote(_ v: Verdict) -> String { if case .early(let t) = v { return " (early: \(t))" }; return "" }
}
