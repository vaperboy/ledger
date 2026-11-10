import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses

public extension GameEngine {
    func contractTopics(companyID: Int, personID: Int) -> [ContractTalk.TopicInfo] {
        ContractTalk.topics(state, companyID: companyID, personID: personID, data: data)
    }

    func contractChoices(companyID: Int, personID: Int, topic: ContractTalk.Topic) -> [ContractTalk.Choice] {
        ContractTalk.choices(state, companyID: companyID, personID: personID, topic: topic, data: data)
    }

    func contractPreview(companyID: Int, personID: Int, proposal: ContractTalk.Proposal, asRequest: Bool = false) -> ContractTalk.Consequences {
        ContractTalk.preview(state, companyID: companyID, personID: personID, proposal: proposal, asRequest: asRequest, data: data)
    }

    func contractTalk(personID: Int) -> ContractTalk.Talk? { ContractTalk.openTalk(state, personID: personID) }

    func contractHandler(companyID: Int) -> ContractTalk.Handler? { ContractTalk.handler(state, companyID: companyID, data: data) }

    @discardableResult
    mutating func contractPropose(companyID: Int, personID: Int, proposal: ContractTalk.Proposal) -> ContractTalk.Reply {
        var r = ContractTalk.Reply.notPossible("")
        update { s, d, _ in r = ContractTalk.propose(&s, companyID: companyID, personID: personID, proposal: proposal, data: d) }
        return r
    }

    @discardableResult
    mutating func contractRespond(companyID: Int, personID: Int, decision: ContractTalk.Decision) -> ContractTalk.Reply {
        var r = ContractTalk.Reply.notPossible("")
        update { s, d, _ in r = ContractTalk.respond(&s, companyID: companyID, personID: personID, decision: decision, data: d) }
        return r
    }

    @discardableResult
    mutating func contractLeaveToManager(companyID: Int, personID: Int) -> ContractTalk.Reply {
        var r = ContractTalk.Reply.notPossible("")
        update { s, d, _ in r = ContractTalk.leaveToManager(&s, companyID: companyID, personID: personID, data: d) }
        return r
    }

    mutating func contractWithdraw(personID: Int) { update { s, _, _ in ContractTalk.close(&s, personID: personID) } }
}
