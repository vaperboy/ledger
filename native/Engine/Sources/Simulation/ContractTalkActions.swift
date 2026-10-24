import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses

/// The contract discussion with one employee (`ContractTalk`): the only engine door for raises, promotions, hours, pay basis, bonus plans, benefits,
/// notice and moves of people who already work for you. The staff profile and the Team screens read and act through these and nothing else.
public extension GameEngine {
    /// The topics, each with whether it can be discussed with this person and why not.
    func contractTopics(companyID: Int, personID: Int) -> [ContractTalk.TopicInfo] {
        ContractTalk.topics(state, companyID: companyID, personID: personID, data: data)
    }

    /// The options inside a topic (posts, ways of paying, perks, places).
    func contractChoices(companyID: Int, personID: Int, topic: ContractTalk.Topic) -> [ContractTalk.Choice] {
        ContractTalk.choices(state, companyID: companyID, personID: personID, topic: topic, data: data)
    }

    /// What the proposal would do, worked out on a copy of the game: cost a month, quit risk, peers, the country's labour rules.
    func contractPreview(companyID: Int, personID: Int, proposal: ContractTalk.Proposal, asRequest: Bool = false) -> ContractTalk.Consequences {
        ContractTalk.preview(state, companyID: companyID, personID: personID, proposal: proposal, asRequest: asRequest, data: data)
    }

    /// The talk that is open with this person, if any (their request, or one you started and they answered with a counter).
    func contractTalk(personID: Int) -> ContractTalk.Talk? { ContractTalk.openTalk(state, personID: personID) }

    /// The manager who may handle this company's contract talks, with the limit; nil when they all come to you.
    func contractHandler(companyID: Int) -> ContractTalk.Handler? { ContractTalk.handler(state, companyID: companyID, data: data) }

    /// Put something to them.
    @discardableResult
    mutating func contractPropose(companyID: Int, personID: Int, proposal: ContractTalk.Proposal) -> ContractTalk.Reply {
        var r = ContractTalk.Reply.notPossible("")
        update { s, d, _ in r = ContractTalk.propose(&s, companyID: companyID, personID: personID, proposal: proposal, data: d) }
        return r
    }

    /// Answer a request of theirs: agree, counter with your own figure, delay or decline.
    @discardableResult
    mutating func contractRespond(companyID: Int, personID: Int, decision: ContractTalk.Decision) -> ContractTalk.Reply {
        var r = ContractTalk.Reply.notPossible("")
        update { s, d, _ in r = ContractTalk.respond(&s, companyID: companyID, personID: personID, decision: decision, data: d) }
        return r
    }

    /// Leave their request to the company's manager, if it is inside their limit.
    @discardableResult
    mutating func contractLeaveToManager(companyID: Int, personID: Int) -> ContractTalk.Reply {
        var r = ContractTalk.Reply.notPossible("")
        update { s, d, _ in r = ContractTalk.leaveToManager(&s, companyID: companyID, personID: personID, data: d) }
        return r
    }

    /// Drop an open talk without a decision (their request is forgotten; nothing changes for them).
    mutating func contractWithdraw(personID: Int) { update { s, _, _ in ContractTalk.close(&s, personID: personID) } }
}
