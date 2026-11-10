import Foundation
import GameCore

public struct PlayerConviction: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case taxEvasion, fraud, unsafeGoods, smuggling, bribery, counterfeiting, harassment, sabotage }
    public var id: Int
    public var account: String
    public var kind: Kind
    public var summary: String
    public var fine: Double
    public var country: String
    public var week: Int
    public var tradeBanUntil: Int?
    public var officeBanUntil: Int?
    public var voteBanUntil: Int?
    public var grave: Bool
    public var quashed = false
}

public struct WatchlistEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: Int { convictionID }
    public var convictionID: Int
    public var account: String
    public var name: String
    public var kind: PlayerConviction.Kind
    public var week: Int
    public var summary: String
}

public struct Justice: Codable, Equatable, Sendable {
    public enum Scope: Sendable { case trade, office, vote }

    public private(set) var convictions: [PlayerConviction] = []
    public private(set) var watchlist: [WatchlistEntry] = []
    var nextID = 1

    public init() {}

    @discardableResult
    mutating func record(account: String, name: String, kind: PlayerConviction.Kind, summary: String, fine: Double, country: String, week: Int,
                         tradeBanWeeks: Int = 0, officeBanWeeks: Int = 0, voteBanWeeks: Int = 0, grave: Bool) -> PlayerConviction {
        let c = PlayerConviction(id: nextID, account: account, kind: kind, summary: summary, fine: govRound(max(0, fine)), country: country, week: week,
                                 tradeBanUntil: tradeBanWeeks > 0 ? week + tradeBanWeeks : nil,
                                 officeBanUntil: officeBanWeeks > 0 ? week + officeBanWeeks : nil,
                                 voteBanUntil: voteBanWeeks > 0 ? week + voteBanWeeks : nil, grave: grave)
        nextID += 1
        convictions.insert(c, at: 0)
        if grave { watchlist.insert(WatchlistEntry(convictionID: c.id, account: account, name: name, kind: kind, week: week, summary: summary), at: 0) }
        return c
    }

    mutating func quash(_ id: Int) -> PlayerConviction? {
        guard let i = convictions.firstIndex(where: { $0.id == id && !$0.quashed }) else { return nil }
        convictions[i].quashed = true
        watchlist.removeAll { $0.convictionID == id }
        return convictions[i]
    }

    public func barred(_ account: String, _ scope: Scope, week: Int) -> Bool {
        convictions.contains { c in
            guard c.account == account, !c.quashed else { return false }
            let until: Int?
            switch scope { case .trade: until = c.tradeBanUntil; case .office: until = c.officeBanUntil; case .vote: until = c.voteBanUntil }
            return (until ?? -1) > week
        }
    }

    public func count(_ account: String) -> Int { convictions.filter { $0.account == account && !$0.quashed }.count }
    public func own(_ account: String) -> [PlayerConviction] { convictions.filter { $0.account == account } }
}
