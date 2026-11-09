import Foundation
import Simulation

/// The guided first steps of a new player (`Tutorial` in the engine keeps the step in the save). The views read these to know what to
/// point at, what to hold back and when the guide is over.
extension GameStore {
    /// The step the guide is on; nil once it is finished (or for a game that never had one).
    var tutorialStep: TutorialStep? { engine?.tutorialStep }
    var tutorialActive: Bool { tutorialStep != nil }

    /// True while the player must pick the first product and set its price: Next day and every way out of that flow wait.
    var tutorialHoldsDay: Bool { tutorialStep?.locksPlay == true }

    func tutorialAdvance(from step: TutorialStep) {
        guard tutorialStep == step else { return }
        act { (e: inout GameEngine) in e.tutorialAdvance(from: step) }
        noteTutorialDone()
    }

    func tutorialFinish() {
        guard tutorialActive else { return }
        act { (e: inout GameEngine) in e.tutorialFinish() }
        noteTutorialDone()
    }

    /// Once the guide is over the first-session flag is set too, so no older intro appears on this install.
    func noteTutorialDone() {
        if tutorialStep == nil { FirstRunFlags.mark(FirstRunFlags.tour) }
    }
}
