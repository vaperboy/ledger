import Foundation
import GameCore
import Businesses

/// Level reads for the app, all drawn from the one table in `FeatureUnlocks`.
public enum LevelGates {
    public static func level(_ f: LevelFeature) -> Int { FeatureUnlocks.unlockLevel(f) }
    public static func title(_ f: LevelFeature) -> String { FeatureUnlocks.row(f).title }
    public static func gives(_ f: LevelFeature) -> String { FeatureUnlocks.row(f).gives }

    public static func lockLine(_ f: LevelFeature) -> String { FeatureUnlocks.lockLine(f) }

    public static func isOpen(_ f: LevelFeature, _ s: GameState) -> Bool { FeatureUnlocks.isUnlocked(f, s) }

    /// Open, locked with its level line when it is close, or hidden while it is far off.
    public static func visibility(_ f: LevelFeature, _ s: GameState) -> GateVisibility {
        if isOpen(f, s) { return .open }
        return level(f) - PlayerLevel.info(s).level <= Gates.nearLevels ? .locked(lockLine(f)) : .hidden
    }

    public struct Progress: Equatable, Sendable {
        public var fraction: Double
        public var xpToGo: Int
    }

    public static func progress(_ f: LevelFeature, _ s: GameState) -> Progress {
        let need: Int = PlayerLevel.threshold(level(f))
        let xp: Int = PlayerLevel.info(s).xp
        return Progress(fraction: need > 0 ? min(1, Double(xp) / Double(need)) : 1, xpToGo: max(0, need - xp))
    }

    public static func nextLocked(_ s: GameState) -> LevelFeature? { FeatureUnlocks.nextUnlock(s)?.feature }

    public static func opensWith(_ f: LevelFeature) -> [LevelFeature] {
        FeatureUnlocks.unlocks(atLevel: level(f)).map { (r: FeatureUnlocks.Row) -> LevelFeature in r.feature }
    }

    public struct Entry: Equatable, Sendable, Identifiable {
        public var feature: LevelFeature
        public var title: String
        public var gives: String
        public var id: String { feature.rawValue }
    }

    public struct Rung: Equatable, Sendable, Identifiable {
        public var level: Int
        public var xpRequired: Int
        public var xpFromPrevious: Int
        public var unlocks: [Entry]
        public var id: Int { level }
    }

    public static var highestUnlockLevel: Int { FeatureUnlocks.highestLevel }

    public static func unlocks(atLevel l: Int) -> [Entry] {
        FeatureUnlocks.unlocks(atLevel: l).map { (r: FeatureUnlocks.Row) -> Entry in Entry(feature: r.feature, title: r.title, gives: r.gives) }
    }

    public static func ladder() -> [Rung] {
        (1...(highestUnlockLevel + 1)).map { (l: Int) -> Rung in
            Rung(level: l, xpRequired: PlayerLevel.threshold(l), xpFromPrevious: l > 1 ? PlayerLevel.threshold(l) - PlayerLevel.threshold(l - 1) : 0, unlocks: unlocks(atLevel: l))
        }
    }

    static func noticeID(_ f: LevelFeature) -> String { "level." + f.rawValue }

    static func reached(level l: Int) -> [String] {
        FeatureUnlocks.table.filter { (r: FeatureUnlocks.Row) -> Bool in r.level <= l }.map { (r: FeatureUnlocks.Row) -> String in noticeID(r.feature) }
    }
}

public extension GameEngine {
    func levelOpen(_ f: LevelFeature) -> Bool { LevelGates.isOpen(f, state) }
}

/// One "unlocked" popup per feature, shown when the player reaches its level.
public enum UnlockNotices {
    public struct Item: Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var line: String
        public var target: String
    }

    public static func pending(_ s: GameState) -> [Item] {
        guard Gates.ladderOn(s) else { return [] }
        let seen: Set<String> = Set(PlayerLevel.seenIDs(s) ?? [])
        let level: Int = PlayerLevel.info(s).level
        return FeatureUnlocks.table.filter { (r: FeatureUnlocks.Row) -> Bool in r.level <= level && !seen.contains(LevelGates.noticeID(r.feature)) }
            .map { (r: FeatureUnlocks.Row) -> Item in
                Item(id: LevelGates.noticeID(r.feature), title: r.title, line: "Level \(r.level) lets you " + r.gives + ".", target: r.feature.rawValue)
            }
    }

    public static func markSeen(_ s: inout GameState, id: String) {
        guard id.hasPrefix("level.") else { return }
        var v = s.rest["lvl"] ?? .object([:])
        var seen: [JSONValue] = v["seen"].array
        if !seen.contains(where: { $0.string == id }) { seen.append(.string(id)) }
        v["seen"] = .array(seen)
        s.rest["lvl"] = v
    }
}

public extension GameEngine {
    func pendingNotices() -> [UnlockNotices.Item] { UnlockNotices.pending(state) }
    mutating func markNoticeSeen(id: String) { update { s, _, _ in UnlockNotices.markSeen(&s, id: id) } }
}
