import Foundation
import GameCore

public struct DecisionConfirmation: Equatable, Sendable {
    public var amount: Double?
    public var irreversible: Bool
    public var needsQuestion: Bool { irreversible || (amount ?? 0) > 0 }
}

public enum DecisionConfirm {
    static let irreversibleActions: Set<String> = ["g27bid", "g27poach", "own27", "mgrsucc", "mgrpoach", "cy56r", "sue16", "fav31"]

    static let irreversibleWords: [String] = ["sell ", "fire", "dismiss", "sack", "close ", "wind up", "terminate", "let go", "merge", "go to court", "settle"]

    static let declineWords: [String] = ["decline", "no thanks", "not now", "ignore", "wait", "refuse", "reject", "keep ", "understood", "later", "turn down"]

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

    static func isDecline(_ label: String) -> Bool {
        label == "no" || declineWords.contains { label.contains($0) }
    }

    public static func confirmation(for message: Message, option index: Int) -> DecisionConfirmation {
        guard message.options.indices.contains(index) else { return DecisionConfirmation(amount: nil, irreversible: false) }
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

public enum ConfirmRule {
    public static func asks(irreversible: Bool, amount: Double?, limit: Double?) -> Bool {
        if irreversible { return true }
        guard let amount, amount > 0 else { return false }
        guard let limit else { return true }
        if limit <= 0 { return true }
        return amount >= limit
    }
}
