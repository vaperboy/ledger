import Foundation
import GameCore
import Businesses
import Finance

public enum SettingResult: Equatable, Sendable {
    case applied
    case unchanged
    case refused(String)

    public var isRefused: Bool { if case .refused = self { return true } else { return false } }
    public var didChange: Bool { self == .applied }
    public var reason: String? { if case .refused(let r) = self { return r } else { return nil } }
}

public extension GameState {
    func companySnapshot(_ id: Int) -> JSONValue {
        guard let co = company(id), let d = try? JSONEncoder().encode(co), let v = try? JSONDecoder().decode(JSONValue.self, from: d) else { return .null }
        return v
    }
}

public extension GameEngine {
    mutating func applySetting(refuse: (GameState) -> String? = { _ in nil }, probe: (GameState) -> JSONValue,
                               _ body: (inout GameState, GameData, FinanceContext) -> Void) -> SettingResult {
        if let why = refuse(state) { return .refused(why) }
        let before = probe(state)
        update(body)
        return probe(state) == before ? .unchanged : .applied
    }
}
