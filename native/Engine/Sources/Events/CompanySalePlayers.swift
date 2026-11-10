import Foundation
import GameCore
import Finance
import Businesses

extension CompanySale {
    public struct PlayerBuyer: Equatable, Sendable {
        public var name: String
        public var profileCode: String
        public init(name: String, profileCode: String) { self.name = name; self.profileCode = profileCode }
    }

    @discardableResult
    public static func startPlayerListing(_ s: inout GameState, companyID: Int, days: Int) -> Bool {
        guard PlayerDeals.offerDays.contains(days) else { return false }
        if !SaleListings.isListed(s, companyID: companyID) {
            guard SaleListings.start(&s, companyID: companyID, route: "private", pct: 100) else { return false }
        }
        return PlayerDeals.showToPlayers(&s, companyID: companyID, days: days)
    }

    @discardableResult
    public static func addPlayerOffer(_ s: inout GameState, companyID: Int, buyer: PlayerBuyer, price: Double, context fc: FinanceContext) -> Bool {
        guard price.isFinite, price > 0, !buyer.name.isEmpty, let until = PlayerDeals.playerListingUntil(s, companyID: companyID), until >= PlayerDeals.today(s),
              let i = s.companyIndex(companyID), s.companies[i].status.isLive else { return false }
        var list = s.rest["sales"]?.array ?? []
        guard let k = list.firstIndex(where: { $0["co"].int == companyID }) else { return false }
        var offers = list[k]["offers"].array.filter { s.week < $0["exp"].int }
        guard offers.count < 6, !offers.contains(where: { $0["pcode"].string == buyer.profileCode }) else { return false }
        let name = buyer.name + " (player)"
        let rounded = (price / 1000).rounded() * 1000
        offers.append(.object(["id": .number(Double(s.makeID())), "k": .string("player"), "name": .string(name), "price": .number(rounded), "note": .string(notes["player"] ?? ""),
                               "exp": .number(Double(s.week + 2)), "ctr": .number(0), "pcode": .string(buyer.profileCode)]))
        list[k]["offers"] = .array(offers)
        write(&s, list)
        let co = s.companies[i]
        s.addMessage(from: name, title: "Offer for \(co.name)", body: "\(name) offers \(fc.currency(co.countryCode, s).display(rounded * co.ownership / 100)) for your stake. The offer stands for two weeks.",
                     companyID: co.id, tone: "good")
        return true
    }
}
