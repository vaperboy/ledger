import Foundation
import GameCore
import Countries
import Finance

/// Progressive unlocks: a small registry of features that open when they make sense in real
/// life. Locked items stay visible with a one-line reason, except those marked `hiddenUntilUnlocked` (meaningless before). Nothing ever locks
/// something the company already uses. The weekly sweep records a newly satisfied unlock once per company in `rest["unlk"]`
/// { "<companyID>": { "<id>": { w: week it opened, shown: 0 or 1 } } }; a save without `unlk` is seeded silently (all satisfied unlocks shown).
public struct UnlockItem: Equatable, Sendable {
    public var id: String
    public var companyID: Int
    public var title: String
    public var unlocked: Bool
    /// "Unlocks when ..." while locked; "Open" once unlocked.
    public var reason: String
    /// Week the unlock was recorded (nil until the sweep has seen it).
    public var since: Int?
    /// True when the page is meaningless before and may be hidden until unlocked.
    public var hiddenUntilUnlocked: Bool
    /// True when opening is never announced (always there for any open company).
    public var silent: Bool
    /// Where "Take me there" goes: a Group entity section key ("board", "money", "expansion"), "research" (company Market tab) or "marketplace".
    public var target: String
}

public enum Unlocks {
    static let key = "unlk"
    public static let weeksChain = 52
    public static let weeksResearch = 8

    struct Def {
        var id: String
        var title: String
        var hidden: Bool
        var silent: Bool
        var target: String
    }
    static let defs: [Def] = [
        Def(id: "board", title: "Board", hidden: true, silent: false, target: "board"),
        Def(id: "chain", title: "Chain", hidden: false, silent: false, target: "expansion"),
        Def(id: "franchise", title: "Franchising", hidden: false, silent: false, target: "expansion"),
        Def(id: "abroad", title: "Expand abroad", hidden: false, silent: false, target: "expansion"),
        Def(id: "research", title: "Market research", hidden: false, silent: false, target: "research"),
        Def(id: "dividends", title: "Dividends", hidden: false, silent: false, target: "money"),
        Def(id: "marketplace", title: "Marketplace", hidden: false, silent: true, target: "marketplace"),
    ]

    /// Weeks the company has traded (0 until it opens).
    public static func weeksTraded(_ s: GameState, _ co: Company) -> Int {
        guard let w = co.openedWeek else { return 0 }
        return max(0, s.week - w)
    }

    /// Profit of the last twelve closed months, or nil with fewer than twelve.
    public static func yearProfit(_ co: Company) -> Double? {
        let h = co.monthlyHistory.suffix(12)
        return h.count == 12 ? h.reduce(0.0) { $0 + $1.profit } : nil
    }

    /// Closed months on record, up to twelve (the progress towards a profitable year).
    public static func monthsClosed(_ co: Company) -> Int { min(12, co.monthlyHistory.count) }

    /// Someone could sit on the board now: a board exists (a chain, or co-owners), a search already lined up candidates, or a limited company
    /// has a manager who could take a seat.
    static func boardPossible(_ s: GameState, _ co: Company) -> Bool {
        let k = ManagerModel.boardKey(s, co)
        if ManagerModel.boardActive(s, key: k) { return true }
        if !ManagerModel.board(s, key: k)["cands"].array.isEmpty { return true }
        return co.form == .limited && co.managerID != nil
    }

    static func check(_ d: Def, _ s: GameState, _ co: Company, context: FinanceContext) -> (ok: Bool, reason: String) {
        let weeks = weeksTraded(s, co)
        switch d.id {
        case "board":
            return (boardPossible(s, co), "Unlocks when a limited company has a manager or candidate who could take a seat, or it gets co-owners or a chain")
        case "chain":
            let ok = weeks >= weeksChain || !co.value("chain").isNull || co.value("fr")["on"].bool
            return (ok, "Unlocks when the company has traded \(weeksChain) weeks (\(weeks) so far)")
        case "franchise":
            let ok = co.value("fr")["on"].bool || Franchising.provenConcept(s, co).ok
            return (ok, "Unlocks with a proven concept: \(weeksChain) weeks traded and four profitable quarters")
        case "abroad":
            let ok = (yearProfit(co) ?? 0) > 0 || !Abroad.foreignCountries(s).isEmpty
            return (ok, "Unlocks after a profitable year (twelve closed months in profit)")
        case "research":
            let ok = weeks >= weeksResearch || !co.value("res27")["r"].array.isEmpty
            return (ok, "Unlocks when the company is \(weeksResearch) weeks old (\(weeks) so far)")
        case "dividends":
            let limited = co.form == .limited
            let ok = limited && (co.distributed > 0 || Payments.maximumDividend(co, state: s, context: context) > 0)
            return (ok, limited ? "Unlocks when the company has retained profit to pay out" : "Unlocks for a limited company with retained profit")
        default:
            return (co.status.isLive, "Unlocks when the company exists")
        }
    }

