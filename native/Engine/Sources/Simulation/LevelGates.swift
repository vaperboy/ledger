import Foundation
import GameCore
import Businesses

public enum LevelFeature: String, CaseIterable, Sendable {
    case auctions, exchange, jointVentures, government, politics
}

public enum LevelGates {
    struct Row: Sendable {
        var feature: LevelFeature
        var level: Int
        var title: String
        var gives: String
    }

    static let table: [Row] = [
        Row(feature: .auctions, level: 2, title: "Auctions", gives: "sell your artifacts or bid on other players' pieces"),
        Row(feature: .exchange, level: 3, title: "Stock exchange", gives: "list a company and sell shares in it"),
        Row(feature: .jointVentures, level: 4, title: "Joint ventures", gives: "start a company together with a friend"),
        Row(feature: .government, level: 4, title: "Government", gives: "the treasury, tax rates and the president"),
        Row(feature: .politics, level: 6, title: "Politics", gives: "donate, stand in elections and shape the law"),
    ]

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
}

public extension GameEngine {
    func levelOpen(_ f: LevelFeature) -> Bool { LevelGates.isOpen(f, state) }
}
