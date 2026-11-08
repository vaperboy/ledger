import Foundation
import GameCore
import Businesses

public extension GameEngine {
    /// The mode this game is played in (Classic for a save that has none).
    var difficulty: Difficulty { Difficulty.of(state) }

    /// Choose the mode once, before the first day has passed. Later calls, and any call after the game has started, change nothing and return false.
    @discardableResult
    mutating func setDifficulty(_ d: Difficulty) -> Bool {
        guard state.week == 0, state.day == 0, state.rest["difficultyLocked"] == nil else { return false }
        update { s, _, _ in
            s.rest[Difficulty.restKey] = .string(d.rawValue)
            s.rest["difficultyLocked"] = .number(1)
        }
        return true
    }
}
