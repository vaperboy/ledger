import Foundation
import GameCore
import Countries
import Finance
import Businesses

public extension GameEngine {
    var staffPerkOptions: [StaffPerks.Perk] { StaffPerks.all }
    func staffPerkIsOn(companyID: Int, perk: String) -> Bool { state.company(companyID).map { StaffPerks.isOn($0, perk) } ?? false }
    func staffPerkMonthlyCost(companyID: Int, perk: String) -> Double {
        guard let co = state.company(companyID), let p = StaffPerks.perk(perk) else { return 0 }
        if p.id == "car" { return CompanyCarPerk.monthlyCost(state, co, data: data) }
        return StaffPerks.monthlyCost(co, p, currency: World(state: state, data: data).currency(co))
    }
    func staffPerksMonthlyTotal(companyID: Int) -> Double {
        guard let co = state.company(companyID) else { return 0 }
        return StaffPerks.onPerks(co).reduce(0) { $0 + staffPerkMonthlyCost(companyID: companyID, perk: $1.id) }
    }
    func companyCarRecipients(companyID: Int) -> [CompanyCarPerk.Recipient] { CompanyCarPerk.recipients(state, companyID: companyID) }
    func staffPerksFewerLeavePercent(companyID: Int) -> Double { state.company(companyID).map { StaffPerks.fewerLeavePercent($0) } ?? 0 }
    @discardableResult mutating func toggleStaffPerk(companyID: Int, perk: String) -> Bool? {
        var r: Bool?
        update { s, d, _ in r = StaffPerks.toggle(&s, companyID: companyID, perk: perk, data: d) }
        return r
    }

    func staffPerkGroups(perk: String) -> [StaffPerks.RoleGroup] { StaffPerks.perk(perk).map { StaffPerks.eligibleGroups($0) } ?? [] }
    func staffPerkCovers(companyID: Int, perk: String, group: String) -> Bool {
        guard let co = state.company(companyID), let p = StaffPerks.perk(perk) else { return false }
        return StaffPerks.covers(co, p, group: group)
    }
    func staffPerkPeople(companyID: Int, group: String) -> Int { state.company(companyID).map { StaffPerks.people($0, group: group) } ?? 0 }
    func staffPerkMonthlyCost(companyID: Int, perk: String, group: String) -> Double {
        guard let co = state.company(companyID), let p = StaffPerks.perk(perk) else { return 0 }
        var only = p
        only.groups = [group]
        var probe = co
        var f = probe.value("perks58"); if f.isNull { f = .object([:]) }
        f[perk] = .number(1); probe.set("perks58", f)
        return StaffPerks.monthlyCost(probe, only, currency: World(state: state, data: data).currency(co))
    }
    @discardableResult mutating func toggleStaffPerk(companyID: Int, perk: String, group: String) -> Bool? {
        var r: Bool?
        update { s, d, _ in
            r = StaffPerks.toggle(&s, companyID: companyID, perk: perk, group: group)
            if perk == "car", r == true, let i = s.companyIndex(companyID) { CompanyCarPerk.sync(&s, companyIndex: i, data: d) }
        }
        return r
    }

    var hostingVenues: [Luxury.Piece] { StaffPerks.venues(state, data: data) }
    func hostingCost(pieceID: Int) -> Double? { StaffPerks.hostingCost(state, data: data, pieceID: pieceID) }
    var hostingGuests: [StaffPerks.GuestOption] { StaffPerks.guests(state) }
    @discardableResult mutating func hostDeal(pieceID: Int, guest: StaffPerks.HostGuest) -> StaffPerks.HostResult {
        var r = StaffPerks.HostResult.none
        update { s, d, _ in
            r = StaffPerks.host(&s, data: d, pieceID: pieceID, guest: guest)
            if case .ok(let title, let body) = r { s.addMessage(kind: "info", from: "Your evening", title: title, body: body, tone: "good") }
        }
        return r
    }

    var lendablePieces: [Luxury.Piece] { StaffPerks.lendable(state) }
    var rewardCandidates: [StaffPerks.Reward] { StaffPerks.rewards(state) }
    func lentTo(pieceID: Int) -> (name: String, until: Int)? { StaffPerks.lentTo(state, pieceID: pieceID) }
    @discardableResult mutating func lendPiece(pieceID: Int, companyID: Int, staffID: Int?) -> StaffPerks.LendResult {
        var r = StaffPerks.LendResult.none
        update { s, _, _ in r = StaffPerks.lend(&s, pieceID: pieceID, companyID: companyID, staffID: staffID) }
        return r
    }

    var nemesis: Stories.Nemesis? { Stories.nemesis(state) }
    var topFifty: Stories.TopFifty? { Stories.topFifty(state) }
    func staffStory(companyID: Int, staffID: Int) -> [(week: Int, text: String)] { Stories.story(state, companyID: companyID, staffID: staffID) }
    var retirementHall: [(name: String, text: String, week: Int)] { Stories.hall(state) }
}
