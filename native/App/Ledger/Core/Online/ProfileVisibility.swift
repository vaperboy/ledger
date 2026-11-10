import Foundation

enum ProfileVisibility {
    static func apply(_ profile: PlayerProfile, relation: FriendRelation) -> PlayerProfile {
        var v: PlayerProfile = profile
        v.relation = relation
        if relation == .you { return v }
        let friend: Bool = relation == .friend
        func nameOnly() {
            v.level = nil; v.badges = []; v.companyCount = nil; v.companies = nil; v.gameWeek = nil; v.tradesCompleted = nil; v.lastSeen = nil
        }
        if relation == .blocked { nameOnly(); return v }
        switch profile.privacy {
        case .everyone:
            if !friend { v.companies = nil }
        case .friends:
            if !friend { v.companyCount = nil; v.companies = nil; v.tradesCompleted = nil }
        case .onlyMe:
            nameOnly()
        }
        return v
    }

    static func showsBoardFigure(_ privacy: PrivacyLevel) -> Bool { privacy != .onlyMe }
}

enum BoardProfiles {
    static let rivalPrefix = "rival-"

    static func isRival(_ id: String) -> Bool { id.hasPrefix(rivalPrefix) }

    static func privacy(rivalName name: String) -> PrivacyLevel {
        switch EmblemCatalog.hash("privacy" + name) % 6 {
        case 0: return .onlyMe
        case 1, 2: return .friends
        default: return .everyone
        }
    }

    static func privacy(playerID id: String, name: String) -> PrivacyLevel {
        if isRival(id) { return privacy(rivalName: name) }
        return OnlineDirectoryCache.players.first { (p: PlayerProfile) -> Bool in p.id == id }?.privacy ?? .everyone
    }

    static func rivalProfile(id: String, name: String) -> PlayerProfile {
        let h: Int = EmblemCatalog.hash("level" + name)
        let pool: [String] = ["Early player", "Cash positive", "Debt free", "Hired fifty", "Opened abroad", "Five-star shop", "Season one"]
        let badges: [String] = Array(Set([pool[h % pool.count], pool[(h / 7) % pool.count]])).sorted()
        let raw = PlayerProfile(id: id, code: "", displayName: name, avatarColour: AvatarCatalog.colour(for: name), countryCode: "",
                                level: 3 + h % 28, badges: badges, privacy: privacy(rivalName: name), companyCount: 1 + (h / 11) % 5,
                                companies: nil, gameWeek: nil, tradesCompleted: nil, relation: .none, avatarIcon: AvatarCatalog.simulatedIcon(for: name))
        return ProfileVisibility.apply(raw, relation: .none)
    }
}
