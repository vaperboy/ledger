import Foundation
import GameCore
import Countries
import Businesses

public extension GameEngine {
    func delegatedSpendLimit() -> (limit: Double, rate: Double) {
        let limit = Delegation.spendLimit(state, data: data)
        guard limit > 0 else { return (0, 0) }
        return (limit, ManagerModel.playerCurrency(state, data).rate)
    }
}

public struct DelegationLine: Identifiable, Equatable, Sendable {
    public var id: Int
    public var name: String
    public var top: String
    public var payroll: String
    public var rehire: String
    public var complaints: String
}

public extension GameEngine {
    func delegationLines() -> [DelegationLine] {
        state.companies.filter { $0.status.isLive }.map { co -> DelegationLine in
            let mgr: Bool = Delegation.hasManager(co)
            let payroll: String = mgr ? "Manager" : "You (a reminder)"
            let asst: Bool = ManagerModel.assistantSkill(co, duty: "comp", people: state.people) != nil
            let complaints: String = mgr ? "Manager" : asst ? "Assistant manager" : Delegation.staffAnswerComplaints(state, co) ? "Staff" : "You"
            return DelegationLine(id: co.id, name: co.name, top: Delegation.topRank(state, co, data: data).title, payroll: payroll,
                                  rehire: mgr ? "Manager" : "You", complaints: complaints)
        }
    }
}

public extension GameEngine {
    func severityLevel(of m: Message) -> Int { Delegation.severity(of: m, netWorth: dayHistory.netWorth.last ?? 0) }

    var ownerDecisions: [Message] { state.inbox.filter { $0.status == "open" && $0.isOwnerAddressed } }
}
