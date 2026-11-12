import Foundation
import GameCore
import Finance
import Businesses
import Events

public extension GameEngine {
    var jointVentures: [Company] { JointVenture.venture(state) }
    func jointVenture(companyID: Int) -> JointVenture.State? { state.company(companyID).flatMap { JointVenture.state($0) } }
    func jvStakes(companyID: Int) -> [JointVenture.Stake] { JointVenture.stakes(state, companyID: companyID) }
    func jvTerms(companyID: Int, pct: Double, price: Double) -> JointVenture.Terms? { JointVenture.terms(state, companyID: companyID, pct: pct, price: price, data: data, context: context) }
    func jvFairPrice(companyID: Int, pct: Double) -> Double {
        state.company(companyID).map { JVRules.fairPrice(value: max(0, Valuation.companyValue($0, state: state, trades: data.catalog)), pct: pct) } ?? 0
    }
    func jvTally(companyID: Int, meetingID: Int, itemID: Int) -> JVRules.Tally? { JointVenture.tally(state, companyID: companyID, meetingID: meetingID, itemID: itemID) }
    var jvMeetingsWaiting: Int { JointVenture.waitingForYou(state) }
    func jvCanStart(companyID: Int) -> Bool {
        guard let co = state.company(companyID) else { return false }
        return co.status == .open && !state.isBranch(co)
    }
    func jvBoardCompany(companyID: Int) -> Company? { JointVenture.boardCompany(state, companyID: companyID) }
    func jvBoardCompany(chainID: Int) -> Company? { JointVenture.boardCompany(state, chainID: chainID) }
    func jvNextMeeting(now: Date = Date()) -> Date { Date(timeIntervalSince1970: JVRules.nextMeeting(after: now.timeIntervalSince1970)) }
    func jvBuyBackOffers(companyID: Int) -> [JointVenture.Buyback] { jointVenture(companyID: companyID).map { JointVenture.buyBackOffers($0) } ?? [] }

    @discardableResult
    mutating func jvInvite(companyID: Int, playerID: String, name: String, linkKey: String, role: String = "partner", mock: Bool = true, pct: Double, price: Double, myLinkKeys: Set<String>,
                           now: Date = Date()) -> JointVenture.InviteResult {
        var r = JointVenture.InviteResult.refused("Could not invite.")
        let at: Double = now.timeIntervalSince1970
        update { s, d, c in r = JointVenture.invite(&s, companyID: companyID, playerID: playerID, name: name, linkKey: linkKey, role: role, mock: mock, pct: pct, price: price, myLinkKeys: myLinkKeys, now: at, data: d, context: c) }
        return r
    }
    @discardableResult
    mutating func jvRespond(companyID: Int, inviteID: Int, accept: Bool) -> String? {
        var r: String?
        update { s, d, c in r = JointVenture.respond(&s, companyID: companyID, inviteID: inviteID, accept: accept, data: d, context: c) }
        return r
    }
    @discardableResult
    mutating func jvVote(companyID: Int, meetingID: Int, itemID: Int, member: String = JointVenture.Member.me, choice: JVRules.Choice, now: Date = Date()) -> Bool {
        var ok = false
        let at: Double = now.timeIntervalSince1970
        update { s, d, c in
            ok = JointVenture.castVote(&s, companyID: companyID, meetingID: meetingID, itemID: itemID, member: member, choice: choice, now: at)
            if ok { JointVenture.settle(&s, now: at, data: d, context: c) }
        }
        return ok
    }
    mutating func jvMakeItem(companyID: Int, kind: JVRules.Kind, by: String? = nil, amount: Double = 0, steps: Int = 0) -> (item: JointVenture.Item?, problem: String?) {
        var r: (item: JointVenture.Item?, problem: String?) = (nil, "Could not make that item.")
        update { s, d, c in r = JointVenture.makeItem(&s, companyID: companyID, kind: kind, by: by ?? s.player.name, amount: amount, steps: steps, data: d, context: c) }
        return r
    }
    @discardableResult
    mutating func jvCallUrgent(companyID: Int, by member: String = JointVenture.Member.me, reason: String, items: [JointVenture.Item], now: Date = Date()) -> JointVenture.CallResult {
        var r = JointVenture.CallResult.refused("Could not call it.")
        let at: Double = now.timeIntervalSince1970
        update { s, d, c in r = JointVenture.callUrgent(&s, companyID: companyID, by: member, reason: reason, items: items, now: at, data: d, context: c) }
        return r
    }
    @discardableResult
    mutating func jvQueue(companyID: Int, item: JointVenture.Item, by member: String = JointVenture.Member.me, now: Date = Date()) -> Bool {
        var ok = false
        let at: Double = now.timeIntervalSince1970
        update { s, _, _ in ok = JointVenture.queue(&s, companyID: companyID, item: item, by: member, now: at) }
        return ok
    }
    @discardableResult
    mutating func jvPropose(companyID: Int, change: JointVenture.Change, urgent: Bool, now: Date = Date()) -> JointVenture.ProposeResult {
        var r = JointVenture.ProposeResult.refused("Could not put that to the board.")
        let at: Double = now.timeIntervalSince1970
        update { s, d, c in r = JointVenture.propose(&s, companyID: companyID, change: change, urgent: urgent, now: at, data: d, context: c) }
        return r
    }
    mutating func jvSettle(now: Date = Date()) {
        let at: Double = now.timeIntervalSince1970
        update { s, d, c in JointVenture.settle(&s, now: at, data: d, context: c) }
    }

    func jvExitTerms(companyID: Int, memberID: String) -> JointVenture.ExitTerms? { JointVenture.exitTerms(state, companyID: companyID, memberID: memberID, data: data, context: context) }
    @discardableResult
    mutating func jvOfferBuyBack(companyID: Int, memberID: String, price: Double, now: Date = Date()) -> String? {
        var r: String? = "Could not make that offer."
        let at: Double = now.timeIntervalSince1970
        update { s, d, c in r = JointVenture.offerBuyBack(&s, companyID: companyID, memberID: memberID, price: price, now: at, data: d, context: c) }
        return r
    }
    @discardableResult
    mutating func jvAnswerBuyBack(companyID: Int, offerID: Int, accept: Bool) -> String? {
        var r: String? = "That offer is no longer open."
        update { s, d, c in r = JointVenture.answerBuyBack(&s, companyID: companyID, offerID: offerID, accept: accept, data: d, context: c) }
        return r
    }
    @discardableResult
    mutating func jvWithdrawBuyBack(companyID: Int, offerID: Int) -> Bool {
        var ok = false
        update { s, _, _ in ok = JointVenture.withdrawBuyBack(&s, companyID: companyID, offerID: offerID) }
        return ok
    }
    @discardableResult
    mutating func jvPartnerWantsOut(companyID: Int, memberID: String) -> String? {
        var r: String? = "Could not send that."
        update { s, d, c in r = JointVenture.partnerWantsOut(&s, companyID: companyID, memberID: memberID, data: d, context: c) }
        return r
    }
}
