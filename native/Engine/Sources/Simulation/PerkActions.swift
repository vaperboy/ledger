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
        return StaffPerks.monthlyCost(co, p, currency: World(state: state, data: data).currency(co))
    }
    func staffPerksMonthlyTotal(companyID: Int) -> Double {
        guard let co = state.company(companyID) else { return 0 }
        return StaffPerks.totalMonthlyCost(co, currency: World(state: state, data: data).currency(co))
    }
    /// Percent fewer people who leave, with the perks that are on.
    func staffPerksFewerLeavePercent(companyID: Int) -> Double { state.company(companyID).map { StaffPerks.fewerLeavePercent($0) } ?? 0 }
    /// Switch a perk on or off; returns whether it is now on.
    @discardableResult mutating func toggleStaffPerk(companyID: Int, perk: String) -> Bool? {
        var r: Bool?
        update { s, _, _ in r = StaffPerks.toggle(&s, companyID: companyID, perk: perk) }
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
