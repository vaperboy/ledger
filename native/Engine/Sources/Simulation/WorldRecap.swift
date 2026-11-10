import Foundation
import GameCore
import Businesses

public struct WorldRecapFriend: Equatable, Sendable {
    public var id: String
    public var kind: String
    public var text: String
    public var at: Double

    public init(id: String, kind: String, text: String, at: Double) {
        self.id = id; self.kind = kind; self.text = text; self.at = at
    }
}

public struct WorldRecapCard: Equatable, Sendable, Identifiable {
    public enum Home: String, Sendable { case news, stats }

    public struct Line: Equatable, Sendable, Identifiable {
        public var id: String
        public var text: String
        public var tone: String
    }

    public var id: Int
    public var lines: [Line]
    public var home: Home
}

public enum WorldRecap {
    public static let minMove = 0.02
    public static let windowDays = 7

    public static func dismissedWeek(_ s: GameState) -> Int? {
        let v = s.rest["wrecap"]?["d"] ?? .null
        return v.isNull ? nil : v.int
    }

    public static func dismiss(_ s: inout GameState) {
        var o = s.rest["wrecap"] ?? .object([:])
        o["d"] = .number(Double(s.week))
        s.rest["wrecap"] = o
    }

    static func today(_ s: GameState) -> Int { s.week * 7 + s.day }

    static func priceLine(_ s: GameState) -> WorldRecapCard.Line? {
        let moves = ExchangeBook(s).instruments.values
            .filter { (i: ExchangeInstrument) -> Bool in !i.halted && i.previousClose > 0 && i.close > 0 && abs(i.change) >= minMove }
            .sorted { (a: ExchangeInstrument, b: ExchangeInstrument) -> Bool in abs(a.change) != abs(b.change) ? abs(a.change) > abs(b.change) : a.id < b.id }
        if let m = moves.first {
            let pct = Int(saturating: (abs(m.change) * 100).rounded())
            return WorldRecapCard.Line(id: "price", text: "\(m.name) \(m.change > 0 ? "rose" : "fell") \(pct)% on the exchange.", tone: m.change > 0 ? "good" : "bad")
        }
        let now = today(s)
        for e in MarketEvents.events(s, limit: 20) where e.kind == .supplierPriceChange && now - e.day < windowDays {
            return WorldRecapCard.Line(id: "price", text: e.title + ".", tone: e.tone)
        }
        return nil
    }

    static func rivalLine(_ s: GameState) -> WorldRecapCard.Line? {
        let now = today(s)
        for e in MarketEvents.events(s, limit: 20) where e.kind == .competitorLaunch && e.title.hasSuffix("opens a new store") && now - e.day < windowDays {
            return WorldRecapCard.Line(id: "rival", text: "A rival opened a new store. " + e.detail, tone: "bad")
        }
        return nil
    }

    static func friendRank(_ kind: String) -> Int {
        switch kind {
        case "levelUp": return 0
        case "joined": return 2
        default: return 1
        }
    }

    public static func friendLine(_ items: [WorldRecapFriend], now: Double) -> WorldRecapCard.Line? {
        let recent = items.filter { (f: WorldRecapFriend) -> Bool in now - f.at <= Double(windowDays) * 86_400 && !f.text.isEmpty }
        let best = recent.sorted { (a: WorldRecapFriend, b: WorldRecapFriend) -> Bool in
            if friendRank(a.kind) != friendRank(b.kind) { return friendRank(a.kind) < friendRank(b.kind) }
            return a.at != b.at ? a.at > b.at : a.id < b.id
        }.first
        return best.map { WorldRecapCard.Line(id: "friend", text: $0.text, tone: "good") }
    }

    public static func card(_ s: GameState, friends: [WorldRecapFriend], now: Double) -> WorldRecapCard? {
        if dismissedWeek(s) == s.week { return nil }
        let price = priceLine(s), rival = rivalLine(s), friend = friendLine(friends, now: now)
        let lines = [price, rival, friend].compactMap { $0 }
        guard !lines.isEmpty else { return nil }
        return WorldRecapCard(id: s.week, lines: lines, home: friend != nil || price != nil ? .news : .stats)
    }
}

public extension GameEngine {
    func worldRecap(friends: [WorldRecapFriend], now: Date = Date()) -> WorldRecapCard? {
        WorldRecap.card(state, friends: friends, now: now.timeIntervalSince1970)
    }

    mutating func dismissWorldRecap() {
        update { s, _, _ in WorldRecap.dismiss(&s) }
    }
}
