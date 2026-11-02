import Foundation

/// Something the player earned that deserves a moment on the main page: a trophy, an ambition milestone, a finished first step.
/// The queue is kept in the save (`rest["cele"]`, written only when something is earned), so a celebration that was earned
/// but not yet shown survives closing the app. Each entry carries the real reward text, never a made-up one.
public struct Celebration: Equatable, Sendable, Identifiable {
    public var id: Int
    /// "trophy", "milestone", "goal", "mission"
    public var kind: String
    public var title: String
    public var detail: String
    /// What the player actually gets ("+25 legacy points", "A start-up grant"); empty when there is none.
    public var reward: String
    public var week: Int
}

public enum Celebrations {
    public static let limit = 12

    /// Adds a celebration to the queue. A second entry with the same kind and title is not queued twice.
    public static func add(_ s: inout GameState, kind: String, title: String, detail: String = "", reward: String = "") {
        var list = s.rest["cele"]?.array ?? []
        if list.contains(where: { $0["k"].string == kind && $0["t"].string == title }) { return }
        let n = (s.rest["celeN"]?.int ?? 0) + 1
        s.rest["celeN"] = .number(Double(n))
        list.append(.object(["id": .number(Double(n)), "k": .string(kind), "t": .string(title), "d": .string(detail), "r": .string(reward), "w": .number(Double(s.week))]))
        if list.count > limit { list.removeFirst(list.count - limit) }
        s.rest["cele"] = .array(list)
    }

    public static func pending(_ s: GameState) -> [Celebration] {
        (s.rest["cele"]?.array ?? []).map {
            Celebration(id: $0["id"].int, kind: $0["k"].string, title: $0["t"].string, detail: $0["d"].string, reward: $0["r"].string, week: $0["w"].int)
        }
    }

    /// Takes the queue (the player has now seen it) and empties it. The key goes back to absent so a game that is not celebrating stays byte-identical.
    public static func take(_ s: inout GameState) -> [Celebration] {
        let list = pending(s)
        s.rest["cele"] = nil
        return list
    }
}
