import Foundation
import GameCore

public enum LevelRewards {
    public struct Reward: Equatable, Sendable, Identifiable {
        public var level: Int
        public var gold: Int
        public var icon: String?
        public var id: Int { level }
    }

    public static let all: [Reward] = ContentFile.load("progression", "level_rewards")["rewards"].array.map { (e: JSONValue) -> Reward in
        Reward(level: e["level"].int, gold: e["gold"].int, icon: e["icon"].isNull ? nil : e["icon"].string)
    }.sorted { (a: Reward, b: Reward) -> Bool in a.level < b.level }

    public static func reward(at level: Int) -> Reward? { all.first { (r: Reward) -> Bool in r.level == level } }

    public static func due(from: Int, to: Int) -> [Reward] { all.filter { (r: Reward) -> Bool in r.level > from && r.level <= to } }

    public static var iconIDs: Set<String> { Set(all.compactMap { (r: Reward) -> String? in r.icon }) }

    public static func isLevelIcon(_ id: String) -> Bool { iconIDs.contains(id) }
}
