import Foundation
import GameCore
import Businesses

public enum TutorialStep: String, CaseIterable, Sendable {
    case openCompany, setPrice, nextDay, openInbox, readInbox, claimGoal

    /// Steps that only open a screen: doing a later step shows the player got there, so they count as done.
    var opensAScreen: Bool { self == .openCompany || self == .openInbox }

    var following: TutorialStep? {
        let all: [TutorialStep] = TutorialStep.allCases
        guard let i = all.firstIndex(of: self), i + 1 < all.count else { return nil }
        return all[i + 1]
    }

    /// Reads a saved step. Saves made while the guide still had a supplier step resume on the price step.
    init?(saved raw: String) {
        if raw == "pickSupplier" { self = .setPrice; return }
        self.init(rawValue: raw)
    }
}

/// Screens the guide waits for the player to open.
public enum TutorialPlace: Sendable {
    case company, inbox
}

public enum Tutorial {
    public static let key = "tutorial"

    public static func step(_ s: GameState) -> TutorialStep? {
        guard let v = s.rest[key], !v.isNull, !v["done"].bool else { return nil }
        return TutorialStep(saved: v["step"].string)
    }

    public static func isComplete(_ s: GameState) -> Bool { step(s) == nil }

    public static func start(_ s: inout GameState) {
        s.rest[key] = .object(["step": .string(TutorialStep.openCompany.rawValue)])
    }

    /// The one completion of a step: every action that does it calls this, whatever screen or button it came from.
    /// Doing a step also completes the screen-opening steps before it, so a player who found the way alone is never held back.
    public static func advance(_ s: inout GameState, from done: TutorialStep) {
        guard let now = step(s) else { return }
        let all: [TutorialStep] = TutorialStep.allCases
        guard let i = all.firstIndex(of: now), let j = all.firstIndex(of: done), i <= j else { return }
        if i < j && !all[i..<j].allSatisfy({ (t: TutorialStep) -> Bool in t.opensAScreen }) { return }
        if let next = done.following { s.rest[key] = .object(["step": .string(next.rawValue)]) } else { finish(&s) }
        skipEmptySteps(&s)
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

    /// Ends the guide when its company is gone, and passes a reading step with nothing to read.
    public static func sync(_ s: inout GameState) {
        guard step(s) != nil else { return }
        if !s.companies.contains(where: { (c: Company) -> Bool in c.status.isLive }) { finish(&s); return }
        skipEmptySteps(&s)
    }

    static func skipEmptySteps(_ s: inout GameState) {
        if step(s) == .readInbox, inboxGuide(s).isEmpty { advance(&s, from: .readInbox) }
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

    /// The player reached a screen the guide waits for, by any way of getting there.
    mutating func tutorialSaw(_ place: TutorialPlace, now: Date = Date()) {
        switch place {
        case .company: tutorialAdvance(from: .openCompany, now: now)
        case .inbox: tutorialAdvance(from: .openInbox, now: now)
        }
    }

    /// Steps with nothing to do pass on their own: a company with nothing to price, an inbox with nothing new, a reward that is not ready.
    mutating func settleTutorial(now: Date = Date()) {
        if tutorialStep == .setPrice, !tutorialHasSomethingToPrice {
            update { s, _, _ in Tutorial.advance(&s, from: .setPrice) }
        }
        update { s, _, _ in Tutorial.sync(&s) }
        guard tutorialStep == .claimGoal, claimableGoals(now: now).isEmpty else { return }
        update { s, _, _ in Tutorial.finish(&s) }
    }

    /// Whether the guide's company has a product to pick or a price the owner sets.
    private var tutorialHasSomethingToPrice: Bool {
        guard let co = state.companies.first(where: { (c: Company) -> Bool in c.status.isLive }) else { return false }
        if needsFirstItemChoice(companyID: co.id) { return true }
        return salesItems(companyID: co.id).contains { (i: SalesItem) -> Bool in i.priceSetter.isOwner }
    }

    /// Reading a message is the inbox step's completion, from the list, a swipe or the message itself.
    mutating func markMessageRead(_ id: Int, now: Date = Date()) {
        var read = false
        update { s, _, _ in
            guard let i = s.inbox.firstIndex(where: { (m: Message) -> Bool in m.id == id }) else { return }
            if !s.inbox[i].isRead { s.inbox[i].isRead = true }
            read = true
        }
        if read { tutorialAdvance(from: .readInbox, now: now) }
    }

    mutating func tutorialRestart() {
        update { s, _, _ in Tutorial.start(&s) }
        settleTutorial()
    }

    mutating func tutorialFinish() { update { s, _, _ in Tutorial.finish(&s) } }

    var tutorialInboxGuide: [Int] { Tutorial.inboxGuide(state) }
}
