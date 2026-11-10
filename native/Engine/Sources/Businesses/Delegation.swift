import Foundation
import GameCore
import Finance

public enum Delegation {
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

    public static func autoRehire(_ s: GameState, _ co: Company) -> Bool { hasManager(co) }
    public static func staffAnswerComplaints(_ s: GameState, _ co: Company) -> Bool { !co.staff.isEmpty }
    public static let cashReserveWeeks = 2.0

    public static func topRank(_ s: GameState, _ co: Company, data: GameData) -> Rank {
        let chain = ManagerModel.decisionChain(s, co, data: data)
        if chain.contains(where: { $0.kind == "ceo56" || $0.kind == "md" }) { return .ceo }
        if chain.contains(where: { $0.kind == "mdir" || $0.kind == "region" || $0.kind == "chainmgr" || $0.kind == "mdir" }) { return .director }
        if hasManager(co) { return .manager }
        if ManagerModel.assistantSkill(co, duty: "comp", people: s.people) != nil { return .assistantManager }
        return .owner
    }

    public static func handler(level: Int, _ s: GameState, _ co: Company, data: GameData) -> Rank {
        let top = topRank(s, co, data: data)
        if top == .owner { return .owner }
        return level <= top.rawValue ? Rank(rawValue: max(level, 1)) ?? .owner : .owner
    }

    public static func level(of m: Message, netWorth nw: Double = 0) -> Int {
        let kind = m.value("data")["kind"].string
        var base: Int
        if !(m.kind == "ask" || m.kind == "decision") || m.status != "open" { return m.tone == "bad" ? 3 : 1 }
        if m.actionID.hasPrefix("pay29") { return 1 }
        if m.actionID == "staffx" || m.actionID == PromiseReminders.action || m.actionID == "mgrraise" || m.actionID == "mgrpoach" { base = 2 }
        else if kind == "exit" || kind == PremisesProposals.kind { return 5 }
        else if m.actionID == HierarchyHiring.action { return 5 }
        else if kind == Appointments.kind { return max(3, m.value("data")["lvl"].int) }
        else if kind == "divq" || kind == "div" || kind == "rofr" { base = 4 }
        else { base = m.tone == "bad" ? 4 : 3 }
        guard nw > 0 else { return base }
        let money = amount(of: m)
        let share = money / nw
        if share > 0.05 { base += 2 } else if share > 0.01 { base += 1 } else if money > 0 { if share < 0.0005 { base -= 2 } else if share < 0.002 { base -= 1 } }
        return min(5, max(1, base))
    }

    public static func amount(of m: Message) -> Double {
        var amount = m.value("data")["amt"].double
        for o in m.options {
            let fx = o["fx"]
            amount = max(amount, abs(fx["cash"].double), abs(fx["loss"].double), abs(fx["fine"].double))
        }
        return amount
    }

    public static func managerMayTake(_ m: Message, _ co: Company, _ s: GameState, data: GameData) -> Bool {
        ManagerModel.budget(of: co).actsAlone && ManagerModel.withinBudget(co, amount: amount(of: m), s, data: data)
    }

    public static let spendShareOfNetWorth = 0.005

    public static func spendLimit(_ s: GameState, data: GameData) -> Double {
        guard s.companies.contains(where: { $0.status.isLive && hasManager($0) }) else { return 0 }
        return Valuation.netWorth(s, trades: data.catalog).total * spendShareOfNetWorth
    }
}
