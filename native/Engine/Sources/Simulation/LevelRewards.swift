import Foundation
import GameCore

public enum LevelRewards {
    public struct Reward: Equatable, Sendable, Identifiable {
        public var level: Int
        public var gold: Int
        /// An outfit (id in cosmetics/gold_cosmetics.json) that comes with this level.
        public var outfit: String?
        public var id: Int { level }
    }

    public static let all: [Reward] = ContentFile.load("progression", "level_rewards")["rewards"].array.map { (e: JSONValue) -> Reward in
        Reward(level: e["level"].int, gold: e["gold"].int, outfit: e["outfit"].isNull ? nil : e["outfit"].string)
    }.sorted { (a: Reward, b: Reward) -> Bool in a.level < b.level }

    public static func reward(at level: Int) -> Reward? { all.first { (r: Reward) -> Bool in r.level == level } }

    public static func due(from: Int, to: Int) -> [Reward] { all.filter { (r: Reward) -> Bool in r.level > from && r.level <= to } }

    public static var outfitIDs: Set<String> { Set(all.compactMap { (r: Reward) -> String? in r.outfit }) }

    public static func isLevelOutfit(_ id: String) -> Bool { outfitIDs.contains(id) }

    /// Level outfits a player of this level owns.
    public static func outfits(upTo level: Int) -> [String] { all.filter { $0.level <= level }.compactMap { $0.outfit } }
}
