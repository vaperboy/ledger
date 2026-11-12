import Foundation
import GameCore
import Events

struct JVOffer: Codable, Equatable, Sendable {
    var companyID: Int
    var inviteID: Int
    var companyName: String
    var friendID: String
    var friendName: String
    var pct: Double
    var price: Double
    var fair: Double
    var lines: [String]
    var sentWeek: Int
    var id: String { "\(companyID)-\(inviteID)" }
}

enum JVReply: Equatable, Sendable {
    case accepted
    case declined
}

struct JVVoteQuery: Sendable {
    struct Item: Sendable { var id: Int; var kind: JVRules.Kind; var raises: Bool = true }
    struct Partner: Sendable { var memberID: String; var name: String }
    var companyID: Int
    var meetingID: Int
    var now: Double
    var opened: Double
    var closes: Double
    var profitable: Bool
    var cashTight: Bool
    var items: [Item]
    var partners: [Partner]
}

struct JVCastVote: Equatable, Sendable {
    var itemID: Int
    var memberID: String
    var choice: JVRules.Choice
}

struct JVBuybackQuery: Sendable {
    var companyID: Int
    var offerID: Int
    var memberID: String
    var price: Double
    var fair: Double
    var sentAt: Double
    var now: Double
}

struct JVEmergency: Equatable, Sendable {
    var memberID: String
    var kind: JVRules.Kind
    var reason: String
}

protocol JointVentureService: Sendable {
    func invitable() async -> [PlayerProfile]
    func send(_ offer: JVOffer) async
    func reply(to offer: JVOffer, week: Int) async -> JVReply?
    func votes(_ query: JVVoteQuery) async -> [JVCastVote]
    func buybackReply(_ query: JVBuybackQuery) async -> JVReply?
    func emergency(companyID: Int, week: Int, profitable: Bool, cashTight: Bool, partners: [JVVoteQuery.Partner]) async -> JVEmergency?
    func offers(for friendID: String) async -> [JVOffer]
}

// What the game server holds for a company that real players own together.
struct VenturePartner: Decodable, Equatable, Sendable {
    var memberID: String
    var name: String?
    var shares: Int
    var percent: Double?
    var lockUntil: Date?
}

struct VentureInfo: Decodable, Equatable, Identifiable, Sendable {
    var id: String
    var chairID: String
    var chairName: String?
    var companyKey: String
    var name: String
    var currency: String
    var value: Double
    var totalShares: Int
    var isChair: Bool
    var dividendPolicy: String?
    var nextMeetingAt: Date?
    var partners: [VenturePartner]
    var openMeetings: [String]?

    func partner(_ id: String?) -> VenturePartner? { partners.first { (p: VenturePartner) -> Bool in p.memberID == id } }
}

struct VentureVote: Decodable, Equatable, Sendable {
    var memberID: String
    var name: String?
    var choice: String
}

struct VentureMeetingItem: Decodable, Equatable, Identifiable, Sendable {
    var id: String
    var kind: String
    var title: String?
    var params: JSONValue
    var proposedBy: String?
    var outcome: String?
    var myVote: String?
    var yesShares: Double?
    var noShares: Double?
    var votes: [VentureVote]?

    // The proposer's own number for the item, so a company can find its item again on the server.
    var ref: String { params["ref"].string }
}

struct VentureMeetingInfo: Decodable, Equatable, Identifiable, Sendable {
    var id: String
    var ventureID: String
    var planned: Bool
    var calledBy: String?
    var deadline: Date
    var closedAt: Date?
    var totalShares: Double?
    var items: [VentureMeetingItem]
}

struct VentureOffer: Decodable, Equatable, Identifiable, Sendable {
    var id: String
    var ventureID: String
    var companyName: String
    var chairID: String
    var chairName: String?
    var pct: Double
    var price: Double
    var fair: Double
    var currency: String
    var expiresAt: Date
    var lockWeeks: Int?
}

struct VentureBuyback: Decodable, Equatable, Identifiable, Sendable {
    var id: String
    var ventureID: String
    var companyName: String
    var buyerID: String
    var buyerName: String?
    var sellerID: String
    var sellerName: String?
    var shares: Int
    var percent: Double?
    var price: Double
    var fair: Double
    var currency: String
    var status: String
    var proposedBy: String
    var expiresAt: Date
}

struct VentureBuybacks: Decodable, Equatable, Sendable {
    var incoming: [VentureBuyback]
    var outgoing: [VentureBuyback]
    static let empty = VentureBuybacks(incoming: [], outgoing: [])
}

struct VentureProposeResult: Decodable, Equatable, Sendable {
    var applied: Bool
    var meetingID: String?
    var deadline: Date?
}

struct VentureCreated: Decodable, Equatable, Sendable {
    var id: String
}

struct VentureInviteRow: Decodable, Equatable, Sendable {
    var id: String
    var inviteeID: String
    var pct: Double
    var price: Double
    var status: String
    enum CodingKeys: String, CodingKey { case id, inviteeID = "invitee_id", pct, price, status }
}

struct VentureBuybackRow: Decodable, Equatable, Sendable {
    var id: String
    var sellerID: String
    var price: Double
    var status: String
    enum CodingKeys: String, CodingKey { case id, sellerID = "seller_id", price, status }
}

// The server's side of shared companies: invitations, the board, and offers for shares between real players.
protocol VentureBoardService: Sendable {
    func ventures() async throws -> [VentureInfo]
    func createVenture(companyKey: String, name: String, value: Double, currency: String) async throws -> VentureInfo
    func reportVentureValue(ventureID: String, value: Double) async throws
    func inviteVenturePartner(ventureID: String, friendID: String, pct: Double, price: Double) async throws -> VentureCreated
    func ventureInvitesSent(ventureID: String) async throws -> [VentureInviteRow]
    func ventureOffers() async throws -> [VentureOffer]
    func replyToVentureOffer(inviteID: String, accept: Bool, currency: String) async throws
    func ventureMeeting(id: String) async throws -> VentureMeetingInfo
    func proposeVentureChange(ventureID: String, kind: String, params: JSONValue, now: Bool, profitable: Bool, cashTight: Bool) async throws -> VentureProposeResult
    func castVentureVote(itemID: String, choice: String) async throws
    func closeVentureMeeting(id: String) async throws
    func offerVentureBuyback(ventureID: String, partnerID: String, price: Double) async throws -> VentureCreated
    func requestVentureExit(ventureID: String, price: Double) async throws -> VentureCreated
    func replyToVentureBuyback(offerID: String, accept: Bool) async throws
    func withdrawVentureBuyback(offerID: String) async throws
    func ventureBuybacks() async throws -> VentureBuybacks
    func ventureSharesSold(ventureID: String) async throws -> [VentureBuybackRow]
    func payVentureDividend(ventureID: String, amount: Double, ref: String) async throws
}
