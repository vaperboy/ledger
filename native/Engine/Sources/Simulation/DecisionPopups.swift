import Foundation
import GameCore
import Finance
import Businesses

/// Which one place an open decision shows in. A decision is never in two at once.
public enum DecisionChannel: Equatable, Sendable {
    /// A Home popup, one at a time, oldest first.
    case home
    /// The inbox: the player chose "Later", or the answer needs the inbox's own flow.
    case inbox
    /// The Desk app hosts the weekly plan while the Desk is open.
    case desk
}

public enum DecisionPopups {
    /// Decisions whose answer runs through a screen of its own rather than a plain choice.
    static let inboxOnlyActions: Set<String> = [PersonalFinance.dueAction]

    public static func channel(_ m: Message, _ s: GameState) -> DecisionChannel {
        if m.actionID == WeeklyFocus.action && DeskStories.isOpen(s) { return .desk }
        if m.deferred || m.route != .decision || inboxOnlyActions.contains(m.actionID) { return .inbox }
        return .home
    }

    static func waiting(_ m: Message) -> Bool { m.status == "open" && m.isOwnerAddressed && !m.options.isEmpty }
}

public extension GameEngine {
    /// Open decisions waiting for their Home popup, oldest first.
    var popupDecisions: [Message] {
        state.inbox.filter { (m: Message) -> Bool in DecisionPopups.waiting(m) && DecisionPopups.channel(m, state) == .home }
            .sorted { (a: Message, b: Message) -> Bool in a.id < b.id }
    }

    /// Serious news whose one-time popup has not been shown yet, oldest first.
    var popupAlerts: [Message] {
        state.inbox.filter { (m: Message) -> Bool in m.route == .alert && !m.alertShown && !m.isRead }
            .sorted { (a: Message, b: Message) -> Bool in a.id < b.id }
    }

    func decisionChannel(_ m: Message) -> DecisionChannel { DecisionPopups.channel(m, state) }

    /// "Later" on the Home popup: the decision moves to the inbox and can be answered there until it expires.
    mutating func deferDecision(messageID: Int) {
        update { s, _, _ in if let k = s.inbox.firstIndex(where: { (m: Message) -> Bool in m.id == messageID }) { s.inbox[k].deferred = true } }
    }

    mutating func markAlertShown(messageID: Int) {
        update { s, _, _ in if let k = s.inbox.firstIndex(where: { (m: Message) -> Bool in m.id == messageID }) { s.inbox[k].alertShown = true } }
    }
}
