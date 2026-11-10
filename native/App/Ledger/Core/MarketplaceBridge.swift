import Foundation
import GameCore
import Businesses
import Simulation

enum MarketplaceBridge {
    static func listings(_ e: GameEngine, companyID: Int) -> [MarketListing] {
        e.marketplaceListings(forCompany: companyID)
    }

    static func begin(_ e: inout GameEngine, listingID: String, companyID: Int) -> MarketNegotiation? {
        e.beginNegotiation(listingID: listingID, companyID: companyID)
    }

    static func push(_ e: inout GameEngine, listingID: String, companyID: Int) -> MarketNegotiation {
        e.pushPrice(listingID: listingID, companyID: companyID)
    }

    static func buy(_ e: inout GameEngine, listingID: String, companyID: Int, price: Double) -> SettingResult {
        e.buyListing(listingID: listingID, companyID: companyID, price: price)
    }

    private static func liveCompanyIDs(_ e: GameEngine) -> [Int] {
        e.state.companies.filter { (c: Company) -> Bool in c.status.isLive }.map { (c: Company) -> Int in c.id }
    }

    static func newestDay(_ e: GameEngine, after day: Int) -> Set<String> {
        var out: Set<String> = []
        for id in liveCompanyIDs(e) {
            for l in listings(e, companyID: id) where l.postedDay > day { out.insert(l.id) }
        }
        return out
    }

    static func newestPostedDay(_ e: GameEngine) -> Int {
        var best: Int = 0
        for id in liveCompanyIDs(e) {
            for l in listings(e, companyID: id) where l.postedDay > best { best = l.postedDay }
        }
        return best
    }
}

extension GameStore {
    func marketBegin(listingID: String, companyID: Int) -> MarketNegotiation? {
        var out: MarketNegotiation? = nil
        act { (e: inout GameEngine) -> Void in out = MarketplaceBridge.begin(&e, listingID: listingID, companyID: companyID) }
        return out
    }

    func marketPush(listingID: String, companyID: Int) -> MarketNegotiation? {
        var out: MarketNegotiation? = nil
        act { (e: inout GameEngine) -> Void in out = MarketplaceBridge.push(&e, listingID: listingID, companyID: companyID) }
        return out
    }

    func marketBuy(listingID: String, companyID: Int, price: Double) -> SettingResult {
        var out: SettingResult = .refused("Not available right now.")
        act { (e: inout GameEngine) -> Void in out = MarketplaceBridge.buy(&e, listingID: listingID, companyID: companyID, price: price) }
        return out
    }

    func marketRefused(listingID: String, companyID: Int) -> Bool {
        guard let n = marketBegin(listingID: listingID, companyID: companyID) else { return true }
        return n.mood == .refusing && !n.canDiscuss
    }
}
