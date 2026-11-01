import Foundation
import GameCore

/// One event that can happen to a company, as data. Loaded from `Resources/events.json`.
/// Original: `EV` (engine/events/library.js). Costs are written as small formulas, see `Formula`.
public struct GameEvent: Sendable {
    public struct Option: Sendable {
        public var label: String
        public var detail: String
        /// Effects, e.g. cash (-1500), rep (-1), dem ([0.9, 4] = demand x0.9 for 4 weeks), gamble ({p, ok, bad})
        public var effects: JSONValue
    }
    public var id: String
    public var text: String
    /// Chance per week at average risk
    public var weight: Double
    public var category: String
    /// "good", "bad" or "n"
    public var tone: String
    /// Weeks the player has to decide
    public var expiresAfterWeeks: Int
    public var minimumCompanyAgeWeeks: Int
    /// Resolved without asking the player
    public var automatic: Bool
    public var automaticEffects: JSONValue
    public var condition: Formula?
    public var options: [Option]
    public var lawyerHelps: Bool

    init(id: String, json e: JSONValue) {
        self.id = id
        text = e["t"].string
        weight = e["w"].double
        category = e["cat"].isNull ? "none" : e["cat"].string
        tone = e["tone"].isNull ? "n" : e["tone"].string
        expiresAfterWeeks = e["exp"].int
        minimumCompanyAgeWeeks = e["minWeek"].int
        automatic = e["auto"].bool
        automaticEffects = e["fx"]
        condition = e["cond"].isNull ? nil : Formula(e["cond"]["expr"].string)
        options = e["opts"].array.map { Option(label: $0["l"].string, detail: $0["d"].string, effects: $0["fx"]) }
        lawyerHelps = e["lawyer"].bool
    }
}

public struct EventLibrary: Sendable {
    public let events: [String: GameEvent]
    /// Events with their own special code instead of data effects. Original: `SPEC`.
    public let special: Set<String>

    public init(json: JSONValue) {
        var map: [String: GameEvent] = [:]
        for (k, v) in json["events"].object { map[k] = GameEvent(id: k, json: v) }
        events = map
        special = Set(json["special"].array.map { $0.string })
    }

    public static func bundled() throws -> EventLibrary {
        guard let url = Bundle.module.url(forResource: "events", withExtension: "json", subdirectory: "Resources") else { throw CocoaError(.fileNoSuchFile) }
        return EventLibrary(json: try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)))
    }

    public subscript(id: String) -> GameEvent? { events[id] }
}
