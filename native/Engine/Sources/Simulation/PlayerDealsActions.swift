import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Events

public extension GameEngine {

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

    func franchiseListing(companyID: Int, ownerID: String, ownerName: String, profileCode: String, linkKey: String) -> PlayerDeals.FranchiseListing? {
        PlayerDeals.franchiseListing(state, companyID: companyID, ownerID: ownerID, ownerName: ownerName, profileCode: profileCode, linkKey: linkKey, data: data)
    }

    @discardableResult
    mutating func importPlayerFranchise(_ l: PlayerDeals.FranchiseListing) -> String? {
        guard FranchiseBrands.isFranchisable(l.tradeID), l.isOpen(today: PlayerDeals.today(state)) else { return nil }
        update { s, _, _ in FranchiseBrands.importPlayerBrand(&s, listing: l) }
        return "P:" + l.id
    }

    func playerSaleUntil(companyID: Int) -> Int? { PlayerDeals.playerListingUntil(state, companyID: companyID) }

    @discardableResult
    mutating func startSaleToPlayers(companyID: Int, days: Int) -> Bool {
        var ok = false
        update { s, _, _ in ok = CompanySale.startPlayerListing(&s, companyID: companyID, days: days) }
        return ok
    }

    mutating func stopSaleToPlayers(companyID: Int) { update { s, _, _ in PlayerDeals.hideFromPlayers(&s, companyID: companyID) } }

    func companyListing(companyID: Int, ownerID: String, ownerName: String, profileCode: String, linkKey: String, askPrice: Double) -> PlayerDeals.CompanyListing? {
        PlayerDeals.listing(state, companyID: companyID, ownerID: ownerID, ownerName: ownerName, profileCode: profileCode, linkKey: linkKey, askPrice: askPrice, data: data)
    }

    func companyAskingValue(companyID: Int) -> Double {
        guard let l = unlistedSnapshot(companyID: companyID) else { return 0 }
        return PlayerDeals.value(l)
    }

    private func unlistedSnapshot(companyID: Int) -> PlayerDeals.CompanyListing? {
        guard let co = state.company(companyID) else { return nil }
        let rev: Double = (co.books.year["rev"] ?? 0) > 0 ? co.books.year["rev"]! : co.lastWeekRevenue * 52
        let l = PlayerDeals.CompanyListing(id: "C\(co.id)", ownerID: "me", ownerName: "", profileCode: "", linkKey: "", companyName: co.name, tradeID: co.type, cityID: co.cityID,
                                           countryCode: co.countryCode, size: co.size, yearlyRevenue: rev, yearlyProfit: CompanyFigures.yearlyProfitEstimate(co, currentWeek: state.week), staff: co.staff.count,
                                           reputation: co.reputation, weeksTrading: 0, askPrice: 0, expiresDay: 0)
        return PlayerDeals.withBalanceSheet(l, co, state: state)
    }

    @discardableResult
    mutating func addPlayerSaleOffer(companyID: Int, buyer: CompanySale.PlayerBuyer, price: Double) -> Bool {
        var ok = false
        update { s, _, ctx in ok = CompanySale.addPlayerOffer(&s, companyID: companyID, buyer: buyer, price: price, context: ctx) }
        return ok
    }

    func playerCompanyBuyPlan(_ l: PlayerDeals.CompanyListing, price: Double) -> PlayerDeals.BuyPlan? { PlayerDeals.buyPlan(state, listing: l, price: price, data: data) }

    @discardableResult
    mutating func buyPlayerCompany(_ l: PlayerDeals.CompanyListing, price: Double, buyerLinkKeys: Set<String>) -> PlayerDeals.BuyResult {
        var r = PlayerDeals.BuyResult.notAllowed("")
        update { s, d, ctx in r = PlayerDeals.buy(&s, listing: l, price: price, buyerLinkKeys: buyerLinkKeys, data: d, context: ctx) }
        return r
    }
}
