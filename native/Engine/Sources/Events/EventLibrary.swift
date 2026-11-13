import Foundation
import GameCore
import Businesses

public struct GameEvent: Sendable {
    public struct Option: Sendable {
        public var label: String
        public var detail: String
        public var effects: JSONValue
    }
    public var id: String
    public var text: String
    public var weight: Double
    public var category: String
    public var tone: String
    public var expiresAfterWeeks: Int
    public var minimumCompanyAgeWeeks: Int
    public var automatic: Bool
    public var automaticEffects: JSONValue
    public var condition: Formula?
    public var options: [Option]
    public var lawyerHelps: Bool
    public var blocking: Bool
    /// Trades this event never happens to, and whether it needs a real premises (not a home, a vehicle or a rented-out portfolio).
    public var excludedTrades: Set<String>
    public var needsPremises: Bool

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
        blocking = e["blocking"].bool
        excludedTrades = Set(e["notTr"].array.map { $0.string })
        needsPremises = e["prem"].bool
    }

    /// Whether the event makes sense for this trade.
    func appliesTo(_ bd: Trade) -> Bool {
        if excludedTrades.contains(bd.id) { return false }
        if needsPremises, let k = bd.premisesKind, k != "none", k != "home" { return true }
        return !needsPremises
    }
}

public struct EventLibrary: Sendable {
    public let events: [String: GameEvent]
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
