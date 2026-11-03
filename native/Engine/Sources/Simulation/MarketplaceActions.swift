import Foundation
import GameCore
import Businesses

/// The Marketplace (Phone app): used cars, vans, equipment and furniture for sale, haggling with the seller, buying, and the used car dealer's yard.
public extension GameEngine {
    /// The live listings for this company: about 30 to 60, refreshed weekly (see `Marketplace`).
    func marketplaceListings(forCompany companyID: Int) -> [MarketListing] {
        Marketplace.listings(state, companyID: companyID, data: data)
    }

    /// Start (or pick up) the talk with the seller. nil when the listing is gone or the seller will not deal with this company.
    @discardableResult
    mutating func beginNegotiation(listingID: String, companyID: Int) -> MarketNegotiation? {
        var r: MarketNegotiation?
        update { s, d, _ in r = Marketplace.begin(&s, listingID: listingID, companyID: companyID, data: d) }
        return r
    }

    /// Ask for a lower price. Costs patience; at 0 the seller gives up, and pushing a seller who has given up closes the listing to this company.
    @discardableResult
    mutating func pushPrice(listingID: String, companyID: Int) -> MarketNegotiation {
        var r = MarketNegotiation(listingID: listingID, price: 0, canDiscuss: false, patienceLeft: 0, mood: .refusing, lastMessage: "")
        update { s, d, _ in r = Marketplace.push(&s, listingID: listingID, companyID: companyID, data: d) }
        return r
    }

    /// Buy at `price` (not below the price agreed so far). Equipment and vehicles go to the company's items; cars and vans go into a used car dealer's yard.
    @discardableResult
    mutating func buyListing(listingID: String, companyID: Int, price: Double) -> SettingResult {
        var result: Marketplace.BuyResult = .refused("That listing is gone.")
        update { s, d, _ in result = Marketplace.buy(&s, listingID: listingID, companyID: companyID, price: price, data: d) }
        if case .refused(let why) = result { return .refused(why) }
        return .applied
    }

    /// What the seller left out, only after the purchase (also sent to the inbox).
    func listingReveal(listingID: String, companyID: Int) -> String? {
        Marketplace.reveal(state, listingID: listingID, companyID: companyID)
    }

    // MARK: Used car dealer

    /// The dealer's own price for used cars: a markup on cost, in percent (default 12).
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

    /// The cars in the yard.
    func usedCarStock(companyID: Int) -> [UsedCarStockItem] {
        state.company(companyID).map { UsedCarDealer.stockItems($0, week: state.week) } ?? []
    }
}
