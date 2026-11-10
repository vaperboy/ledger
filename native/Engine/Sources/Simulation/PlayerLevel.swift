import Foundation
import GameCore

public struct ProfileProgress: Codable, Equatable, Sendable {
    public var xp: Int
    public var seen: [String]?

    public init(xp: Int = 0, seen: [String]? = nil) {
        self.xp = xp
        self.seen = seen
    }

    public func merged(with other: ProfileProgress) -> ProfileProgress {
        let both: [String]? = seen == nil && other.seen == nil ? nil : Array(Set((seen ?? []) + (other.seen ?? []))).sorted()
        return ProfileProgress(xp: max(xp, other.xp), seen: both)
    }
}

public enum PlayerLevel {
    public static let ladderXP = 60
    public static let dailyXP = 25
    public static let weekXP = 15
    public static let maxLevel = 100

    public struct Info: Equatable, Sendable {
        public var level: Int
        public var xp: Int
        public var xpIntoLevel: Int
        public var xpForNext: Int
        public var progress: Double
    }

    public static func threshold(_ level: Int) -> Int { 25 * level * max(0, level - 1) }

    public static func level(forXP xp: Int) -> Int {
        var l = 1
        while l < maxLevel && threshold(l + 1) <= xp { l += 1 }
        return l
    }

    public static func info(_ s: GameState) -> Info {
        let xp: Int = max(0, s.rest["lvl"]?["xp"].int ?? 0)
        let l: Int = level(forXP: xp)
        let into: Int = xp - threshold(l)
        if l >= maxLevel { return Info(level: l, xp: xp, xpIntoLevel: 0, xpForNext: 0, progress: 1) }
        let need: Int = threshold(l + 1) - threshold(l)
        return Info(level: l, xp: xp, xpIntoLevel: into, xpForNext: need, progress: need > 0 ? min(1, Double(into) / Double(need)) : 0)
    }

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

    static func seenIDs(_ s: GameState) -> [String]? {
        guard let v = s.rest["lvl"], !v["seen"].isNull else { return nil }
        return v["seen"].array.map { $0.string }
    }

    public static func profile(of s: GameState) -> ProfileProgress { ProfileProgress(xp: info(s).xp, seen: seenIDs(s)) }

    @discardableResult
    public static func adopt(_ s: inout GameState, profile p: ProfileProgress) -> ProfileProgress {
        let merged: ProfileProgress = profile(of: s).merged(with: p)
        var v = s.rest["lvl"] ?? .object([:])
        v["xp"] = .number(Double(merged.xp))
        s.rest["lvl"] = v
        let seen: [String] = merged.seen ?? LevelGates.reached(level: info(s).level)
        v["seen"] = .array(seen.map { JSONValue.string($0) })
        s.rest["lvl"] = v
        UnlockNotices.seedGates(&s)
        return ProfileProgress(xp: merged.xp, seen: seen)
    }

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
    var playerLevel: PlayerLevel.Info { PlayerLevel.info(state) }
    mutating func sweepLevel() { update { s, _, _ in PlayerLevel.sweep(&s) } }
}
