import Foundation
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
