import Foundation
import GameCore

/// How an answer reads: it takes the offer, turns it down, or is one of several equal paths.
public enum DecisionKind: String, Equatable, Sendable {
    case yes, no, neutral
}

/// Where each answer goes. With a yes/no pair, No sits on the left and Yes on the right; every other answer goes in rows below.
/// Without a pair, all answers are equal and stacked in their own order. Tapping a shown answer still sends its original index.
public struct DecisionLayout: Equatable, Sendable {
    /// The answer that turns it down, shown on the left.
    public var no: Int?
    /// The answer that takes it, shown on the right.
    public var yes: Int?
    /// Every other answer, in its own order: below the pair, or stacked when there is no pair.
    public var others: [Int]

    public var hasPair: Bool { no != nil && yes != nil }

    /// Original option indices from top left to bottom right.
    public var order: [Int] { [no, yes].compactMap { (i: Int?) -> Int? in i } + others }

    public func kind(_ index: Int) -> DecisionKind {
        if index == no { return .no }
        if index == yes { return .yes }
        return .neutral
    }
}

public enum DecisionOrder {
    static let noWords: Set<String> = ["no", "pass", "later"]
    static let noStarts: [String] = ["decline", "politely decline", "no thanks", "say no", "skip", "not now", "not yet", "ignore",
                                     "do nothing", "refuse", "reject", "turn down", "stay out", "stay home", "stay quiet", "leave it", "let it go",
                                     "wait", "hold and wait", "hope", "keep things as they are", "keep normal hours", "keep your rates",
                                     "keep the team as it is", "thank them, change nothing", "say thanks, not now", "carry on as usual",
                                     "vote no", "vote against"]
    static let yesWords: Set<String> = ["yes", "ok", "accept", "agree", "approve", "go ahead", "do it", "deal"]
    static let yesStarts: [String] = ["yes", "accept", "agree", "approve", "go ahead", "say yes", "take", "sign", "hire", "buy", "join", "invest",
                                      "book", "vote yes", "vote for", "do it"]

    static func matches(_ label: String, words: Set<String>, starts: [String]) -> Bool {
        let t: String = label.trimmingCharacters(in: .whitespaces).lowercased()
        if words.contains(t) { return true }
        return starts.contains { (w: String) -> Bool in t == w || t.hasPrefix(w + " ") || t.hasPrefix(w + ",") || t.hasPrefix(w + ":") }
    }

    /// True when the label turns the offer down or leaves things as they are.
    public static func isNo(_ label: String) -> Bool { matches(label, words: noWords, starts: noStarts) }

    /// True when the label plainly takes the offer.
    public static func isYes(_ label: String) -> Bool { !isNo(label) && matches(label, words: yesWords, starts: yesStarts) }

    /// A pair needs one answer that turns it down and one that acts. The acting side is the first plain "yes",
    /// or the first acting answer when none says yes outright.
    public static func layout(_ labels: [String]) -> DecisionLayout {
        let no: [Int] = labels.indices.filter { (i: Int) -> Bool in isNo(labels[i]) }
        let acting: [Int] = labels.indices.filter { (i: Int) -> Bool in !isNo(labels[i]) }
        guard let left = no.first, let first = acting.first else { return DecisionLayout(no: nil, yes: nil, others: Array(labels.indices)) }
        let right: Int = acting.first { (i: Int) -> Bool in isYes(labels[i]) } ?? first
        let rest: [Int] = labels.indices.filter { (i: Int) -> Bool in i != left && i != right }
        return DecisionLayout(no: left, yes: right, others: rest)
    }

    public static func layout(_ m: Message) -> DecisionLayout {
        layout(m.options.map { (o: JSONValue) -> String in o["l"].string })
    }

    /// Original option indices in the order to show them.
    public static func shown(_ labels: [String]) -> [Int] { layout(labels).order }

    public static func shown(_ m: Message) -> [Int] { layout(m).order }
}
