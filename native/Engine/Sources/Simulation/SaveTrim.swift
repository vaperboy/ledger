import Foundation
import GameCore
import Businesses

/// Keeps a long career's save small: old answered messages and long-idle people nobody points at are dropped.
public enum SaveTrim {
    /// Answered or informational messages kept, newest first; every open message is always kept.
    public static let doneMessagesKept = 300
    /// Weeks a person must sit without a job before they can be forgotten.
    public static let idleWeeks = 26
    /// How often the people sweep runs, in weeks; it walks the whole save, so it does not run every week.
    static let peopleSweepEvery = 4

    public static func weekly(_ s: inout GameState) {
        trimInbox(&s)
        if s.week % peopleSweepEvery == 0 { prunePeople(&s) }
    }

    /// Keeps every open message and the newest `doneMessagesKept` of the rest, in their original order.
    public static func trimInbox(_ s: inout GameState) {
        let done = s.inbox.filter { $0.status != "open" }
        guard done.count > doneMessagesKept else { return }
        let keep = Set(done.sorted { $0.id > $1.id }.prefix(doneMessagesKept).map { $0.id })
        s.inbox.removeAll { $0.status != "open" && !keep.contains($0.id) }
    }

    /// Forgets people who have had no job for `idleWeeks` and whose id appears nowhere else in the save.
    public static func prunePeople(_ s: inout GameState) {
        var idle: [Int] = []
        for id in s.people.keys.sorted() {
            guard var p = s.people[id] else { continue }
            let jobless = p.employerID == 0 || p.employerID == Hiring.goneElsewhere
            if !jobless {
                if p.raw["idleW"] != nil { p.raw.removeValue(forKey: "idleW"); s.people[id] = p }
                continue
            }
            if p.raw["idleW"] == nil { p.set("idleW", s.week); s.people[id] = p; continue }
            if s.week - p.int("idleW") >= idleWeeks { idle.append(id) }
        }
        guard !idle.isEmpty else { return }
        let candidates = Set(idle)
        var seen = Set<Int>()
        func walk(_ v: JSONValue) {
            switch v {
            case .number(let n): if n == n.rounded(), abs(n) < 1e15 { seen.insert(Int(n)) }
            case .array(let a): for x in a { walk(x) }
            case .object(let o):
                for (k, x) in o {
                    if let n = Int(k) { seen.insert(n) }
                    walk(x)
                }
            default: break
            }
        }
        for co in s.companies { walk(.object(co.raw)) }
        for m in s.inbox { walk(.object(m.raw)) }
        for l in s.loans { walk(.object(l.raw)) }
        walk(.object(s.player.raw))
        walk(.object(s.rest))
        for (id, p) in s.people where !candidates.contains(id) { walk(.object(p.raw)) }
        for id in idle where !seen.contains(id) { s.people.removeValue(forKey: id) }
    }
}
