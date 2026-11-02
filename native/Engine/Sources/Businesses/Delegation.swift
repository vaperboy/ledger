import Foundation
import GameCore
import Finance

/// (The old policy switches stay in the save as a hidden master off-switch for tests; the player no longer sees them.)
/// What the player's people do without asking (owner decision, 2 Nov: there is no "How much I decide" setting any more). It follows who is hired:
/// an accountant or a manager approves routine payroll, a manager replaces people who leave, staff answer routine complaints, and the amount a
/// manager may spend without asking grows with the owner's net worth. Without a manager everything comes to the owner.
public enum Delegation {
    /// The ranks that can take a decision, lowest first. A decision has a level (1 to 5); the lowest rank present at or above it takes it,
    /// and only a decision above the highest rank present reaches the owner (level 5).
    public enum Rank: Int, Sendable, CaseIterable {
        case assistantManager = 1, manager, director, ceo, owner
        public var title: String {
            switch self {
            case .assistantManager: return "Assistant manager"
            case .manager: return "Manager"
            case .director: return "Director"
            case .ceo: return "CEO"
            case .owner: return "You"
            }
        }
    }

    public static func hasAccountant(_ co: Company) -> Bool { !co.value("acc").isNull }
    public static func hasManager(_ co: Company) -> Bool { co.managerID != nil }

    /// Routine payroll is approved by itself when an accountant or a manager is there to do it; otherwise the owner gets a reminder.
    public static func autoPayroll(_ s: GameState, _ co: Company) -> Bool { s.policy.autoPayroll && (hasAccountant(co) || hasManager(co)) }
    /// A hired manager replaces people who leave.
    public static func autoRehire(_ s: GameState, _ co: Company) -> Bool { s.policy.autoRehire && hasManager(co) }
    /// Staff answer routine complaints when there is staff.
    public static func staffAnswerComplaints(_ s: GameState, _ co: Company) -> Bool { s.policy.autoComplaints && !co.staff.isEmpty }

    /// The highest rank present in a company: what the lowest-level decisions can climb to before they reach the owner.
    public static func topRank(_ s: GameState, _ co: Company, data: GameData) -> Rank {
        let chain = ManagerModel.decisionChain(s, co, data: data)
        if chain.contains(where: { $0.kind == "ceo56" || $0.kind == "md" }) { return .ceo }
        if chain.contains(where: { $0.kind == "mdir" || $0.kind == "region" || $0.kind == "chainmgr" || $0.kind == "mdir" }) { return .director }
        if hasManager(co) { return .manager }
        if ManagerModel.assistantSkill(co, duty: "comp", people: s.people) != nil { return .assistantManager }
        return .owner
    }

    /// Who takes a decision of this level in this company: the lowest rank present that is at least the level (the owner if none is).
    public static func handler(level: Int, _ s: GameState, _ co: Company, data: GameData) -> Rank {
        let top = topRank(s, co, data: data)
        if top == .owner { return .owner }
        return level <= top.rawValue ? Rank(rawValue: max(level, 1)) ?? .owner : .owner
    }

    /// How serious a message is, 1 (routine) to 5 (only the owner can take it). Read-only news is routine; payroll is routine; people matters are a
    /// manager's; bad news is a CEO's; anything else that asks for a decision is a director's. A message that reached the owner is shown at the level
    /// where nobody below could take it.
    public static func level(of m: Message) -> Int {
        if m.kind != "ask" || m.status != "open" { return m.tone == "bad" ? 3 : 1 }
        if m.actionID.hasPrefix("pay29") { return 1 }
        if m.actionID == "staffx" || m.actionID == "mgrraise" || m.actionID == "mgrpoach" { return 2 }
        return m.tone == "bad" ? 4 : 3
    }

    /// The share of the owner's net worth a manager may spend on one thing without asking.
    public static let spendShareOfNetWorth = 0.005

    /// What the player's managers may spend without asking, in the home currency (0 when no company has a manager: everything is asked).
    public static func spendLimit(_ s: GameState, data: GameData) -> Double {
        guard s.companies.contains(where: { $0.status.isLive && hasManager($0) }) else { return 0 }
        return Valuation.netWorth(s, trades: data.catalog).total * spendShareOfNetWorth
    }
}
