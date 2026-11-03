import Foundation
import GameCore
import Businesses
import Simulation

/// The one place the app talks to the engine's used-goods marketplace. A signature change in the engine is fixed here only.
enum MarketplaceBridge {
    static func listings(_ e: GameEngine, companyID: Int) -> [MarketListing] {
        e.marketplaceListings(forCompany: companyID)
    }

    /// Opens (or resumes) the price talk. Nil: the seller will not deal with this company.
    static func begin(_ e: inout GameEngine, listingID: String, companyID: Int) -> Negotiation? {
        e.beginNegotiation(listingID: listingID, companyID: companyID)
    }

    /// Pushes for a lower price; the seller answers with a new state.
    static func push(_ e: inout GameEngine, listingID: String, companyID: Int) -> Negotiation {
        e.pushPrice(listingID: listingID, companyID: companyID)
    }

    static func buy(_ e: inout GameEngine, listingID: String, companyID: Int, price: Double) -> SettingResult {
        e.buyListing(listingID: listingID, companyID: companyID, price: price)
    }

    private static func liveCompanyIDs(_ e: GameEngine) -> [Int] {
        e.state.companies.filter { (c: Company) -> Bool in c.status.isLive }.map { (c: Company) -> Int in c.id }
    }

    /// Distinct listings over every live company that were posted after `day`.
    static func newestDay(_ e: GameEngine, after day: Int) -> Set<String> {
        var out: Set<String> = []
        for id in liveCompanyIDs(e) {
            for l in listings(e, companyID: id) where l.postedDay > day { out.insert(l.id) }
        }
        return out
    }

    /// The day of the newest listing over every live company (0 when there is none).
    static func newestPostedDay(_ e: GameEngine) -> Int {
        var best: Int = 0
        for id in liveCompanyIDs(e) {
            for l in listings(e, companyID: id) where l.postedDay > best { best = l.postedDay }
        }
        return best
    }
}

extension GameStore {
    /// Opens the price talk on a listing and saves. Nil: the seller already refused this company.
    func marketBegin(listingID: String, companyID: Int) -> Negotiation? {
        var out: Negotiation? = nil
        act { (e: inout GameEngine) -> Void in out = MarketplaceBridge.begin(&e, listingID: listingID, companyID: companyID) }
        return out
    }

    /// One push for a lower price, saved. Nil only when there is no engine.
    func marketPush(listingID: String, companyID: Int) -> Negotiation? {
        var out: Negotiation? = nil
        act { (e: inout GameEngine) -> Void in out = MarketplaceBridge.push(&e, listingID: listingID, companyID: companyID) }
        return out
    }

    func marketBuy(listingID: String, companyID: Int, price: Double) -> SettingResult {
        var out: SettingResult = .refused("Not available right now.")
        act { (e: inout GameEngine) -> Void in out = MarketplaceBridge.buy(&e, listingID: listingID, companyID: companyID, price: price) }
        return out
    }

    /// True when the seller already refused this company.
    func marketRefused(listingID: String, companyID: Int) -> Bool {
        guard let n = marketBegin(listingID: listingID, companyID: companyID) else { return true }
        return n.mood == .refusing && !n.canDiscuss
    }
}
