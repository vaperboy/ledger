import Foundation
import GameCore

extension SupabaseOnlineService: VentureBoardService {
    func ventures() async throws -> [VentureInfo] { try decode([VentureInfo].self, try await rpcData("my_ventures")) }

    func createVenture(companyKey: String, name: String, value: Double, currency: String) async throws -> VentureInfo {
        try decode(VentureInfo.self, try await rpcData("create_venture", ["p_company_key": companyKey, "p_name": name, "p_value": value, "p_currency": currency]))
    }

    func reportVentureValue(ventureID: String, value: Double) async throws {
        _ = try await rpcData("report_venture_value", ["p_venture": ventureID, "p_value": value])
    }

    func inviteVenturePartner(ventureID: String, friendID: String, pct: Double, price: Double) async throws -> VentureCreated {
        try decode(VentureCreated.self, try await rpcData("invite_venture_partner", ["p_venture": ventureID, "p_friend": friendID, "p_pct": pct, "p_price": price]))
    }

    // Every invitation this company has sent, newest first, with how each one ended.
    func ventureInvitesSent(ventureID: String) async throws -> [VentureInviteRow] {
        let query: [URLQueryItem] = [URLQueryItem(name: "venture_id", value: "eq." + ventureID), URLQueryItem(name: "select", value: "id,invitee_id,pct,price,status"),
                                     URLQueryItem(name: "order", value: "sent_at.desc"), URLQueryItem(name: "limit", value: "60")]
        return try decode([VentureInviteRow].self, try await tableData("venture_invites", query: query))
    }

    func ventureOffers() async throws -> [VentureOffer] { try decode([VentureOffer].self, try await rpcData("my_venture_offers")) }

    func replyToVentureOffer(inviteID: String, accept: Bool, currency: String) async throws {
        _ = try await rpcData("reply_to_venture_offer", ["p_invite": inviteID, "p_accept": accept, "p_currency": currency])
    }

    func ventureMeeting(id: String) async throws -> VentureMeetingInfo {
        try decode(VentureMeetingInfo.self, try await rpcData("venture_meeting", ["p_meeting": id]))
    }

    func proposeVentureChange(ventureID: String, kind: String, params: JSONValue, now: Bool, profitable: Bool, cashTight: Bool) async throws -> VentureProposeResult {
        let obj: Any = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(params), options: [.fragmentsAllowed])
        let args: [String: Any] = ["p_venture": ventureID, "p_kind": kind, "p_params": obj, "p_now": now, "p_profitable": profitable, "p_cash_tight": cashTight]
        return try decode(VentureProposeResult.self, try await rpcData("propose_venture_change", args))
    }

    func castVentureVote(itemID: String, choice: String) async throws {
        _ = try await rpcData("cast_venture_vote", ["p_item": itemID, "p_choice": choice])
    }

    func closeVentureMeeting(id: String) async throws { _ = try await rpcData("close_venture_meeting", ["p_meeting": id]) }

    func offerVentureBuyback(ventureID: String, partnerID: String, price: Double) async throws -> VentureCreated {
        try decode(VentureCreated.self, try await rpcData("offer_venture_buyback", ["p_venture": ventureID, "p_partner": partnerID, "p_price": price]))
    }

    func requestVentureExit(ventureID: String, price: Double) async throws -> VentureCreated {
        try decode(VentureCreated.self, try await rpcData("request_venture_exit", ["p_venture": ventureID, "p_price": price]))
    }

    func replyToVentureBuyback(offerID: String, accept: Bool) async throws {
        _ = try await rpcData("reply_to_venture_buyback", ["p_offer": offerID, "p_accept": accept])
    }

    func withdrawVentureBuyback(offerID: String) async throws { _ = try await rpcData("withdraw_venture_buyback", ["p_offer": offerID]) }

    func ventureBuybacks() async throws -> VentureBuybacks { try decode(VentureBuybacks.self, try await rpcData("my_venture_buybacks")) }

    // Shares that went back to the owner in this company, newest first, with the price paid.
    func ventureSharesSold(ventureID: String) async throws -> [VentureBuybackRow] {
        let query: [URLQueryItem] = [URLQueryItem(name: "venture_id", value: "eq." + ventureID), URLQueryItem(name: "status", value: "eq.accepted"),
                                     URLQueryItem(name: "select", value: "id,seller_id,price,status"), URLQueryItem(name: "order", value: "answered_at.desc"),
                                     URLQueryItem(name: "limit", value: "40")]
        return try decode([VentureBuybackRow].self, try await tableData("venture_buybacks", query: query))
    }

    func payVentureDividend(ventureID: String, amount: Double, ref: String) async throws {
        _ = try await rpcData("pay_venture_dividend", ["p_venture": ventureID, "p_amount": amount, "p_ref": ref])
    }
}
