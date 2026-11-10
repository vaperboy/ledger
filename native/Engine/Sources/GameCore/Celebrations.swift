import Foundation

public struct Celebration: Equatable, Sendable, Identifiable {
    public var id: Int
    public var kind: String
    public var title: String
    public var detail: String
    public var reward: String
    public var week: Int
    public var art: String = ""
    public var tier: Int = 1
}

public struct AwardInfo: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var tier: Int
    public var artKey: String
    public init(id: String, title: String, detail: String, tier: Int, artKey: String) { self.id = id; self.title = title; self.detail = detail; self.tier = tier; self.artKey = artKey }
}

public enum Celebrations {
    public static let limit = 12

    public static func add(_ s: inout GameState, kind: String, title: String, detail: String = "", reward: String = "", art: String = "", tier: Int = 1) {
        var list = s.rest["cele"]?.array ?? []
        if list.contains(where: { $0["k"].string == kind && $0["t"].string == title }) { return }
        let n = (s.rest["celeN"]?.int ?? 0) + 1
        s.rest["celeN"] = .number(Double(n))
        list.append(.object(["id": .number(Double(n)), "k": .string(kind), "t": .string(title), "d": .string(detail), "r": .string(reward), "w": .number(Double(s.week))].merging(art.isEmpty ? [:] : ["a": .string(art), "n": .number(Double(tier))]) { $1 }))
        if list.count > limit { list.removeFirst(list.count - limit) }
        s.rest["cele"] = .array(list)
    }

    public static func pending(_ s: GameState) -> [Celebration] {
        (s.rest["cele"]?.array ?? []).map {
            Celebration(id: $0["id"].int, kind: $0["k"].string, title: $0["t"].string, detail: $0["d"].string, reward: $0["r"].string, week: $0["w"].int,
                         art: $0["a"].string.isEmpty ? "\($0["k"].string)" : $0["a"].string, tier: $0["n"].isNull ? 1 : $0["n"].int)
        }
    }

    public static func take(_ s: inout GameState) -> [Celebration] {
        let list = pending(s)
        s.rest["cele"] = nil
        return list
    }
}
