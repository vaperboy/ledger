import Foundation
import GameCore

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
