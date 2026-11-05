import Foundation
import GameCore
import Countries

/// Who may appoint whom.
/// The owner appoints the general manager, unless a CEO or managing director exists: then the CEO appoints. A general manager hires ordinary staff
/// alone, but may NOT hire an assistant (deputy) manager without the confirmation of the level above: the CEO, or the owner when there is none.
/// The manager's hire is therefore a proposal message ("asst", a decision for that level); the assistant exists only after it is confirmed.
public struct AppointmentAuthority: Equatable, Sendable {
    /// The rank that takes the decision (for an assistant: the manager who chose the person).
    public var decidedBy: Delegation.Rank
    /// The rank that must confirm, nil when the decider can act alone.
    public var needsConfirmationFrom: Delegation.Rank?
    public var reason: String
}

public enum Appointments {
    public static let kind = "asst"

    enum RoleClass { case manager, assistant, staff }
    static func classify(_ role: String) -> RoleClass {
        let r = role.lowercased()
        if r.contains("assistant") || r.contains("deputy") || r == "asst" { return .assistant }
        if r.contains("manager") || r == "mgr" || r == "gm" || r.contains("director") { return .manager }
        return .staff
    }

    public static func authority(_ s: GameState, companyID: Int, role: String, data: GameData) -> AppointmentAuthority {
        guard let co = s.company(companyID) else { return AppointmentAuthority(decidedBy: .owner, needsConfirmationFrom: nil, reason: "The owner decides.") }
        let top = Delegation.topRank(s, co, data: data)
        let hasCEO = top.rawValue >= Delegation.Rank.ceo.rawValue && top != .owner
        switch classify(role) {
        case .manager:
            return hasCEO ? AppointmentAuthority(decidedBy: .ceo, needsConfirmationFrom: nil, reason: "The CEO appoints the general manager.")
                          : AppointmentAuthority(decidedBy: .owner, needsConfirmationFrom: nil, reason: "The owner appoints the general manager when there is no CEO or managing director.")
        case .assistant:
            let above: Delegation.Rank = hasCEO ? .ceo : .owner
            return AppointmentAuthority(decidedBy: Delegation.hasManager(co) ? .manager : .owner,
                                        needsConfirmationFrom: Delegation.hasManager(co) ? above : nil,
                                        reason: Delegation.hasManager(co)
                                            ? "A general manager cannot hire an assistant manager alone: \(above == .ceo ? "the CEO" : "the owner") confirms."
                                            : "Without a manager the owner hires the assistant manager.")
        case .staff:
            return Delegation.hasManager(co) ? AppointmentAuthority(decidedBy: .manager, needsConfirmationFrom: nil, reason: "The manager hires ordinary staff.")
                                             : AppointmentAuthority(decidedBy: .owner, needsConfirmationFrom: nil, reason: "Without a manager the owner hires.")
        }
    }

    /// The manager has chosen an assistant: post the proposal to the level above (the CEO, else the owner). Nothing is created until it is confirmed.
    /// False when there is no manager, the company already has an assistant, the person is not free, or a proposal is already open.
    @discardableResult
    public static func propose(_ s: inout GameState, companyID: Int, personID: Int, monthlyWage w: Double, data: GameData) -> Bool {
        guard let ci = s.companyIndex(companyID), let mid = s.companies[ci].managerID, let mgr = s.people[mid], let p = s.people[personID], p.employerID == 0,
              s.companies[ci].value("asst")["npc"].int == 0,
              !s.inbox.contains(where: { $0.companyID == companyID && $0.status == "open" && $0.actionID == kind }) else { return false }
        let auth = authority(s, companyID: companyID, role: "assistant manager", data: data)
        guard let above = auth.needsConfirmationFrom else { return false }
        let co = s.companies[ci]
        let cur = World(state: s, data: data).currency(co)
        s.addMessage(kind: "ask", from: mgr.name, title: "Hire \(p.name) as assistant manager of \(co.name)?",
                     body: "\(mgr.name) wants \(p.name) as assistant manager at \(cur.display(w)) a month. A manager cannot make this hire alone: it needs the confirmation of \(above == .ceo ? "the CEO" : "the owner").",
                     companyID: companyID, tone: "n", status: "open",
                     options: [.option("Confirm the hire", "\(cur.display(w)) a month."), .option("Decline", "No assistant for now.")],
                     action: kind, data: .object(["t": .string(kind), "kind": .string(kind), "co": .number(Double(companyID)), "npc": .number(Double(personID)),
                                                  "wage": .number(w), "lvl": .number(Double(above.rawValue))]), expiresWeek: s.week + 3)
        return true
    }

    /// The answer: option 0 confirms and the assistant is installed; anything else declines.
    public static func answer(_ s: inout GameState, message m: Message, option idx: Int) {
        let d = m.value("data")
        guard idx == 0, let ci = s.companyIndex(d["co"].int), s.companies[ci].status == .open, s.companies[ci].value("asst")["npc"].int == 0,
              var n = s.people[d["npc"].int], n.employerID == 0 else { return }
        n.employerID = s.companies[ci].id
        n.set("asst", true)
        s.people[n.id] = n
        s.companies[ci].set("asst", .object(["npc": .number(Double(n.id)), "wage": .number(d["wage"].double), "duties": .array([]), "w0": .number(Double(s.week))]))
        s.note("\(n.name) is now assistant manager of \(s.companies[ci].name).", tone: "good", companyID: s.companies[ci].id)
    }
}
