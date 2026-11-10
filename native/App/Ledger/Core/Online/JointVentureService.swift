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
    struct Item: Sendable { var id: Int; var kind: JVRules.Kind }
    struct Partner: Sendable { var memberID: String; var name: String }
    var companyID: Int
    var meetingID: Int
    var week: Int
    var opened: Int
    var deadline: Int
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
    func emergency(companyID: Int, week: Int, profitable: Bool, cashTight: Bool, partners: [JVVoteQuery.Partner]) async -> JVEmergency?
    func offers(for friendID: String) async -> [JVOffer]
}
