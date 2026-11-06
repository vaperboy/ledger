import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// The owner's talks with the people who run a company, the boardroom round, and replacing the CEO, as player actions.
/// Models: `OwnerMeetings`, `ManagerBoards`.
public extension GameEngine {
    func ownerCounterparts(companyID: Int) -> [OwnerMeetings.Counterpart] { OwnerMeetings.counterparts(state, companyID: companyID) }
    func ownerTopics(companyID: Int, personID: Int) -> [OwnerMeetings.Topic] { OwnerMeetings.topics(state, companyID: companyID, personID: personID) }
    func ownerScene(companyID: Int, personID: Int, topic: String) -> OwnerMeetings.Scene? { OwnerMeetings.scene(state, companyID: companyID, personID: personID, topic: topic, data: data) }
    @discardableResult
    mutating func ownerChoose(companyID: Int, personID: Int, topic: String, choice: String) -> OwnerMeetings.Outcome? {
        var r: OwnerMeetings.Outcome?; let m = marketing
        update { s, d, _ in r = OwnerMeetings.choose(&s, companyID: companyID, personID: personID, topic: topic, choice: choice, data: d, marketing: m) }
        return r
    }
    func companyDirective(companyID: Int) -> String? { state.company(companyID).flatMap { OwnerMeetings.directive($0) } }
    func boardIsAdvisory(companyID: Int) -> Bool { OwnerMeetings.isAdvisory(state, companyID: companyID) }
    func boardRound(companyID: Int) -> [OwnerMeetings.RoundLine] { OwnerMeetings.boardRound(state, companyID: companyID, data: data) }
    /// What the board and the co-owners say to replacing the CEO (advisory only when you own it alone).
    func ceoVote(companyID: Int) -> ManagerModel.BoardVote { ManagerModel.boardVote(state, kind: "ceo", companyID: companyID, advisory: true) }
    /// What the board says about selling, closing or a loan, also for a company you own alone (then it only advises).
    func advisoryVote(kind: String, companyID: Int, amount: Double = 0) -> ManagerModel.BoardVote { ManagerModel.boardVote(state, kind: kind, companyID: companyID, amount: amount, advisory: true) }
    @discardableResult
    mutating func proposeCEOChange(companyID: Int) -> ManagerModel.CEOChange {
        var r = ManagerModel.CEOChange.refused("There is nobody to replace.")
        update { s, d, _ in r = ManagerModel.proposeCEOChange(&s, companyID: companyID, data: d) }
        return r
    }
}
