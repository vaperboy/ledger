import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Events

/// Deals between players, as the screens call them: franchising to players for a chosen number of days, taking up another player's franchise, putting a
/// company on sale to players and buying one that another player has put up. The rules are `PlayerDeals`; the other players come from the app's service.
public extension GameEngine {
    // MARK: Franchising to players

    /// The last day the company's franchise takes players; nil when it is not open to them.
    func franchiseOpenUntil(companyID: Int) -> Int? { state.company(companyID).flatMap { PlayerDeals.franchiseOpenUntil($0) } }

    @discardableResult
    mutating func openFranchiseToPlayers(companyID: Int, days: Int) -> PlayerDeals.OpenResult {
        var r = PlayerDeals.OpenResult.notFranchising
        update { s, _, _ in r = PlayerDeals.openFranchiseOffer(&s, companyID: companyID, days: days) }
        return r
    }

    mutating func closeFranchiseToPlayers(companyID: Int) { update { s, _, _ in PlayerDeals.closeFranchiseOffer(&s, companyID: companyID) } }

    @discardableResult
    mutating func addFranchiseApplicant(companyID: Int, applicant: PlayerDeals.PlayerApplicant) -> Bool {
        var ok = false
        update { s, _, _ in ok = PlayerDeals.addPlayerApplicant(&s, companyID: companyID, applicant: applicant) }
        return ok
    }

    /// The franchise offer of one of the player's companies as other players see it; nil while it is not open to players.
    func franchiseListing(companyID: Int, ownerID: String, ownerName: String, profileCode: String, linkKey: String) -> PlayerDeals.FranchiseListing? {
        PlayerDeals.franchiseListing(state, companyID: companyID, ownerID: ownerID, ownerName: ownerName, profileCode: profileCode, linkKey: linkKey, data: data)
    }

    /// Take another player's franchise offer into the game as a brand: apply, talk and open the unit as with any brand.
    /// Returns the brand's id, or nil when the offer has ended or the trade cannot be franchised.
    @discardableResult
    mutating func importPlayerFranchise(_ l: PlayerDeals.FranchiseListing) -> String? {
        guard FranchiseBrands.isFranchisable(l.tradeID), l.isOpen(today: PlayerDeals.today(state)) else { return nil }
        update { s, _, _ in FranchiseBrands.importPlayerBrand(&s, listing: l) }
        return "P:" + l.id
    }

    // MARK: Selling a company to players

    /// The last day the company's sale listing is shown to other players; nil when it is not.
    func playerSaleUntil(companyID: Int) -> Int? { PlayerDeals.playerListingUntil(state, companyID: companyID) }

    /// Put the company on the market and show it to other players for `days` days.
    @discardableResult
    mutating func startSaleToPlayers(companyID: Int, days: Int) -> Bool {
        var ok = false
        update { s, _, _ in ok = CompanySale.startPlayerListing(&s, companyID: companyID, days: days) }
        return ok
    }

    /// The company as a listing other players see, at the price the player asks.
    func companyListing(companyID: Int, ownerID: String, ownerName: String, profileCode: String, linkKey: String, askPrice: Double) -> PlayerDeals.CompanyListing? {
        PlayerDeals.listing(state, companyID: companyID, ownerID: ownerID, ownerName: ownerName, profileCode: profileCode, linkKey: linkKey, askPrice: askPrice, data: data)
    }

    /// What the company is worth to a buyer, to suggest an asking price.
    func companyAskingValue(companyID: Int) -> Double {
        guard let l = unlistedSnapshot(companyID: companyID) else { return 0 }
        return PlayerDeals.value(l)
    }

    private func unlistedSnapshot(companyID: Int) -> PlayerDeals.CompanyListing? {
        guard let co = state.company(companyID) else { return nil }
        let rev: Double = (co.books.year["rev"] ?? 0) > 0 ? co.books.year["rev"]! : co.lastWeekRevenue * 52
        return PlayerDeals.CompanyListing(id: "C\(co.id)", ownerID: "me", ownerName: "", profileCode: "", linkKey: "", companyName: co.name, tradeID: co.type, cityID: co.cityID,
                                          countryCode: co.countryCode, size: co.size, yearlyRevenue: rev, yearlyProfit: CompanyFigures.yearlyProfitEstimate(co, currentWeek: state.week), staff: co.staff.count,
                                          reputation: co.reputation, weeksTrading: 0, askPrice: 0, expiresDay: 0)
    }

    /// An offer from a player on the company that is shown to players.
    @discardableResult
    mutating func addPlayerSaleOffer(companyID: Int, buyer: CompanySale.PlayerBuyer, price: Double) -> Bool {
        var ok = false
        update { s, _, ctx in ok = CompanySale.addPlayerOffer(&s, companyID: companyID, buyer: buyer, price: price, context: ctx) }
        return ok
    }

    // MARK: Buying another player's company

    func playerCompanyBuyPlan(_ l: PlayerDeals.CompanyListing, price: Double) -> PlayerDeals.BuyPlan? { PlayerDeals.buyPlan(state, listing: l, price: price, data: data) }

    @discardableResult
    mutating func buyPlayerCompany(_ l: PlayerDeals.CompanyListing, price: Double, buyerLinkKeys: Set<String>) -> PlayerDeals.BuyResult {
        var r = PlayerDeals.BuyResult.notAllowed("")
        update { s, d, ctx in r = PlayerDeals.buy(&s, listing: l, price: price, buyerLinkKeys: buyerLinkKeys, data: d, context: ctx) }
        return r
    }
}
