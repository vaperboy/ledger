import Foundation
import GameCore

public enum PassMissions {
    public enum Period: String, Sendable, CaseIterable {
        case day, week, month
        public var days: Int { self == .day ? 1 : (self == .week ? 7 : 30) }
        public var prefix: String { self == .day ? "d" : (self == .week ? "w" : "m") }
        public var label: String { self == .day ? "Today" : (self == .week ? "This week" : "This month") }
    }

    public struct Mission: Equatable, Sendable, Identifiable {
        public var id: String
        public var period: Period
        public var title: String
        public var metric: String
        public var target: Int
        public var xp: Int

        public func index(today: Int) -> Int { today / period.days }
        public func key(today: Int) -> String { "\(period.prefix)\(index(today: today)).\(id)" }
    }

    public static let metrics: [String] = ["advance", "decision", "event", "answered", "dailyGoal", "weekReport"]

    static let file: JSONValue = ContentFile.load("season", "pass_missions")

    public static let loginXP: Int = file["loginXP"].int

    public static let all: [Mission] = file["missions"].array.compactMap { (e: JSONValue) -> Mission? in
        guard let p = Period(rawValue: e["period"].string) else { return nil }
        return Mission(id: e["id"].string, period: p, title: e["title"].string, metric: e["metric"].string, target: max(1, e["target"].int), xp: e["xp"].int)
    }

    public static func missions(_ period: Period) -> [Mission] { all.filter { (m: Mission) -> Bool in m.period == period } }

    public static func missions(metric: String) -> [Mission] { all.filter { (m: Mission) -> Bool in m.metric == metric } }

    public static func maxDailyXP() -> Int { loginXP + missions(.day).reduce(0) { (n: Int, m: Mission) -> Int in n + m.xp } }

    static let storeKey = "pcnt"

    public static func note(_ s: inout GameState, _ metric: String, _ amount: Int = 1) {
        guard amount > 0 else { return }
        var o: [String: JSONValue] = (s.rest[storeKey] ?? .null).object
        o[metric] = .number(Double((o[metric]?.int ?? 0) + amount))
        s.rest[storeKey] = .object(o)
    }

    public static func counters(_ s: GameState) -> [String: Int] {
        (s.rest[storeKey] ?? .null).object.mapValues { (v: JSONValue) -> Int in v.int }
    }

    public static func noteAnswer(_ s: inout GameState, decision: Bool) {
        note(&s, decision ? "decision" : "event")
        note(&s, "answered")
    }
}
