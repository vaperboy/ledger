import Foundation
import GameCore
import Businesses

public enum LevelFeature: String, CaseIterable, Sendable {
    case auctions, exchange, ventures, jointVentures, government, politics, chain, franchise, abroad
}

public enum LevelGates {
    struct Row: Sendable {
        var feature: LevelFeature
        var level: Int
        var title: String
        var gives: String
    }

    static let table: [Row] = ContentFile.load("progression", "level_gates")["gates"].array.compactMap { (e: JSONValue) -> Row? in
        guard let f = LevelFeature(rawValue: e["feature"].string) else { return nil }
        return Row(feature: f, level: e["level"].int, title: e["title"].string, gives: e["gives"].string)
    }

    static func row(_ f: LevelFeature) -> Row { table.first { (r: Row) -> Bool in r.feature == f } ?? table[0] }

    public static func level(_ f: LevelFeature) -> Int { row(f).level }
    public static func title(_ f: LevelFeature) -> String { row(f).title }
    public static func gives(_ f: LevelFeature) -> String { row(f).gives }

    public static func lockLine(_ f: LevelFeature) -> String { "Unlocks at level \(level(f)): \(gives(f))" }

    public static func isOpen(_ f: LevelFeature, _ s: GameState) -> Bool {
        guard Gates.ladderOn(s) else { return true }
        return PlayerLevel.info(s).level >= level(f)
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

    public static func nextLocked(_ s: GameState) -> LevelFeature? {
        let rows: [Row] = table.filter { (r: Row) -> Bool in !isOpen(r.feature, s) }
        return rows.min(by: { (a: Row, b: Row) -> Bool in a.level < b.level })?.feature
    }

    public static func opensWith(_ f: LevelFeature) -> [LevelFeature] {
        table.filter { (r: Row) -> Bool in r.level == level(f) }.map { (r: Row) -> LevelFeature in r.feature }
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

    public static var highestUnlockLevel: Int { table.map { (r: Row) -> Int in r.level }.max() ?? 1 }

    public static func unlocks(atLevel l: Int) -> [Entry] {
        table.filter { (r: Row) -> Bool in r.level == l }.map { (r: Row) -> Entry in Entry(feature: r.feature, title: r.title, gives: r.gives) }
    }

    public static func ladder() -> [Rung] {
        (1...(highestUnlockLevel + 1)).map { (l: Int) -> Rung in
            Rung(level: l, xpRequired: PlayerLevel.threshold(l), xpFromPrevious: l > 1 ? PlayerLevel.threshold(l) - PlayerLevel.threshold(l - 1) : 0, unlocks: unlocks(atLevel: l))
        }
    }

    static func noticeID(_ f: LevelFeature) -> String { "level." + f.rawValue }

    static func reached(level l: Int) -> [String] {
        table.filter { (r: Row) -> Bool in r.level <= l }.map { (r: Row) -> String in noticeID(r.feature) }
    }
}

public extension GameEngine {
    func levelOpen(_ f: LevelFeature) -> Bool { LevelGates.isOpen(f, state) }
}

public enum UnlockNotices {
    public struct Item: Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var line: String
        public var target: String
    }

    static let gateKey = "gateSeen"
    static let skippedGates: Set<Gate> = [.ownerHours]

    static func gateID(_ g: Gate) -> String { "gate." + g.rawValue }

    static func recorded(_ s: GameState) -> [Gate] {
        let rec: JSONValue = s.rest["gateG"] ?? .null
        return Gate.allCases.filter { (g: Gate) -> Bool in !skippedGates.contains(g) && !rec[g.rawValue].isNull }
    }

    static func seenGates(_ s: GameState) -> Set<String> { Set((s.rest[gateKey]?.array ?? []).map { $0.string }) }

    public static func seedGates(_ s: inout GameState) {
        guard s.rest[gateKey] == nil else { return }
        s.rest[gateKey] = .array(recorded(s).map { JSONValue.string(gateID($0)) })
    }

    public static func pending(_ s: GameState) -> [Item] {
        guard Gates.ladderOn(s) else { return [] }
        var out: [Item] = []
        let seenLevel: Set<String> = Set(PlayerLevel.seenIDs(s) ?? [])
        let level: Int = PlayerLevel.info(s).level
        for r in LevelGates.table.sorted(by: { (a: LevelGates.Row, b: LevelGates.Row) -> Bool in a.level < b.level }) where r.level <= level && !seenLevel.contains(LevelGates.noticeID(r.feature)) {
            out.append(Item(id: LevelGates.noticeID(r.feature), title: r.title, line: "Level \(r.level) lets you " + r.gives + ".", target: r.feature.rawValue))
        }
        let seenGate: Set<String> = seenGates(s)
        let opened: JSONValue = s.rest["gateG"] ?? .null
        for g in recorded(s) where opened[g.rawValue].double > 0 && !seenGate.contains(gateID(g)) {
            out.append(Item(id: gateID(g), title: Gates.title(g), line: GatePurposes.purpose(g.rawValue) ?? "It is open now.", target: g.rawValue))
        }
        return out
    }

    public static func markSeen(_ s: inout GameState, id: String) {
        if id.hasPrefix("level.") {
            var v = s.rest["lvl"] ?? .object([:])
            var seen: [JSONValue] = v["seen"].array
            if !seen.contains(where: { $0.string == id }) { seen.append(.string(id)) }
            v["seen"] = .array(seen)
            s.rest["lvl"] = v
        } else if id.hasPrefix("gate.") {
            var seen: [JSONValue] = s.rest[gateKey]?.array ?? []
            if !seen.contains(where: { $0.string == id }) { seen.append(.string(id)) }
            s.rest[gateKey] = .array(seen)
        }
    }
}

public extension GameEngine {
    func pendingNotices() -> [UnlockNotices.Item] { UnlockNotices.pending(state) }
    mutating func markNoticeSeen(id: String) { update { s, _, _ in UnlockNotices.markSeen(&s, id: id) } }
}
