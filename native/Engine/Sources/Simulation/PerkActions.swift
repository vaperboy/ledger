import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Staff perks, hosting a deal on what you own, lending a piece to a manager or star worker, the rivalry and the staff stories.
/// Originals: `ACT.pk58t`, `ACT.pk58host`/`pk58hgo`, `ACT.pk58lend`/`pk58lgo` (features/people/perks_and_hosting.js), `V.nem28`
/// (features/people/staff_stories_and_nemesis.js). The yacht dinner (`lx56din`) is `hostYachtDinner` in WorldAndGivingActions.
public extension GameEngine {
    // MARK: Staff perks (Staff > Perks)
    var staffPerkOptions: [StaffPerks.Perk] { StaffPerks.all }
    func staffPerkIsOn(companyID: Int, perk: String) -> Bool { state.company(companyID).map { StaffPerks.isOn($0, perk) } ?? false }
    /// What one perk costs a month in this company (all the people it covers).
    func staffPerkMonthlyCost(companyID: Int, perk: String) -> Double {
        guard let co = state.company(companyID), let p = StaffPerks.perk(perk) else { return 0 }
        if p.id == "car" { return CompanyCarPerk.monthlyCost(state, co, data: data) }   // leases and fuel of the real cars, also before they arrive
        return StaffPerks.monthlyCost(co, p, currency: World(state: state, data: data).currency(co))
    }
    func staffPerksMonthlyTotal(companyID: Int) -> Double {
        guard let co = state.company(companyID) else { return 0 }
        return StaffPerks.onPerks(co).reduce(0) { $0 + staffPerkMonthlyCost(companyID: companyID, perk: $1.id) }
    }
    /// Who drives a company car while that perk is on, and the car each has (nil: it arrives with the next week's sync).
    func companyCarRecipients(companyID: Int) -> [CompanyCarPerk.Recipient] { CompanyCarPerk.recipients(state, companyID: companyID) }
    /// Percent fewer people who leave, with the perks that are on.
    func staffPerksFewerLeavePercent(companyID: Int) -> Double { state.company(companyID).map { StaffPerks.fewerLeavePercent($0) } ?? 0 }
    /// Switch a perk on or off; returns whether it is now on.
    @discardableResult mutating func toggleStaffPerk(companyID: Int, perk: String) -> Bool? {
        var r: Bool?
        update { s, d, _ in r = StaffPerks.toggle(&s, companyID: companyID, perk: perk, data: d) }
        return r
    }

    /// The role groups a perk may be given to (who may get which perk).
    func staffPerkGroups(perk: String) -> [StaffPerks.RoleGroup] { StaffPerks.perk(perk).map { StaffPerks.eligibleGroups($0) } ?? [] }
    /// Is the perk on for this role group in this company?
    func staffPerkCovers(companyID: Int, perk: String, group: String) -> Bool {
        guard let co = state.company(companyID), let p = StaffPerks.perk(perk) else { return false }
        return StaffPerks.covers(co, p, group: group)
    }
    /// How many people a role group has in this company.
    func staffPerkPeople(companyID: Int, group: String) -> Int { state.company(companyID).map { StaffPerks.people($0, group: group) } ?? 0 }
    /// What the perk costs a month for one role group alone, if it were on there.
    func staffPerkMonthlyCost(companyID: Int, perk: String, group: String) -> Double {
        guard let co = state.company(companyID), let p = StaffPerks.perk(perk) else { return 0 }
        var only = p
        only.groups = [group]
        var probe = co
        var f = probe.value("perks58"); if f.isNull { f = .object([:]) }
        f[perk] = .number(1); probe.set("perks58", f)
        return StaffPerks.monthlyCost(probe, only, currency: World(state: state, data: data).currency(co))
    }
    /// Switch a perk on or off for one role group; returns whether that group is covered now.
    @discardableResult mutating func toggleStaffPerk(companyID: Int, perk: String, group: String) -> Bool? {
        var r: Bool?
        update { s, d, _ in
            r = StaffPerks.toggle(&s, companyID: companyID, perk: perk, group: group)
            if perk == "car", r == true, let i = s.companyIndex(companyID) { CompanyCarPerk.sync(&s, companyIndex: i, data: d) }   // the leased cars arrive at once
        }
        return r
    }

    // MARK: Hosting a deal on a yacht, jet, castle or island
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

    // MARK: Lending a piece
    var lendablePieces: [Luxury.Piece] { StaffPerks.lendable(state) }
    var rewardCandidates: [StaffPerks.Reward] { StaffPerks.rewards(state) }
    func lentTo(pieceID: Int) -> (name: String, until: Int)? { StaffPerks.lentTo(state, pieceID: pieceID) }
    @discardableResult mutating func lendPiece(pieceID: Int, companyID: Int, staffID: Int?) -> StaffPerks.LendResult {
        var r = StaffPerks.LendResult.none
        update { s, _, _ in r = StaffPerks.lend(&s, pieceID: pieceID, companyID: companyID, staffID: staffID) }
        return r
    }

    // MARK: The rivalry and the Top 50
    var nemesis: Stories.Nemesis? { Stories.nemesis(state) }
    /// The Top 50 printed last January, with your place on it.
    var topFifty: Stories.TopFifty? { Stories.topFifty(state) }
    /// What has happened in a worker's working life at your company, newest first.
    func staffStory(companyID: Int, staffID: Int) -> [(week: Int, text: String)] { Stories.story(state, companyID: companyID, staffID: staffID) }
    /// People who retired from your companies, newest first.
    var retirementHall: [(name: String, text: String, week: Int)] { Stories.hall(state) }
}
