import Foundation
import GameCore
import Countries
import Finance

public struct GrowthPath: Equatable, Sendable {
    public var companyID: Int
    public var employeeID: Int
    public var currentRole: String
    public var currentRoleName: String
    public var nextRole: String?
    public var nextRoleName: String
    public var readiness: Double
    public var missing: [String]
    public var yearsToReady: Double
    public var suggestedTrainingID: String?
    public var suggestedTraining: String?
    public var isSuccessor: Bool
    public var isReady: Bool { missing.isEmpty && nextRole != nil }
}

public enum PromoteResult: Equatable, Sendable {
    case promoted(String)
    case notReady([String])
    case blocked(String)
}

public enum GrowthPaths {
    public static let requirements: [String: (years: Double, skill: Double, courses: Int)] = ["role": (1, 50, 0), "assistant": (2, 60, 1), "manager": (3, 68, 2)]
    public static let skillPerYear = 5.0
    public static let courseYears = 0.25

    static func rungKey(_ nextRole: String) -> String { nextRole == "assistant" || nextRole == "manager" ? nextRole : "role" }

    static func member(_ co: Company, _ id: Int) -> (role: String, wage: Double, hired: Int, isAssistant: Bool)? {
        if let m = co.staff.first(where: { $0.id == id }) { return (m.role, m.monthlyWage, m.hiredWeek, false) }
        let a = co.value("asst")
        if a["npc"].int == id && id != 0 { return ("assistant", a["wage"].double, a["w0"].int, true) }
        return nil
    }

    public static func growthPath(_ s: GameState, companyID: Int, employeeID: Int, data: GameData) -> GrowthPath? {
        guard let co = s.company(companyID), let n = s.people[employeeID] else { return nil }
        let t = data.catalog.tables
        func roleName(_ r: String) -> String { r == "assistant" ? "Assistant manager" : r == "manager" ? "Manager" : (t.roles[r]?.name ?? r) }
        let isSucc = co.value("succ")["id"].int == employeeID && employeeID != 0
        if co.managerID == employeeID {
            return GrowthPath(companyID: companyID, employeeID: employeeID, currentRole: "manager", currentRoleName: "Manager", nextRole: nil, nextRoleName: "", readiness: 1,
                              missing: [], yearsToReady: 0, suggestedTrainingID: nil, suggestedTraining: nil, isSuccessor: false)
        }
        guard let me = member(co, employeeID) else { return nil }
        var next: String
        if me.isAssistant { next = "manager" }
        else if let post = ManagerModel.promotionPosts(s, companyID: companyID, personID: employeeID, data: data).filter({ $0.kind == "role" }).min(by: { $0.ask < $1.ask }) { next = String(post.id.dropFirst(5)) }
        else if co.value("asst")["npc"].int == 0 { next = "assistant" }
        else { next = "manager" }
        let req = requirements[rungKey(next)]!
        let m = co.staff.first { $0.id == employeeID }
        let years = Double(max(0, s.week - me.hired)) / 52
        let skill: Double = m.map { ManagerModel.skillOf(s, $0, n, data: data) } ?? (n.skill.isZero ? 55 : n.skill)
        let courses = m?.int("crsN") ?? n.int("crsN")
        var missing: [String] = []
        var yearsNeeded = 0.0
        if years < req.years {
            let d = req.years - years
            missing.append("\(d >= 1 ? String(format: "%.1f", d) : String(format: "%.1f", d)) more years with the company"); yearsNeeded = max(yearsNeeded, d)
        }
        if skill < req.skill { let d = (req.skill - skill) / skillPerYear; missing.append("skill \(Int(skill)) of \(Int(req.skill)) needed"); yearsNeeded = max(yearsNeeded, d) }
        if courses < req.courses { let d = Double(req.courses - courses) * courseYears; missing.append("\(req.courses - courses) more course\(req.courses - courses == 1 ? "" : "s")"); yearsNeeded = max(yearsNeeded, d) }
        var calm = 1.0
        if let m = m {
            if StaffPromises.letDown(m, week: s.week) { calm = 0; missing.append("a promise to them was broken") }
            else if let mood = StaffProfile.mood(s, companyID: companyID, staffID: employeeID, data: data), mood.word == "Unhappy" || mood.word == "Leaving" { calm = 0; missing.append("they are unhappy in the job") }
        }
        let readiness = 0.35 * min(1, years / req.years) + 0.35 * min(1, skill / req.skill) + 0.2 * (req.courses == 0 ? 1 : min(1, Double(courses) / Double(req.courses))) + 0.1 * calm
        var tid: String?, tname: String?
        if courses < req.courses || skill < req.skill, let c = StaffProfile.courses(co, data: data).max(by: { $0.maxGain < $1.maxGain }) { tid = c.id; tname = c.name }
        return GrowthPath(companyID: companyID, employeeID: employeeID, currentRole: me.role, currentRoleName: roleName(me.role), nextRole: next, nextRoleName: roleName(next),
                          readiness: min(1, max(0, missing.isEmpty ? 1 : min(readiness, 0.99))), missing: missing, yearsToReady: missing.isEmpty ? 0 : yearsNeeded, suggestedTrainingID: tid, suggestedTraining: tname, isSuccessor: isSucc)
    }

