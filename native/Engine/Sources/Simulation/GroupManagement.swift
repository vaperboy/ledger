import Foundation
import GameCore
import Employees
import Businesses

/// Who manages whom, for the Group screen. For every company: who runs it day to day (the store manager, or you), and the people above that
/// person in the delegation chain of `ManagerModel.decisionChain` (regional manager, chain manager, chain CEO or managing director, group
/// managing director), each with the authority they have been given. Staff are not listed: they report to the manager of their company,
/// and the Team tab and the company's People section show them. Nothing here is stored; it reads the same records as the Team tab.
public struct GroupManagement: Sendable {
    public struct Rung: Identifiable, Sendable {
        public var id: String
        public var personID: Int
        public var title: String
        public var name: String
        /// 0 asks you, 1 decides within your limits, 2 decides on their own.
        public var authority: Int
        public var authorityText: String
    }

    public struct Line: Identifiable, Sendable {
        public var id: Int
        public var name: String
        public var isHolding: Bool
        /// The chain or holding it belongs to; nil for a company that stands alone.
        public var groupName: String?
        public var isChain: Bool
        /// Who runs it day to day; nil means you do.
        public var runner: Rung?
        /// Who stands above the runner, nearest first. The last rung answers to you.
        public var above: [Rung]
        public var staff: Int
        /// The one who decides first when something needs a decision: the runner, or the nearest boss, or you.
        public var firstToDecide: String { runner?.name ?? above.first?.name ?? "You" }
    }

    public var lines: [Line]
    public var groupOfficeEstablished: Bool

    /// Companies nobody runs for you.
    public var runByYou: [Line] { lines.filter { $0.runner == nil && $0.above.isEmpty && !$0.isHolding } }
    /// Companies with a manager (or a boss) between you and the staff.
    public var delegated: [Line] { lines.filter { $0.runner != nil || !$0.above.isEmpty } }
    /// Distinct people in management posts across the group (runners and bosses).
    public var managerCount: Int {
        var seen = Set<Int>()
        for l in lines { if let r = l.runner { seen.insert(r.personID) }; for a in l.above { seen.insert(a.personID) } }
        return seen.count
    }
}

public extension GameEngine {
    func groupManagement() -> GroupManagement {
        let s = state
        var lines: [GroupManagement.Line] = []
        for co in s.companies where co.status.isLive && co.status != .setup {
            let trade = data.catalog[co.type]
            let chain = Chains.chain(s, of: co)
            let holding = co.holdingID != 0 ? s.company(co.holdingID) : nil
            func rung(_ b: ManagerModel.Boss) -> GroupManagement.Rung {
                let lvl = min(2, max(0, b.level))
                return GroupManagement.Rung(id: "\(co.id):\(b.kind):\(b.personID)", personID: b.personID, title: GameEngine.bossTitle(b.kind, trade: trade), name: b.name,
                                            authority: lvl, authorityText: GameEngine.authorityText(level: lvl))
            }
            let all = ManagerModel.decisionChain(s, co, data: data)
            let runner = all.first(where: { $0.kind == "mgr" }).map(rung)
            let above = all.filter { $0.kind != "mgr" }.map(rung)
            lines.append(GroupManagement.Line(id: co.id, name: co.name, isHolding: co.type == "hold", groupName: chain.map { $0["name"].string } ?? holding?.name, isChain: chain != nil,
                                              runner: runner, above: above, staff: co.staff.count))
        }
        return GroupManagement(lines: lines, groupOfficeEstablished: groupOfficeEstablished)
    }
}
