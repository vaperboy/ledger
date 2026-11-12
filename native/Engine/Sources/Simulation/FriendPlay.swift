import Foundation
import GameCore
import Businesses

public struct LoginStreak: Codable, Equatable, Sendable {
    public var count: Int
    public var best: Int
    public var lastDay: Int

    public init(count: Int = 0, best: Int = 0, lastDay: Int = 0) {
        self.count = count; self.best = best; self.lastDay = lastDay
    }
}

public struct LoginReward: Equatable, Sendable {
    public var gold: Int
    public var boxes: Int
    public var text: String
}

public enum LoginStreakRules {
    public static let boxEvery = 7
    public static let forgivenGap = 7

    public static func reward(day n: Int) -> LoginReward {
        let gold = min(3, 1 + n / 10)
        let box = n > 0 && n % boxEvery == 0
        return LoginReward(gold: gold, boxes: box ? 1 : 0,
                           text: "Day \(n): +\(gold) gold" + (box ? " and a Season box" : ""))
    }

    public static func open(_ st: LoginStreak, today: Int) -> (streak: LoginStreak, reward: LoginReward?) {
        guard today > st.lastDay else { return (st, nil) }
        var n = st
        if st.lastDay == 0 {
            n.count = 1
        } else if today - st.lastDay <= forgivenGap {
            n.count = st.count + 1
        } else {
            n.count = max(1, st.count / 2) + 1
        }
        n.best = max(st.best, n.count)
        n.lastDay = today
        return (n, reward(day: n.count))
    }

    public static func openedToday(_ st: LoginStreak, today: Int) -> Bool { st.lastDay == today }

    public static func daysToBox(_ st: LoginStreak) -> Int {
        let r = st.count % boxEvery
        return r == 0 ? boxEvery : boxEvery - r
    }
}

public struct RaceEntry: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var growth: Double
    public var isYou: Bool

    public init(id: String, name: String, growth: Double, isYou: Bool = false) {
        self.id = id; self.name = name; self.growth = growth; self.isYou = isYou
    }
}

public enum FriendRace {
    public static let rewardGold = [3, 2, 1]

    public static func week(ofDay day: Int) -> Int { day / 7 }

    public static func growth(base: Double, now: Double) -> Double {
        guard base > 0, now.isFinite else { return 0 }
        return ((now - base) / base * 10_000).rounded() / 10_000
    }

    public static func standings(_ entries: [RaceEntry]) -> [RaceEntry] {
        entries.sorted { a, b in
            if a.growth != b.growth { return a.growth > b.growth }
            return a.name != b.name ? a.name < b.name : a.id < b.id
        }
    }

    public static func place(of id: String, in entries: [RaceEntry]) -> Int? {
        standings(entries).firstIndex { $0.id == id }.map { $0 + 1 }
    }

    public static func reward(place: Int?, racers: Int) -> Int {
        guard let p = place, p >= 1, p <= rewardGold.count, p < racers else { return 0 }
        return rewardGold[p - 1]
    }
}

public enum GiftRules {
    public static func canSend(lastSentDay: Int, today: Int) -> Bool { lastSentDay != today }

    public static func arrivalText(from name: String, item: String) -> String {
        "\(name) sent you \(item) from their cabinet."
    }
}

public struct GoalState: Codable, Equatable, Sendable {
    public var week: Int
    public var target: Double
    public var total: Double
    public var reward: String
    public var met: Bool { total >= target }
}

public enum SharedGoalRules {
    public static let unitsPerMember = 300.0
    public static let rewards = ["gold.plate.pewter", "gold.backdrop.fog", "gold.trade.pewter", "outfit.charcoal"]

    public static func target(members: Int) -> Double { unitsPerMember * Double(max(2, members)) }

    public static func contribution(_ s: GameState) -> Double {
        s.companies.filter { $0.status == .open }.reduce(0) { $0 + $1.lastWeekUnits }.rounded()
    }

    public static func reward(week: Int, owned: Set<String>) -> String? {
        guard !rewards.isEmpty else { return nil }
        let start = ((week % rewards.count) + rewards.count) % rewards.count
        for i in 0..<rewards.count {
            let id = rewards[(start + i) % rewards.count]
            if !owned.contains(id) { return id }
        }
        return nil
    }

    public static func state(week: Int, members: Int, contributions: [Double], owned: Set<String>) -> GoalState {
        GoalState(week: week, target: target(members: members), total: contributions.reduce(0, +), reward: reward(week: week, owned: owned) ?? "")
    }
}

public struct RichRival: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var netWorth: Double
    public var isReal: Bool
    public var visible: Bool

    public init(id: String, name: String, netWorth: Double, isReal: Bool, visible: Bool) {
        self.id = id; self.name = name; self.netWorth = netWorth; self.isReal = isReal; self.visible = visible
    }
}

public enum RichPass {
    static let key = "rpass"

    public static func passed(before: Double, now: Double, rivals: [RichRival], notified: Set<String>) -> [RichRival] {
        guard before.isFinite, now.isFinite, now > before else { return [] }
        return rivals.filter { $0.isReal && !notified.contains($0.id) && $0.netWorth >= before && $0.netWorth < now }
            .sorted { $0.netWorth != $1.netWorth ? $0.netWorth > $1.netWorth : $0.id < $1.id }
    }

    public static func myNotice(_ list: [RichRival]) -> String? {
        guard let first = list.first else { return nil }
        let name = first.visible ? first.name : "a player"
        if list.count == 1 { return "You passed \(name) in net worth." }
        return "You passed \(name) and \(list.count - 1) more \(list.count == 2 ? "player" : "players") in net worth."
    }

    public static func theirNotice(passer name: String, visible: Bool) -> String {
        "\(visible ? name : "A player") passed you in net worth."
    }
}

public extension GameEngine {
    mutating func notePassedPlayers(_ rivals: [RichRival], netWorth now: Double) -> [RichRival] {
        let st = state.rest[RichPass.key] ?? .null
        guard !st["nw"].isNull else {
            update { s, _, _ in s.rest[RichPass.key] = .object(["nw": .number(now), "seen": .array([])]) }
            return []
        }
        let seen = Set(st["seen"].array.map { $0.string })
        let found = RichPass.passed(before: st["nw"].double, now: now, rivals: rivals, notified: seen)
        update { s, _, _ in
            s.rest[RichPass.key] = .object(["nw": .number(max(st["nw"].double, now)), "seen": .array((Array(seen) + found.map { $0.id }).sorted().map { .string($0) })])
        }
        return found
    }
}
