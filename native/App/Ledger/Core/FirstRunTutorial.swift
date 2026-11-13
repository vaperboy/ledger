import Foundation
import Simulation

extension GameStore {
    var tutorialStep: TutorialStep? { engine?.tutorialStep }
    var tutorialActive: Bool { tutorialStep != nil }

    /// Runs on the next main-loop turn, so a navigation change never publishes inside a view update.
    func routeChanged() {
        guard tutorialActive else { return }
        Task { @MainActor [weak self] in self?.noteTutorialRoute() }
    }

    /// Navigation is the action for the screen-opening steps: whatever opened the company or the Inbox, the guide hears it here.
    func noteTutorialRoute() {
        guard let step = tutorialStep else { return }
        let top: NavRoute? = path(for: tab).last
        switch step {
        case .openCompany:
            guard top?.companyID != nil else { return }
            act { (e: inout GameEngine) in e.tutorialSaw(.company) }
        case .openInbox:
            guard showsApp(.inbox) else { return }
            act { (e: inout GameEngine) in e.tutorialSaw(.inbox) }
        default:
            return
        }
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
