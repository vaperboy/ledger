import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Events

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
    func ceoVote(companyID: Int) -> ManagerModel.BoardVote { ManagerModel.boardVote(state, kind: "ceo", companyID: companyID, advisory: true) }
    func advisoryVote(kind: String, companyID: Int, amount: Double = 0) -> ManagerModel.BoardVote { ManagerModel.boardVote(state, kind: kind, companyID: companyID, amount: amount, advisory: true) }
    @discardableResult
    mutating func proposeCEOChange(companyID: Int) -> ManagerModel.CEOChange {
        var r = ManagerModel.CEOChange.refused("There is nobody to replace.")
        update { s, d, _ in r = ManagerModel.proposeCEOChange(&s, companyID: companyID, data: d) }
        return r
    }
}

public extension GameEngine {
    func maximumDividend(companyID: Int) -> Double { state.company(companyID).map { JointVenture.payoutRoom(state, $0, context) } ?? 0 }
    func saleQuote(companyID: Int, percent: Int, method: CompanySale.Method) -> CompanySale.Quote? {
        CompanySale.quote(state, companyID: companyID, pct: percent, method: method, data: data, context: context)
    }
    func saleListing(companyID: Int) -> CompanySale.Listing? { CompanySale.listing(state, companyID: companyID) }
    @discardableResult
    mutating func startSale(companyID: Int, percent: Int, method: CompanySale.Method, reserve: Double = 0) -> CompanySale.StartResult {
        var r = CompanySale.StartResult.refused("Not possible.")
        update { s, d, c in r = CompanySale.start(&s, companyID: companyID, pct: percent, method: method, reserve: reserve, data: d, context: c) }
        return r
    }
    @discardableResult
    mutating func hammerSale(companyID: Int) -> Double? {
        var r: Double?
        update { s, d, c in r = CompanySale.hammer(&s, companyID: companyID, data: d, context: c) }
        return r
    }
}
