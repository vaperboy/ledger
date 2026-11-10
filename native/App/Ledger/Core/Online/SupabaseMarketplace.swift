import Foundation
import GameCore

extension SupabaseOnlineService {
    func marketBrowse(kind: String?) async throws -> [PlayerListing] {
        var params: [String: Any] = ["p_limit": 80]
        if let kind { params["p_kind"] = kind }
        return try decode([PlayerListing].self, try await rpcData("market_browse", params))
    }

    func marketMine() async throws -> MarketState { try decode(MarketState.self, try await rpcData("market_mine")) }

    func marketList(item: JSONValue, price: Double, currency: String) async throws -> PlayerListing {
        let obj: Any = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(item), options: [.fragmentsAllowed])
        return try decode(PlayerListing.self, try await rpcData("market_list", ["p_item": obj, "p_price": price, "p_currency": currency]))
    }

    func marketCancel(listingID: String) async throws { _ = try await rpcData("market_cancel", ["p_listing": listingID]) }

    func marketBuy(listingID: String) async throws -> MarketDeal {
        try decode(MarketDeal.self, try await rpcData("market_buy", ["p_listing": listingID]))
    }

    func marketOffer(listingID: String, price: Double) async throws -> MarketDeal {
        try decode(MarketDeal.self, try await rpcData("market_offer", ["p_listing": listingID, "p_price": price]))
    }

    func marketRespond(dealID: String, reply: MarketReply, price: Double?) async throws -> MarketResult {
        var params: [String: Any] = ["p_deal": dealID, "p_action": reply.rawValue]
        if let price { params["p_price"] = price }
        return try decode(MarketResult.self, try await rpcData("market_respond", params))
    }

    func marketAnswer(dealID: String, accept: Bool) async throws -> MarketResult {
        try decode(MarketResult.self, try await rpcData("market_answer", ["p_deal": dealID, "p_accept": accept]))
    }

    func marketWithdraw(dealID: String) async throws -> MarketResult {
        try decode(MarketResult.self, try await rpcData("market_withdraw", ["p_deal": dealID]))
    }
}
