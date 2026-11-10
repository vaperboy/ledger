import Foundation
import Businesses

final class MockAssociationService: AssociationService {
    private func directory() -> [PlayerProfile] {
        OnlineDirectoryCache.players.isEmpty ? SampleRoster.players() : OnlineDirectoryCache.players
    }

    func members(of club: AssociationClub) -> [AssociationMemberRow] {
        let seen: [String: PlayerProfile] = Dictionary(uniqueKeysWithValues: directory().map { ($0.id, $0) })
        var rows: [AssociationMemberRow] = []
        for raw in SampleRoster.players() where raw.privacy != .onlyMe {
            guard let shown = seen[raw.id], shown.relation != .blocked else { continue }
            let friend: Bool = shown.relation == .friend
            if let trade = club.tradeName {
                guard raw.countryCode == club.region else { continue }
                guard let co = raw.companies?.first(where: { $0.trade.lowercased() == trade.lowercased() }) else { continue }
                rows.append(AssociationMemberRow(id: raw.id, profile: shown, line: friend ? "\(co.trade) in \(co.city)" : nil))
            } else {
                var s = SampleRoster.Stream(club.id + ":" + raw.id)
                guard s.next(100) < 45 else { continue }
                rows.append(AssociationMemberRow(id: raw.id, profile: shown, line: nil))
            }
        }
        return rows.sorted { ($0.profile.level ?? 0) > ($1.profile.level ?? 0) }
    }
}
