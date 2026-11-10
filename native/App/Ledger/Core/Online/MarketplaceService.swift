import Foundation
import GameCore

struct PlayerListing: Decodable, Equatable, Identifiable, Sendable {
    var id: String
    var sellerID: String
    var sellerName: String
    var sellerCode: String?
    var avatarColour: Int?
    var avatarIcon: String?
    var sellerCountry: String?
    var sellerLevel: Int?
    var sellerOnline: Bool
    var sellerLastSeen: Double?
    var kind: String
    var title: String
    var item: JSONValue
    var price: Double
    var currency: String
    var status: String
    var postedAt: Double
    var mine: Bool
    var offerUsed: Bool
    var myDeal: MarketDeal?

    var family: String { item["family"].string }
    var itemID: String { item["id"].string }
    var openDeal: MarketDeal? { myDeal.flatMap { (d: MarketDeal) -> MarketDeal? in d.isOpen ? d : nil } }
}

struct MarketDeal: Decodable, Equatable, Identifiable, Sendable {
    var id: String
    var listingID: String
    var role: String
    var kind: String
    var price: Double
    var specialPrice: Double?
    var finalPrice: Double?
    var status: String
    var title: String
    var itemKind: String
    var family: String?
    var currency: String
    var listingPrice: Double
    var listingStatus: String
    var otherID: String
    var otherName: String
    var otherCode: String?
    var otherOnline: Bool
    var createdAt: Double
    var answeredAt: Double?

    var isOpen: Bool { status == "pending" || status == "discussing" }
    var isBuyer: Bool { role == "buyer" }
    var statusText: String {
        switch status {
        case "pending": return isBuyer ? "Waiting for \(otherName)" : "Waiting for you"
        case "discussing": return isBuyer ? "\(otherName) made you a price" : "Waiting for \(otherName)"
        case "accepted": return "Done"
        case "declined": return "Declined"
        case "withdrawn": return "Withdrawn"
        case "expired": return "Expired"
        default: return "Closed"
        }
    }
}

struct MarketResult: Decodable, Equatable, Sendable {
    var status: String
    var dealID: String
    var price: Double?
    var specialPrice: Double?
}

struct MarketState: Decodable, Equatable, Sendable {
    var listings: [PlayerListing]
    var incoming: [MarketDeal]
    var outgoing: [MarketDeal]
    static let empty = MarketState(listings: [], incoming: [], outgoing: [])
}

enum MarketReply: String, Sendable { case accept, decline, discuss }

protocol MarketplaceService: Sendable {
    func marketBrowse(kind: String?) async throws -> [PlayerListing]
    func marketMine() async throws -> MarketState
    func marketList(item: JSONValue, price: Double, currency: String) async throws -> PlayerListing
    func marketCancel(listingID: String) async throws
    func marketBuy(listingID: String) async throws -> MarketDeal
    func marketOffer(listingID: String, price: Double) async throws -> MarketDeal
    func marketRespond(dealID: String, reply: MarketReply, price: Double?) async throws -> MarketResult
    func marketAnswer(dealID: String, accept: Bool) async throws -> MarketResult
    func marketWithdraw(dealID: String) async throws -> MarketResult
}

extension MarketplaceService {
    func marketBrowse(kind: String?) async throws -> [PlayerListing] { [] }
    func marketMine() async throws -> MarketState { .empty }
    func marketList(item: JSONValue, price: Double, currency: String) async throws -> PlayerListing { throw OnlineError.notSignedIn }
    func marketCancel(listingID: String) async throws { throw OnlineError.notSignedIn }
    func marketBuy(listingID: String) async throws -> MarketDeal { throw OnlineError.notSignedIn }
    func marketOffer(listingID: String, price: Double) async throws -> MarketDeal { throw OnlineError.notSignedIn }
    func marketRespond(dealID: String, reply: MarketReply, price: Double?) async throws -> MarketResult { throw OnlineError.notSignedIn }
    func marketAnswer(dealID: String, accept: Bool) async throws -> MarketResult { throw OnlineError.notSignedIn }
    func marketWithdraw(dealID: String) async throws -> MarketResult { throw OnlineError.notSignedIn }
}
