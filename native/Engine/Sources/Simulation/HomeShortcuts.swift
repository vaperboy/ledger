import Foundation
import GameCore

/// The shortcut boxes on Home: the player picks up to four. The choice is kept per game, in the save (`rest["homeBoxes"]`),
/// and the key is written only once the player has chosen: a game that never touched it is byte-identical to before.
/// The engine stores identifiers only; the app owns the catalogue of what each identifier opens.
public extension GameEngine {
    static let homeShortcutLimit = 4

    /// The saved choice, or nil when the player never chose (the app then shows its default four).
    var homeShortcutIDs: [String]? {
        guard let v = state.rest["homeBoxes"] else { return nil }
        return v.array.map { $0.string }
    }

    /// Stores the choice: blank and repeated identifiers are dropped and at most four are kept, in the order given.
    /// Passing nil (or nothing valid) returns to the default and removes the key. Returns what was stored.
    @discardableResult
    mutating func setHomeShortcutIDs(_ ids: [String]?) -> [String]? {
        var kept: [String] = []
        for raw in ids ?? [] {
            let id = raw.trimmingCharacters(in: .whitespaces)
            if id.isEmpty || id.count > 24 || kept.contains(id) { continue }
            kept.append(id)
            if kept.count == Self.homeShortcutLimit { break }
        }
        update { s, _, _ in s.rest["homeBoxes"] = kept.isEmpty ? nil : .array(kept.map { .string($0) }) }
        return kept.isEmpty ? nil : kept
    }
}
