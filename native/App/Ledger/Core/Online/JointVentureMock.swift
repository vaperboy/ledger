import Foundation
import GameCore
import Events

final class MockJointVentureService: JointVentureService, @unchecked Sendable {
    private let online: any OnlineService
    private static let sentKey = "jv.sent.v1"

    init(online: any OnlineService) { self.online = online }

    func invitable() async -> [PlayerProfile] {
        if let overview = try? await online.friends(), !overview.friends.isEmpty { return overview.friends }
        let sample: [PlayerProfile] = OnlineDirectoryCache.players.filter { $0.relation != .you && $0.relation != .blocked }
        return Array(sample.prefix(12))
    }

    func send(_ offer: JVOffer) async {
        guard let mock = online as? MockOnlineService else { return }
        var all: [String: [JVOffer]] = [:]
        if let data = await mock.extensionData(for: Self.sentKey), let saved = try? JSONDecoder().decode([String: [JVOffer]].self, from: data) { all = saved }
        var mine: [JVOffer] = (all[offer.friendID] ?? []).filter { $0.id != offer.id }
        mine.append(offer)
        all[offer.friendID] = Array(mine.suffix(10))
        await mock.setExtensionData(try? JSONEncoder().encode(all), for: Self.sentKey)
    }

    func offers(for friendID: String) async -> [JVOffer] {
        guard let mock = online as? MockOnlineService, let data = await mock.extensionData(for: Self.sentKey),
              let all = try? JSONDecoder().decode([String: [JVOffer]].self, from: data) else { return [] }
        return all[friendID] ?? []
    }

    func reply(to offer: JVOffer, week: Int) async -> JVReply? {
        let delay: Int = 1 + Int(HashedRandom.first("jvdelay:" + offer.id) * 3)
        guard week >= offer.sentWeek + delay else { return nil }
        let ratio: Double = offer.fair > 0 ? offer.price / offer.fair : 1
        let chance: Double = min(0.95, max(0.25, 1.15 - ratio * 0.35))
        return HashedRandom.first("jvreply:" + offer.id) < chance ? .accepted : .declined
    }

    func emergency(companyID: Int, week: Int, profitable: Bool, cashTight: Bool, partners: [JVVoteQuery.Partner]) async -> JVEmergency? {
        guard !partners.isEmpty, HashedRandom.first("jvcall:\(companyID):\(week)") < 0.06 else { return nil }
        let who: JVVoteQuery.Partner = partners[Int(HashedRandom.first("jvwho:\(companyID):\(week)") * Double(partners.count)) % partners.count]
        if !profitable { return JVEmergency(memberID: who.memberID, kind: .price, reason: "Sales are falling, prices should come down") }
        return JVEmergency(memberID: who.memberID, kind: .dividend, reason: "The company is making money, time to share some")
    }

    func votes(_ q: JVVoteQuery) async -> [JVCastVote] {
        var out: [JVCastVote] = []
        for p in q.partners {
            for item in q.items {
                let seed: String = "\(q.companyID):\(q.meetingID):\(item.id):\(p.memberID)"
                let when: Int = JVRules.mockVoteWeek(opened: q.opened, deadline: q.deadline, seed: seed)
                guard when <= q.week, when <= q.deadline else { continue }
                out.append(JVCastVote(itemID: item.id, memberID: p.memberID, choice: JVRules.mockChoice(item.kind, profitable: q.profitable, cashTight: q.cashTight, seed: seed)))
            }
        }
        return out
    }
}
