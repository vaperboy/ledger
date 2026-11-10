import Foundation
import GameCore

public extension GameEngine {
    static let homeShortcutLimit = 4

    var homeShortcutIDs: [String]? {
        guard let v = state.rest["homeBoxes"] else { return nil }
        return v.array.map { $0.string }
    }

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
