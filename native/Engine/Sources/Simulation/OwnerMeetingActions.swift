import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Events

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

// MARK: Selling: one set of routes, all finishing in `CompanySale`
public extension GameEngine {
    func saleRoutes(companyID: Int) -> [CompanySale.Route] { CompanySale.routes(state, companyID: companyID, data: data, context: context) }
    func stakeTiers(companyID: Int) -> [CompanySale.StakeTier] { CompanySale.stakeTiers(state, companyID: companyID) }
    func saleListing(companyID: Int) -> CompanySale.Listing? { CompanySale.listing(state, companyID: companyID) }
    /// route: "private", "broker" or "mbo"; `percent` below 100 sells part of your shares.
    @discardableResult
    mutating func startSale(companyID: Int, route: String, percent: Int = 100) -> Bool {
        var ok = false
        update { s, _, _ in ok = CompanySale.startListing(&s, companyID: companyID, route: route, pct: percent) }
        return ok
    }
    @discardableResult
    mutating func startAuction(companyID: Int, reserve: Double, percent: Int = 100) -> Bool {
        var ok = false
        update { s, d, c in ok = CompanySale.startAuction(&s, companyID: companyID, reserve: reserve, pct: percent, data: d, context: c) }
        return ok
    }
    /// Take the highest bid standing. Returns the cash you get.
    @discardableResult
    mutating func hammerSale(companyID: Int) -> Double? {
        var r: Double?
        update { s, d, c in r = CompanySale.hammer(&s, companyID: companyID, data: d, context: c) }
        return r
    }
    func mergeCandidates(companyID: Int) -> [CompanySale.MergeCandidate] { CompanySale.mergeCandidates(state, companyID: companyID) }
    @discardableResult
    mutating func mergeWithRival(companyID: Int, rivalID: Int, percent: Double) -> CompanySale.MergeResult {
        var r = CompanySale.MergeResult.refused("Not possible.")
        update { s, d, c in r = CompanySale.mergeWithRival(&s, companyID: companyID, rivalID: rivalID, pct: percent, data: d, context: c) }
        return r
    }
    func groupBuyers(companyID: Int) -> [CompanySale.GroupBuyer] { CompanySale.groupBuyers(state, companyID: companyID, data: data, context: context) }
    @discardableResult
    mutating func sellToGroup(companyID: Int, groupID: String) -> Double? {
        var r: Double?
        update { s, d, c in r = CompanySale.sellToGroupNow(&s, companyID: companyID, groupID: groupID, data: d, context: c) }
        return r
    }
}
