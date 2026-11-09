import Foundation
import GameCore
import Businesses

/// The five guided steps of a new player, in order. The step lives in the save (`rest["tutorial"]`). Every step can be skipped.
public enum TutorialStep: String, CaseIterable, Sendable {
    // The supplier is asked when the first product is picked, so it comes before the price.
    case openCompany, pickSupplier, setPrice, nextDay, claimGoal

    var following: TutorialStep? {
        let all: [TutorialStep] = TutorialStep.allCases
        guard let i = all.firstIndex(of: self), i + 1 < all.count else { return nil }
        return all[i + 1]
    }
}

public enum Tutorial {
    public static let key = "tutorial"

    /// The step the player is on; nil when the tutorial is finished or the game never had one.
    public static func step(_ s: GameState) -> TutorialStep? {
        guard let v = s.rest[key], !v.isNull, !v["done"].bool else { return nil }
        return TutorialStep(rawValue: v["step"].string)
    }

    public static func isComplete(_ s: GameState) -> Bool { step(s) == nil }

    public static func start(_ s: inout GameState) {
        s.rest[key] = .object(["step": .string(TutorialStep.openCompany.rawValue)])
    }

    /// Moves on from `from` when the player is on it; a step that is not the current one changes nothing, so a repeat is harmless.
    public static func advance(_ s: inout GameState, from: TutorialStep) {
        guard step(s) == from else { return }
        if let next = from.following { s.rest[key] = .object(["step": .string(next.rawValue)]) } else { finish(&s) }
    }

    public static func finish(_ s: inout GameState) {
        guard s.rest[key] != nil else { return }
        s.rest[key] = .object(["done": .bool(true)])
    }
}

public extension GameEngine {
    var tutorialStep: TutorialStep? { Tutorial.step(state) }
    var tutorialComplete: Bool { Tutorial.isComplete(state) }

    /// The player did what the step asked (the app reports the steps that are only a screen being opened).
    mutating func tutorialAdvance(from step: TutorialStep) { update { s, _, _ in Tutorial.advance(&s, from: step) } }

    /// Starts the guide again from the first step (Settings > Replay the tutorial).
    mutating func tutorialRestart() { update { s, _, _ in Tutorial.start(&s) } }

    /// Ends the tutorial early.
    mutating func tutorialFinish() { update { s, _, _ in Tutorial.finish(&s) } }
}
