import Foundation
import Events

// The online side of joint ventures, as the app sees it: who can be invited, the private offer each friend gets, their answer, and the votes
// partners cast. The game (JointVenture, JVRules) keeps the truth; this only carries messages. `MockJointVentureService` stands in for the
// server with the sample players until one exists.

/// What one invited friend is shown. The price is theirs alone: another friend's offer is never part of it.
struct JVOffer: Codable, Equatable, Sendable {
    var companyID: Int
    var inviteID: Int
    var companyName: String
    var friendID: String
    var friendName: String
    var pct: Double
    var price: Double
    /// What the shares are worth at the company's real value; the answer leans on how far the price is from it.
    var fair: Double
    /// "If you join, this will happen": share, cost, lock-up, voting power, dividend rule.
    var lines: [String]
    var sentWeek: Int
    var id: String { "\(companyID)-\(inviteID)" }
}

enum JVReply: Equatable, Sendable {
    case accepted
    case declined
}

/// The facts a partner's vote leans on, and the window it must be cast in.
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

/// A partner who wants a meeting now, and about what.
struct JVEmergency: Equatable, Sendable {
    var memberID: String
    var kind: JVRules.Kind
    var reason: String
}

protocol JointVentureService: Sendable {
    /// Friends the player can invite; sample players when there are none yet.
    func invitable() async -> [PlayerProfile]
    /// Delivers a private offer to one friend.
    func send(_ offer: JVOffer) async
    /// The friend's answer by game week; nil while they have not answered.
    func reply(to offer: JVOffer, week: Int) async -> JVReply?
    /// Votes the partners have cast up to `query.week`. A vote that comes after the deadline is never returned: it counts as an abstention.
    func votes(_ query: JVVoteQuery) async -> [JVCastVote]
    /// Whether a partner calls an emergency meeting this week (rarely, and only when nothing else is open).
    func emergency(companyID: Int, week: Int, profitable: Bool, cashTight: Bool, partners: [JVVoteQuery.Partner]) async -> JVEmergency?
    /// What one friend has been offered (their own offers only).
    func offers(for friendID: String) async -> [JVOffer]
}
