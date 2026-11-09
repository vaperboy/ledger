import Foundation
import GameCore
import Businesses

/// The guided first steps of a new player, in order. The step lives in the save (`rest["tutorial"]`), so it survives closing the app.
/// A save without the key (an older game, a story that starts without it) has no tutorial and counts as complete.
public enum TutorialStep: String, CaseIterable, Sendable {
    case pickProduct, setPrice, nextDay, openInbox, readInbox

    var following: TutorialStep? {
        let all: [TutorialStep] = TutorialStep.allCases
        guard let i = all.firstIndex(of: self), i + 1 < all.count else { return nil }
        return all[i + 1]
    }

    /// Steps the player must finish in place: nothing else (back, tabs, Next day) is open until they are done.
    public var locksPlay: Bool { self == .pickProduct || self == .setPrice }
}

public enum Tutorial {
    public static let key = "tutorial"

    /// The step the player is on; nil when the tutorial is finished or the game never had one.
    public static func step(_ s: GameState) -> TutorialStep? {
        guard let v = s.rest[key], !v.isNull, !v["done"].bool else { return nil }
        return TutorialStep(rawValue: v["step"].string)
    }

    public static func isComplete(_ s: GameState) -> Bool { step(s) == nil }

    /// Begins the tutorial on the first step.
    public static func start(_ s: inout GameState) {
        s.rest[key] = .object(["step": .string(TutorialStep.pickProduct.rawValue)])
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

    /// The messages the player should open next while the tutorial runs: the newest few unread ones that are information, not a decision.
    public static func inboxGuide(_ s: GameState) -> [Int] {
        let info: [Message] = s.inbox.filter { (m: Message) -> Bool in !(m.status == "open" && m.isOwnerAddressed) && !m.isRead }
        let sorted: [Message] = info.sorted { (a: Message, b: Message) -> Bool in a.week != b.week ? a.week > b.week : a.id > b.id }
        return sorted.prefix(3).map { (m: Message) -> Int in m.id }
    }
}

public extension GameEngine {
    var tutorialStep: TutorialStep? { Tutorial.step(state) }
    var tutorialComplete: Bool { Tutorial.isComplete(state) }

    /// The player did what the step asked (the app reports the steps that are only a screen being opened).
    mutating func tutorialAdvance(from step: TutorialStep) { update { s, _, _ in Tutorial.advance(&s, from: step) } }

    /// Ends the tutorial early (a step that does not lock play may be skipped).
    mutating func tutorialFinish() { update { s, _, _ in Tutorial.finish(&s) } }

    /// "Keep this price": the price the company already has is the one the player chose.
    mutating func tutorialKeepPrice() { tutorialAdvance(from: .setPrice) }

    var tutorialInboxGuide: [Int] { Tutorial.inboxGuide(state) }
}