    // MARK: Records

    static func record(_ s: GameState, _ cid: Int, _ id: String) -> JSONValue? {
        guard let t: JSONValue = s.rest[key] else { return Optional<JSONValue>.none }
        let r: JSONValue = t["\(cid)"][id]
        if r.isNull { return Optional<JSONValue>.none }
        return Optional<JSONValue>.some(r)
    }

    /// JSONValue is ExpressibleByNilLiteral, so `x == nil` on an optional JSONValue does not mean "absent": test with a pattern instead.
    static func hasTable(_ s: GameState) -> Bool {
        if case .some = s.rest[key] { return true }
        return false
    }

    static func hasRecord(_ s: GameState, _ cid: Int, _ id: String) -> Bool {
        if case .some = record(s, cid, id) { return true }
        return false
    }

    static func put(_ s: inout GameState, _ cid: Int, _ id: String, week: Int, shown: Bool) {
        var t: JSONValue = s.rest[key] ?? .object([:])
        var c: JSONValue = t["\(cid)"]
        if c.isNull { c = .object([:]) }
        c[id] = .object(["w": .number(Double(week)), "shown": .number(shown ? 1 : 0)])
        t["\(cid)"] = c
        s.rest[key] = t
    }

    // MARK: Reads

    public static func state(_ s: GameState, companyID: Int, context: FinanceContext) -> [UnlockItem] {
        guard let co = s.company(companyID) else { return [] }
        var out: [UnlockItem] = []
        for d in defs {
            let c = check(d, s, co, context: context)
            let ok: Bool = c.ok || (co.type == "hold" && d.id != "board")
            out.append(UnlockItem(id: d.id, companyID: companyID, title: d.title, unlocked: ok, reason: ok ? "Open" : c.reason,
                                  since: record(s, companyID, d.id)?["w"].int, hiddenUntilUnlocked: d.hidden, silent: d.silent, target: d.target))
        }
        return out
    }

    /// Recorded unlocks that were never shown to the player, oldest first.
    public static func pending(_ s: GameState, context: FinanceContext) -> [UnlockItem] {
        guard hasTable(s) else { return [] }
        var out: [UnlockItem] = []
        for co in s.companies where co.status.isLive {
            for it in state(s, companyID: co.id, context: context) where it.unlocked && !it.silent {
                guard let r = record(s, co.id, it.id), r["shown"].int == 0 else { continue }
                out.append(it)
            }
        }
        return out.sorted { (a: UnlockItem, b: UnlockItem) -> Bool in
            let wa: Int = a.since ?? 0
            let wb: Int = b.since ?? 0
            if wa != wb { return wa < wb }
            if a.companyID != b.companyID { return a.companyID < b.companyID }
            return a.id < b.id
        }
    }

    public static func markShown(_ s: inout GameState, id: String, companyID: Int) {
        guard let r = record(s, companyID, id) else { return }
        put(&s, companyID, id, week: r["w"].int, shown: true)
    }

    // MARK: Weekly sweep

    public static func weekly(_ s: inout GameState, context: FinanceContext) {
        let first: Bool = !hasTable(s)
        if first { s.rest[key] = .object([:]) }
        let ids: [Int] = s.companies.filter { (c: Company) -> Bool in (first ? c.status.isLive : (c.status == .open || c.status == .closed)) && c.type != "hold" }.map { (c: Company) -> Int in c.id }
        for id in ids {
            for it in state(s, companyID: id, context: context) where it.unlocked && !hasRecord(s, id, it.id) {
                put(&s, id, it.id, week: s.week, shown: first || it.silent)
            }
        }
    }
}
