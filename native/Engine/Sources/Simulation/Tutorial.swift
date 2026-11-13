import Foundation
import GameCore
import Businesses

public enum TutorialStep: String, CaseIterable, Sendable {
    case openCompany, pickSupplier, setPrice, nextDay, openInbox, readInbox, claimGoal

    var following: TutorialStep? {
        let all: [TutorialStep] = TutorialStep.allCases
        guard let i = all.firstIndex(of: self), i + 1 < all.count else { return nil }
        return all[i + 1]
    }
}

public enum Tutorial {
    public static let key = "tutorial"

    public static func step(_ s: GameState) -> TutorialStep? {
        guard let v = s.rest[key], !v.isNull, !v["done"].bool else { return nil }
        return TutorialStep(rawValue: v["step"].string)
    }

    public static func isComplete(_ s: GameState) -> Bool { step(s) == nil }

    public static func start(_ s: inout GameState) {
        s.rest[key] = .object(["step": .string(TutorialStep.openCompany.rawValue)])
    }

    public static func advance(_ s: inout GameState, from: TutorialStep) {
        guard step(s) == from else { return }
        if let next = from.following { s.rest[key] = .object(["step": .string(next.rawValue)]) } else { finish(&s) }
    }

    public static func finish(_ s: inout GameState) {
        guard s.rest[key] != nil else { return }
        s.rest[key] = .object(["done": .bool(true)])
    }

    public static let stepCount: Int = TutorialStep.allCases.count

    public static func position(_ s: GameState) -> Int? {
        guard let st = step(s), let i = TutorialStep.allCases.firstIndex(of: st) else { return nil }
        return i + 1
    }

    public static func sync(_ s: inout GameState) {
        guard step(s) != nil else { return }
        if !s.companies.contains(where: { (c: Company) -> Bool in c.status.isLive }) { finish(&s) }
    }

    public static func inboxGuide(_ s: GameState) -> [Int] {
        let info: [Message] = s.inbox.filter { (m: Message) -> Bool in !(m.status == "open" && m.isOwnerAddressed) && !m.isRead }
        let sorted: [Message] = info.sorted { (a: Message, b: Message) -> Bool in a.week != b.week ? a.week > b.week : a.id > b.id }
        return sorted.prefix(3).map { (m: Message) -> Int in m.id }
    }
}

public extension GameEngine {
    var tutorialStep: TutorialStep? { Tutorial.step(state) }
    var tutorialPosition: Int? { Tutorial.position(state) }
    var tutorialComplete: Bool { Tutorial.isComplete(state) }

    mutating func tutorialAdvance(from step: TutorialStep, now: Date = Date()) {
        update { s, _, _ in Tutorial.advance(&s, from: step) }
        settleTutorial(now: now)
    }

    /// The last step asks for a reward that is ready; with none ready the guide ends instead of waiting days.
    mutating func settleTutorial(now: Date = Date()) {
        guard tutorialStep == .claimGoal, claimableGoals(now: now).isEmpty else { return }
        update { s, _, _ in Tutorial.finish(&s) }
    }

    mutating func tutorialRestart() { update { s, _, _ in Tutorial.start(&s) } }

    mutating func tutorialFinish() { update { s, _, _ in Tutorial.finish(&s) } }

    var tutorialInboxGuide: [Int] { Tutorial.inboxGuide(state) }
}
