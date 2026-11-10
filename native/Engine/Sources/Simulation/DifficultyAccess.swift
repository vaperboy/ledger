import Foundation
import GameCore
import Businesses

public extension GameEngine {
    var difficulty: Difficulty { Difficulty.of(state) }

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
