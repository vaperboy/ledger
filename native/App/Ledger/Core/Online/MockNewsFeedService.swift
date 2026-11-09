import Foundation
import Businesses

/// The stand-in for the news side of the server: every six hours each sample player may have something to tell, drawn from their own sample
/// data (their companies, level and trades). The same six-hour slot always gives the same events. Only Public and Friends-level players
/// produce events, and the Friends-level ones reach friends alone.
final class MockNewsFeedService: NewsFeedService {
    private static let slotSeconds: TimeInterval = 6 * 3600
    private static let slotsShown = 24

    private func directory() -> [PlayerProfile] {
        OnlineDirectoryCache.players.isEmpty ? SampleRoster.players() : OnlineDirectoryCache.players
    }

    func isFriend(_ playerID: String) -> Bool { directory().first { $0.id == playerID }?.relation == .friend }

    func events(now: Date) async -> [PlayerEvent] {
        let roster: [PlayerProfile] = SampleRoster.players().filter { $0.privacy != .onlyMe }
        guard !roster.isEmpty else { return [] }
        let friends: Set<String> = Set(directory().filter { $0.relation == .friend }.map { $0.id })
        let blocked: Set<String> = Set(directory().filter { $0.relation == .blocked }.map { $0.id })
        let current: Int = Int(now.timeIntervalSince1970 / Self.slotSeconds)
        var out: [PlayerEvent] = []
        for slot in stride(from: current, to: current - Self.slotsShown, by: -1) {
            var s = SampleRoster.Stream("news:\(slot)")
            let count: Int = 1 + s.next(2)
            for k in 0..<count {
                let player: PlayerProfile = roster[s.next(roster.count)]
                guard let e = event(slot: slot, k: k, player: player, roster: roster, stream: &s) else { continue }
                guard !blocked.contains(player.id), PlayerNewsRules.canSee(e, viewerIsFriend: friends.contains(player.id)) else { continue }
                out.append(e)
            }
        }
        return out.sorted { $0.day != $1.day ? $0.day > $1.day : $0.id > $1.id }
    }

    private func event(slot: Int, k: Int, player p: PlayerProfile, roster: [PlayerProfile], stream s: inout SampleRoster.Stream) -> PlayerEvent? {
        guard let co = p.companies?.first else { return nil }
        let kinds: [PlayerEventKind] = PlayerEventKind.allCases
        let kind: PlayerEventKind = kinds[s.next(kinds.count)]
        let day: Int = Int(Double(slot) * Self.slotSeconds / 86_400)
        var e = PlayerEvent(id: "ev.\(slot).\(k)", kind: kind, playerID: p.id, playerName: p.displayName, countryCode: p.countryCode,
                            audience: p.privacy == .everyone ? .everyone : .friends, day: day, trade: co.trade, city: co.city, company: co.name)
        switch kind {
        case .branchMilestone: e.count = 3 + s.next(8)
        case .wentViral: break
        case .supplierMilestone: e.count = (1 + s.next(9)) * 500
        case .acquisition:
            // The company bought is one a Public player has chosen to show.
            let others: [PlayerProfile] = roster.filter { $0.id != p.id && $0.privacy == .everyone }
            guard !others.isEmpty, let bought = others[s.next(others.count)].companies?.first else { return nil }
            e.otherName = bought.name
        case .newAssociation: e.club = AssociationCatalogue.tradeClub(tradeName: co.trade, region: p.countryCode).name
        case .seasonMilestone: e.count = max(1, (p.level ?? 3) / 3)
        }
        return e
    }
}
