import Foundation
import GameCore

/// Which Inbox answers need a second question and which are simply sent. Pure, so it can be tested as a table.
///
/// A routine reply (acknowledge, accept a small offer, wait, decline) is sent at once. A reply is confirmed only when it
/// is consequential: it spends money (the amount decides, against the player's "how much I decide" size), or it cannot be undone
/// (a sale, a settlement paid to a court, a ransom, a successor or ownership change, a dismissal).
public struct DecisionConfirmation: Equatable, Sendable {
    /// The most money the answer can cost (in the company's currency); nil when it spends nothing.
    public var amount: Double?
    /// The answer cannot be undone, so it is always confirmed whatever the amount.
    public var irreversible: Bool
    /// True when the player must be asked (a spend is still subject to the size they chose; see the app's confirm rule).
    public var needsQuestion: Bool { irreversible || (amount ?? 0) > 0 }
}

public enum DecisionConfirm {
    /// Inbox actions whose non-declining answers move ownership, pay a court or a criminal, or change who runs a company.
    static let irreversibleActions: Set<String> = ["g27bid", "g27poach", "own27", "mgrsucc", "mgrpoach", "cy56r", "sue16", "fav31"]

    /// Words in an option label that mark an answer that ends something.
    static let irreversibleWords: [String] = ["sell ", "fire", "dismiss", "sack", "close ", "wind up", "terminate", "let go", "merge", "go to court", "settle"]

    /// Words that mark an answer that commits nothing.
    static let declineWords: [String] = ["decline", "no thanks", "not now", "ignore", "wait", "refuse", "reject", "keep ", "understood", "later", "turn down"]

    /// The most an option's effects can cost: certain cash out, a fine, or the worst case of a gamble.
    static func spend(_ fx: JSONValue) -> Double {
        if fx.isNull { return 0 }
        var out: Double = max(0, -fx["cash"].double)
        out += abs(fx["fine"].double)
        out = max(out, abs(fx["loss"].double))
        if !fx["gamble"].isNull {
            out = max(out, spend(fx["gamble"]["ok"]), spend(fx["gamble"]["bad"]))
        }
        return out
    }

    /// "No", "Decline", "Not now", "Ignore", "Wait": answers that never commit anything.
    static func isDecline(_ label: String) -> Bool {
        label == "no" || declineWords.contains { label.contains($0) }
    }

    public static func confirmation(for message: Message, option index: Int) -> DecisionConfirmation {
        guard message.options.indices.contains(index) else { return DecisionConfirmation(amount: nil, irreversible: false) }
        // Payroll approvals are routine, whatever they cost: the wages are already owed.
        if message.actionID.hasPrefix("pay29") { return DecisionConfirmation(amount: nil, irreversible: false) }
        let opt: JSONValue = message.options[index]
        let amount: Double = spend(opt["fx"])
        let label: String = opt["l"].string.lowercased()
        let declines: Bool = isDecline(label)
        var irreversible: Bool = false
        if !declines {
            irreversible = irreversibleActions.contains(message.actionID) && message.options.count > 1
            if !irreversible { irreversible = irreversibleWords.contains { label.contains($0) } }
        }
        return DecisionConfirmation(amount: amount > 0 ? amount : nil, irreversible: irreversible)
    }
}

/// The one rule for when the game stops to ask "Are you sure": only for a spend at or above the player's "Ask before spending" size, and
/// for anything that cannot be undone. Everything else applies at once. Pure, so the app (every confirmation, Inbox answers included)
/// and the tests share it.
public enum ConfirmRule {
    /// - Parameters:
    ///   - irreversible: the action cannot be undone (a sale, a dismissal, closing, converting): always asked.
    ///   - amount: the money the action spends, in the currency `limit` is expressed in; nil or zero when it spends nothing.
    ///   - limit: the player's size under which a spend is not asked; 0 means "always ask a spend"; nil when the spend's currency is unknown
    ///     (then a spend is asked, because it cannot be compared).
    public static func asks(irreversible: Bool, amount: Double?, limit: Double?) -> Bool {
        if irreversible { return true }
        guard let amount, amount > 0 else { return false }
        guard let limit else { return true }
        if limit <= 0 { return true }
        return amount >= limit
    }
}
