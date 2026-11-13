import Foundation
import GameCore

/// The order answers are shown in. "No" answers (decline, skip, wait) always come first, on top or on the left;
/// the answers that act come after them, in their own order. Tapping a shown answer still sends its original index.
public enum DecisionOrder {
    static let noWords: Set<String> = ["no", "pass", "later"]
    static let noStarts: [String] = ["decline", "politely decline", "no thanks", "say no", "skip", "not now", "not yet", "ignore",
                                     "do nothing", "refuse", "reject", "turn down", "stay out", "stay home", "stay quiet", "leave it", "let it go",
                                     "wait", "hold and wait", "hope", "keep things as they are", "keep normal hours", "keep your rates",
                                     "keep the team as it is", "thank them, change nothing", "say thanks, not now", "carry on as usual"]

    /// True when the label turns the offer down or leaves things as they are.
    public static func isNo(_ label: String) -> Bool {
        let t: String = label.trimmingCharacters(in: .whitespaces).lowercased()
        if noWords.contains(t) { return true }
        return noStarts.contains { (w: String) -> Bool in t == w || t.hasPrefix(w + " ") || t.hasPrefix(w + ",") || t.hasPrefix(w + ":") }
    }

    /// Original option indices in the order to show them.
    public static func shown(_ labels: [String]) -> [Int] {
        let no: [Int] = labels.indices.filter { (i: Int) -> Bool in isNo(labels[i]) }
        if no.isEmpty || no.count == labels.count { return Array(labels.indices) }
        let rest: [Int] = labels.indices.filter { (i: Int) -> Bool in !no.contains(i) }
        return no + rest
    }

    public static func shown(_ m: Message) -> [Int] {
        shown(m.options.map { (o: JSONValue) -> String in o["l"].string })
    }
}
