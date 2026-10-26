import Foundation
import GameCore

/// What a setting-style action did, so the screen can say so: `applied` (something changed), `unchanged` (it was already so, or
/// the thing it refers to has gone) or `refused` with the reason to show the player.
public enum SettingResult: Equatable, Sendable {
    case applied
    case unchanged
    case refused(String)

    public var isRefused: Bool { if case .refused = self { return true } else { return false } }
    public var didChange: Bool { self == .applied }
    /// The reason when refused.
    public var reason: String? { if case .refused(let r) = self { return r } else { return nil } }
}

public extension GameState {
    /// The whole record of one company as data, for comparing before and after an action. `.null` when it does not exist.
    func companySnapshot(_ id: Int) -> JSONValue {
        guard let co = company(id), let d = try? JSONEncoder().encode(co), let v = try? JSONDecoder().decode(JSONValue.self, from: d) else { return .null }
        return v
    }
}

public extension GameEngine {
    /// Runs `body` when `refuse` finds no reason not to, and reports whether `probe` (the part of the state the action writes)
    /// changed. The one way setting-style actions report their result.
    mutating func applySetting(refuse: (GameState) -> String? = { _ in nil }, probe: (GameState) -> JSONValue,
                               _ body: (inout GameState, GameData, FinanceContext) -> Void) -> SettingResult {
        if let why = refuse(state) { return .refused(why) }
        let before = probe(state)
        update(body)
        return probe(state) == before ? .unchanged : .applied
    }
}
