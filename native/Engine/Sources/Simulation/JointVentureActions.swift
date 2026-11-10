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

    @discardableResult
    mutating func jvInvite(companyID: Int, playerID: String, name: String, linkKey: String, role: String = "partner", mock: Bool = true, pct: Double, price: Double, myLinkKeys: Set<String>) -> JointVenture.InviteResult {
        var r = JointVenture.InviteResult.refused("Could not invite.")
        update { s, d, c in r = JointVenture.invite(&s, companyID: companyID, playerID: playerID, name: name, linkKey: linkKey, role: role, mock: mock, pct: pct, price: price, myLinkKeys: myLinkKeys, data: d, context: c) }
        return r
    }
    @discardableResult
    mutating func jvRespond(companyID: Int, inviteID: Int, accept: Bool) -> String? {
        var r: String?
        update { s, d, c in r = JointVenture.respond(&s, companyID: companyID, inviteID: inviteID, accept: accept, data: d, context: c) }
        return r
    }
    @discardableResult
    mutating func jvVote(companyID: Int, meetingID: Int, itemID: Int, member: String = JointVenture.Member.me, choice: JVRules.Choice) -> Bool {
        var ok = false
        update { s, _, _ in ok = JointVenture.castVote(&s, companyID: companyID, meetingID: meetingID, itemID: itemID, member: member, choice: choice) }
        return ok
    }
    mutating func jvMakeItem(companyID: Int, kind: JVRules.Kind, by: String? = nil, amount: Double = 0, steps: Int = 0) -> (item: JointVenture.Item?, problem: String?) {
        var r: (item: JointVenture.Item?, problem: String?) = (nil, "Could not make that item.")
        update { s, d, c in r = JointVenture.makeItem(&s, companyID: companyID, kind: kind, by: by ?? s.player.name, amount: amount, steps: steps, data: d, context: c) }
        return r
    }
    @discardableResult
    mutating func jvCallUrgent(companyID: Int, by member: String = JointVenture.Member.me, reason: String, items: [JointVenture.Item]) -> JointVenture.CallResult {
        var r = JointVenture.CallResult.refused("Could not call it.")
        update { s, d, c in r = JointVenture.callUrgent(&s, companyID: companyID, by: member, reason: reason, items: items, data: d, context: c) }
        return r
    }
    func jvExitTerms(companyID: Int, memberID: String) -> JointVenture.ExitTerms? { JointVenture.exitTerms(state, companyID: companyID, memberID: memberID, data: data, context: context) }
    @discardableResult
    mutating func jvBuyOut(companyID: Int, memberID: String) -> String? {
        var r: String? = "Could not buy them out."
        update { s, d, c in r = JointVenture.buyOut(&s, companyID: companyID, memberID: memberID, data: d, context: c) }
        return r
    }
    @discardableResult
    mutating func jvPartnerWantsOut(companyID: Int, memberID: String) -> String? {
        var r: String? = "Could not send that."
        update { s, d, c in r = JointVenture.partnerWantsOut(&s, companyID: companyID, memberID: memberID, data: d, context: c) }
        return r
    }

    @discardableResult
    mutating func jvQueue(companyID: Int, item: JointVenture.Item) -> Bool {
        var ok = false
        update { s, _, _ in ok = JointVenture.queue(&s, companyID: companyID, item: item) }
        return ok
    }
}
