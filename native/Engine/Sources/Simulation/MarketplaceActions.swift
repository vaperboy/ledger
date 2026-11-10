import Foundation
import GameCore
import Businesses

public extension GameEngine {
    func marketplaceListings(forCompany companyID: Int) -> [MarketListing] {
        Marketplace.listings(state, companyID: companyID, data: data)
    }

    @discardableResult
    mutating func beginNegotiation(listingID: String, companyID: Int) -> MarketNegotiation? {
        var r: MarketNegotiation?
        update { s, d, _ in r = Marketplace.begin(&s, listingID: listingID, companyID: companyID, data: d) }
        return r
    }

    @discardableResult
    mutating func pushPrice(listingID: String, companyID: Int) -> MarketNegotiation {
        var r = MarketNegotiation(listingID: listingID, price: 0, canDiscuss: false, patienceLeft: 0, mood: .refusing, lastMessage: "")
        update { s, d, _ in r = Marketplace.push(&s, listingID: listingID, companyID: companyID, data: d) }
        return r
    }

    @discardableResult
    mutating func buyListing(listingID: String, companyID: Int, price: Double) -> SettingResult {
        var result: Marketplace.BuyResult = .refused("That listing is gone.")
        update { s, d, _ in result = Marketplace.buy(&s, listingID: listingID, companyID: companyID, price: price, data: d) }
        if case .refused(let why) = result { return .refused(why) }
        return .applied
    }

    func listingReveal(listingID: String, companyID: Int) -> String? {
        Marketplace.reveal(state, listingID: listingID, companyID: companyID)
    }

    @discardableResult
    mutating func setUsedCarMarkup(companyID: Int, percent: Double) -> SettingResult {
        var ok = false
        let before = state.company(companyID).map { UsedCarDealer.markup($0) }
        update { s, _, _ in ok = UsedCarDealer.setMarkup(&s, companyID: companyID, percent: percent) }
        if !ok { return .refused("Only a used car dealer sets a markup, between -50 and 300 percent.") }
        return before == percent ? .unchanged : .applied
    }

    func usedCarMarkup(companyID: Int) -> Double? {
        state.company(companyID).flatMap { $0.type == UsedCarDealer.tradeID ? UsedCarDealer.markup($0) : nil }
    }

    func usedCarStock(companyID: Int) -> [UsedCarStockItem] {
        state.company(companyID).map { UsedCarDealer.stockItems($0, week: state.week) } ?? []
    }
}