    @discardableResult
    public static func promote(_ s: inout GameState, companyID: Int, employeeID: Int, data: GameData) -> PromoteResult {
        guard let ci = s.companyIndex(companyID), let path = growthPath(s, companyID: companyID, employeeID: employeeID, data: data), let next = path.nextRole else { return .blocked("There is nothing to promote them to.") }
        guard path.isReady else { return .notReady(path.missing) }
        let co = s.companies[ci]
        guard let cand = ManagerModel.candidate(s, companyID: companyID, personID: employeeID, data: data) else { return .blocked("They do not work here.") }
        let first = ManagerModel.firstName(cand.n.name)
        switch next {
        case "assistant":
            guard co.value("asst")["npc"].int == 0, let k = co.staff.firstIndex(where: { $0.id == employeeID }) else { return .blocked("The company already has an assistant manager.") }
            var n = cand.n
            let wage = World(state: s, data: data).currency(co).roundedStep(max(cand.pay * 1.15, ManagerModel.assistantGoingRate(company: co, state: s, data: data) * 0.9), about: 500)
            var staff = co.staff; staff.remove(at: k); s.companies[ci].staff = staff
            n.set("asst", true); n.set("promoW", s.week); s.people[n.id] = n
            s.companies[ci].set("asst", .object(["npc": .number(Double(n.id)), "wage": .number(wage), "duties": .array([]), "w0": .number(Double(s.week))]))
            s.note("\(first) is now assistant manager of \(co.name).", tone: "good", companyID: companyID)
            StaffPromises.noticeChange(&s, companyID: companyID)
            return .promoted("\(first) is now assistant manager at \(co.name).")
        case "manager":
            if co.managerID != nil { return .blocked("\(co.name) has a manager. Name \(first) as successor to take over when the manager leaves.") }
            guard let post = ManagerModel.promotionPosts(s, companyID: companyID, personID: employeeID, data: data).first(where: { $0.id == "mgr@\(companyID)" }) else { return .blocked("They cannot manage this company.") }
            if co.value("asst")["npc"].int == employeeID { s.companies[ci].set("asst", .null) }
            let msg = ManagerModel.applyPromotion(&s, cand, post: post, wage: post.ask, terms: ManagerModel.PromotionTerms(), data: data)
            return .promoted(msg)
        default:
            guard let post = ManagerModel.promotionPosts(s, companyID: companyID, personID: employeeID, data: data).first(where: { $0.id == "role:\(next)" }) else { return .blocked("That post is not open.") }
            let msg = ManagerModel.applyPromotion(&s, cand, post: post, wage: post.ask, terms: ManagerModel.PromotionTerms(), data: data)
            if let ci2 = s.companyIndex(companyID), let k = s.companies[ci2].staff.firstIndex(where: { $0.id == employeeID }) {
                var staff = s.companies[ci2].staff
                staff[k].happyUntilWeek = max(staff[k].happyUntilWeek, s.week + 52)
                s.companies[ci2].staff = staff
            }
            return .promoted(msg)
        }
    }

    @discardableResult
    public static func setSuccessor(_ s: inout GameState, companyID: Int, employeeID: Int, successorID: Int?) -> Bool {
        guard let ci = s.companyIndex(companyID), s.companies[ci].managerID == employeeID, employeeID != 0 else { return false }
        guard let sid = successorID else { s.companies[ci].set("succ", .null); return true }
        guard sid != employeeID, member(s.companies[ci], sid) != nil, s.companies[ci].staff.first(where: { $0.id == sid })?.noticeWeeks ?? 0 <= 0 else { return false }
        s.companies[ci].set("succ", .object(["mgr": .number(Double(employeeID)), "id": .number(Double(sid)), "w": .number(Double(s.week))]))
        return true
    }

    public static func successor(_ s: GameState, companyID: Int) -> Int? {
        guard let co = s.company(companyID), co.value("succ")["id"].int != 0 else { return nil }
        return co.value("succ")["id"].int
    }

    @discardableResult
    static func installSuccessor(_ s: inout GameState, companyID: Int, data: GameData) -> Bool {
        guard let ci = s.companyIndex(companyID), s.companies[ci].managerID == nil, s.companies[ci].status == .open else { return false }
        let rec = s.companies[ci].value("succ")
        guard !rec.isNull else { return false }
        s.companies[ci].set("succ", .null)
        let co = s.companies[ci], sid = rec["id"].int
        guard var n = s.people[sid], let me = member(co, sid) else {
            s.note("The successor named for \(co.name) is no longer with the company.", tone: "bad", companyID: companyID)
            return false
        }
        if me.isAssistant { s.companies[ci].set("asst", .null) }
        else { s.companies[ci].staff = co.staff.filter { $0.id != sid } }
        let first = ManagerModel.firstName(n.name)
        if n.value("stats").isNull { ManagerModel.ensureStats(&n, role: me.role) }
        n.role = "manager"
        s.people[sid] = n
        let cur = World(state: s, data: data).currency(co)
        let wage = cur.roundedStep(max(me.wage * 1.2, ManagerModel.managerGoingRate(company: co, state: s, data: data) * 0.8), about: 500)
        ManagerModel.appoint(&s, companyIndex: ci, person: n, wage: wage, data: data)
        s.companies[ci].set("mood", 62)
        s.addMessage(kind: "info", from: n.name, title: "\(n.name) takes over \(co.name)",
                     body: "As planned, \(first) steps up from \(roleLabel(me.role, data)) to manager of \(co.name) on \(cur.display(wage)) a month. Expect a few weeks of settling in; the post they leave will be filled by the manager if the team needs it.",
                     companyID: companyID, tone: "good", status: "done")
        StaffPromises.noticeChange(&s, companyID: companyID)
        return true
    }

    static func roleLabel(_ role: String, _ data: GameData) -> String { role == "assistant" ? "assistant manager" : (data.catalog.tables.roles[role]?.name ?? role).lowercased() }
}
