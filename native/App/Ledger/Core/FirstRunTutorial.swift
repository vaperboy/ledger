import Foundation
import Simulation

extension GameStore {
    var tutorialStep: TutorialStep? { engine?.tutorialStep }
    var tutorialActive: Bool { tutorialStep != nil }

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

    func tutorialReplay() {
        act { (e: inout GameEngine) in e.tutorialRestart() }
    }

    func noteTutorialDone() {
        if tutorialStep == nil { FirstRunFlags.mark(FirstRunFlags.tour) }
    }
}
