import Foundation
import GameCore

/// The player's level: experience points earned from finished goals, the daily goal and weeks played. It lives in the save
/// (`rest["lvl"]` = { xp, wk }), so every player keeps their own level. Level L needs `50 * L * (L - 1)` points in total.
public enum PlayerLevel {
    public static let ladderXP = 60
    public static let dailyXP = 25
    public static let weekXP = 15

    public struct Info: Equatable, Sendable {
        public var level: Int
        public var xp: Int
        /// Points gathered inside this level and the points this level asks for in all.
        public var xpIntoLevel: Int
        public var xpForNext: Int
        /// 0 to 1 towards the next level.
        public var progress: Double
    }

    /// Total points needed to reach `level` (level 1 needs none).
    public static func threshold(_ level: Int) -> Int { 50 * level * max(0, level - 1) }

    public static func level(forXP xp: Int) -> Int {
        var l = 1
        while threshold(l + 1) <= xp { l += 1 }
        return l
    }

    public static func info(_ s: GameState) -> Info {
        let xp: Int = max(0, s.rest["lvl"]?["xp"].int ?? 0)
        let l: Int = level(forXP: xp)
        let into: Int = xp - threshold(l)
        let need: Int = threshold(l + 1) - threshold(l)
        return Info(level: l, xp: xp, xpIntoLevel: into, xpForNext: need, progress: need > 0 ? min(1, Double(into) / Double(need)) : 0)
    }

    /// Adds points and celebrates a new level. Returns the points added.
    @discardableResult
    public static func award(_ s: inout GameState, _ points: Int) -> Int {
        guard points > 0 else { return 0 }
        let before: Int = info(s).level
        var v = s.rest["lvl"] ?? .object([:])
        v["xp"] = .number(Double(max(0, v["xp"].int) + points))
        s.rest["lvl"] = v
        let after: Int = info(s).level
        if after > before {
            Celebrations.add(&s, kind: "milestone", title: "Level \(after)", detail: "You gained a level", reward: "", art: "milestone.rank", tier: 1)
        }
        return points
    }

    /// Each new game week played gives points once. The first look only records the week.
    public static func sweep(_ s: inout GameState) {
        var v = s.rest["lvl"] ?? .object([:])
        let seen: Int? = v["wk"].isNull ? nil : v["wk"].int
        if seen == s.week { return }
        v["wk"] = .number(Double(s.week))
        s.rest["lvl"] = v
        if let seen, s.week > seen { award(&s, weekXP) }
    }
}

public extension GameEngine {
    /// Level, points and progress to the next level.
    var playerLevel: PlayerLevel.Info { PlayerLevel.info(state) }
    mutating func sweepLevel() { update { s, _, _ in PlayerLevel.sweep(&s) } }
}
