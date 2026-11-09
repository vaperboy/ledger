import Foundation

/// News about real players, from public events only. Every sentence is a template filled from the event's own fields: a field the event does
/// not carry is never guessed, and an event missing a field the template needs gives no sentence. Who may see an event follows the player's
/// privacy level: Public players' events are open to everyone, Friends-level players' events only to their friends, Private players publish none.

public enum PlayerEventKind: String, Codable, CaseIterable, Sendable {
    case branchMilestone, wentViral, supplierMilestone, acquisition, newAssociation, seasonMilestone
}

/// Who the player allowed to see their events.
public enum PlayerEventAudience: String, Codable, Sendable {
    case everyone, friends
}

public struct PlayerEvent: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: PlayerEventKind
    public var playerID: String
    public var playerName: String
    public var countryCode: String
    public var audience: PlayerEventAudience
    /// The game-independent day the event happened (days since the epoch).
    public var day: Int
    public var trade: String?
    public var city: String?
    public var company: String?
    /// Branches opened, units delivered or the season reached, as the kind needs.
    public var count: Int?
    public var otherName: String?
    public var club: String?

    public init(id: String, kind: PlayerEventKind, playerID: String, playerName: String, countryCode: String, audience: PlayerEventAudience, day: Int,
                trade: String? = nil, city: String? = nil, company: String? = nil, count: Int? = nil, otherName: String? = nil, club: String? = nil) {
        self.id = id; self.kind = kind; self.playerID = playerID; self.playerName = playerName; self.countryCode = countryCode; self.audience = audience
        self.day = day; self.trade = trade; self.city = city; self.company = company; self.count = count; self.otherName = otherName; self.club = club
    }
}

public enum PlayerNewsFilter: String, CaseIterable, Sendable {
    case everyone, friends, myTrade, myCountry
    public var title: String {
        switch self {
        case .everyone: return "Everyone"
        case .friends: return "Friends"
        case .myTrade: return "My trade"
        case .myCountry: return "My country"
        }
    }
}

public enum PlayerNewsRules {
    /// Whether the viewer may see the event at all (privacy), before any filter.
    public static func canSee(_ e: PlayerEvent, viewerIsFriend: Bool, viewerIsOwner: Bool = false) -> Bool {
        if viewerIsOwner { return true }
        switch e.audience {
        case .everyone: return true
        case .friends: return viewerIsFriend
        }
    }

    /// Whether a visible event passes the chosen filter. "My trade" compares trade names ignoring case; an event with no trade never matches it.
    public static func matches(_ e: PlayerEvent, filter: PlayerNewsFilter, viewerIsFriend: Bool, viewerTrades: Set<String>, viewerCountry: String) -> Bool {
        switch filter {
        case .everyone: return true
        case .friends: return viewerIsFriend
        case .myTrade:
            guard let t = e.trade?.lowercased() else { return false }
            return viewerTrades.contains { $0.lowercased() == t }
        case .myCountry: return e.countryCode == viewerCountry
        }
    }

    private static let ordinalWords: [String] = ["", "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth",
                                                  "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth", "seventeenth",
                                                  "eighteenth", "nineteenth", "twentieth"]

    public static func ordinal(_ n: Int) -> String {
        if n >= 1 && n < ordinalWords.count { return ordinalWords[n] }
        let tens = n % 100
        let suffix = (11...13).contains(tens) ? "th" : (n % 10 == 1 ? "st" : n % 10 == 2 ? "nd" : n % 10 == 3 ? "rd" : "th")
        return "\(n)\(suffix)"
    }

    /// The company as the viewer may name it: its name for a friend, otherwise "a <trade> in <city>" from what the event carries.
    static func companyPhrase(_ e: PlayerEvent, namesVisible: Bool) -> String? {
        if namesVisible, let c = e.company { return c }
        switch (e.trade, e.city) {
        case let (t?, c?): return "a \(t.lowercased()) in \(c)"
        case let (t?, nil): return "a \(t.lowercased())"
        default: return nil
        }
    }

    /// The headline for one event; nil when the event lacks what its template needs. `namesVisible` is true for the owner and their friends.
    public static func sentence(_ e: PlayerEvent, namesVisible: Bool) -> String? {
        let who = e.playerName
        switch e.kind {
        case .branchMilestone:
            guard let n = e.count, n > 1, let c = companyPhrase(e, namesVisible: namesVisible) else { return nil }
            return "\(who) opened the \(ordinal(n)) branch of \(c)."
        case .wentViral:
            guard let c = companyPhrase(e, namesVisible: namesVisible) else { return nil }
            return "\(c.prefix(1).uppercased() + c.dropFirst()), a startup run by \(who), went viral."
        case .supplierMilestone:
            guard let n = e.count, n > 0, let c = companyPhrase(e, namesVisible: namesVisible) else { return nil }
            return "\(who)'s supplier, \(c), has now delivered \(n) units to other players' companies."
        case .acquisition:
            guard let other = e.otherName, let c = companyPhrase(e, namesVisible: namesVisible) else { return nil }
            return "\(who)'s \(c) acquired \(other)."
        case .newAssociation:
            guard let club = e.club else { return nil }
            return "\(who) joined \(club)."
        case .seasonMilestone:
            guard let n = e.count, n > 0 else { return nil }
            return "\(who) finished season \(n)."
        }
    }

    /// Numbers a sentence may contain: only the event's own count.
    public static func numbersIn(_ text: String) -> [Int] {
        text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }
}
