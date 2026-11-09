import Foundation
import GameCore
import Countries
import Finance

/// Progressive unlocks: a small registry of features that open when they make sense in real
/// life. Locked items stay visible with a one-line reason, except those marked `hiddenUntilUnlocked` (meaningless before). Nothing ever locks
/// something the company already uses. Unlocks belong to the player: the first company to meet a condition opens the feature for every
/// company, present and future, and the weekly sweep records it once in `rest["unlkG"]` { "<id>": { w: week it opened, shown: 0 or 1,
/// c: company that earned it } }. A save without it is seeded silently (all satisfied unlocks shown); the older per-company table
/// `rest["unlk"]` is merged into it on the first sweep.
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
    static let globalKey = "unlkG"
    public static let weeksChain = 52
    public static let weeksResearch = 8
    /// Weeks of trading before the calm engagement pages open (Desk, weekly plan, Rivals); never inside the first-session ladder.
    public static let weeksDesk = 6, weeksFocus = 8, weeksRivals = 12

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
        Def(id: "desk", title: "Desk", hidden: true, silent: true, target: "desk"),
        Def(id: "focus", title: "Weekly plan", hidden: true, silent: true, target: "focus"),
        Def(id: "rivals", title: "Rivals", hidden: true, silent: true, target: "rivals"),
    ]

    /// True when the player has already earned this unlock through any company (or the older per-company table holds it).
    static func playerHas(_ s: GameState, _ id: String) -> Bool {
        if case .some(let g) = s.rest[globalKey], !g[id].isNull { return true }
        guard case .some(let t) = s.rest[key] else { return false }
        for cid in t.object.keys where !t[cid][id].isNull { return true }
        return false
    }

    /// Ids of every unlock the player has earned, in registry order.
    public static func unlockedFeatures(_ s: GameState) -> [String] {
        defs.map { (d: Def) -> String in d.id }.filter { (id: String) -> Bool in playerHas(s, id) }
    }

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

    /// The board matters now: it exists (a chain, or co-owners), or a limited company has a manager who advises it.
    static func boardPossible(_ s: GameState, _ co: Company) -> Bool {
        if ManagerModel.boardActive(s, key: ManagerModel.boardKey(s, co)) { return true }
        return co.form == .limited && co.managerID != nil
    }

    /// A company that already uses a feature keeps it, whatever the rule says.
    static func alreadyUses(_ id: String, _ s: GameState, _ co: Company) -> Bool {
        switch id {
        case "chain": return !co.value("chain").isNull || co.value("fr")["on"].bool
        case "franchise": return co.value("fr")["on"].bool
        case "abroad": return !Abroad.foreignCountries(s).isEmpty
        case "research": return !co.value("res27")["r"].array.isEmpty
        default: return false
        }
    }

    /// The first-session ladder is over (first profitable month done); a game without a ladder is always past it.
    static func ladderPast(_ s: GameState) -> Bool { !Gates.ladderOn(s) || Gates.goalDone(s, 7) }

    /// A player-level engagement page (`desk`, `focus`, `rivals`) has opened for any company of the player (recorded by the weekly sweep).
    public static func isOpen(_ s: GameState, _ id: String) -> Bool { playerHas(s, id) }

    /// The rule and its words come from `Gates.table`; this adds what the company already uses and the progress count.
    static func check(_ d: Def, _ s: GameState, _ co: Company, context: FinanceContext) -> (ok: Bool, reason: String) {
        if d.id == "desk" || d.id == "focus" || d.id == "rivals" {
            let need: Int = d.id == "desk" ? weeksDesk : d.id == "focus" ? weeksFocus : weeksRivals
            let weeks: Int = weeksTraded(s, co)
            return (weeks >= need && ladderPast(s), "Unlocks when the company has traded \(need) weeks (\(weeks) so far) and the first steps are done")
        }
        let e: RuleEntry = Gates.entry(.unlock(d.id))
        let ok: Bool = Gates.met(e.rule, s, data: nil, company: co, context: context) || alreadyUses(d.id, s, co)
        var reason: String = e.text
        if case .weeksTraded = e.rule { reason += " (\(weeksTraded(s, co)) so far)" }
        if d.id == "dividends" && co.form != .limited { reason = "Unlocks for a limited company with retained profit" }
        return (ok, reason)
    }

    // MARK: Records

    /// JSONValue is ExpressibleByNilLiteral, so `x == nil` on an optional JSONValue does not mean "absent": test with a pattern instead.
    static func record(_ s: GameState, _ id: String) -> JSONValue? {
        guard let g: JSONValue = s.rest[globalKey] else { return Optional<JSONValue>.none }
        let r: JSONValue = g[id]
        if r.isNull { return Optional<JSONValue>.none }
        return Optional<JSONValue>.some(r)
    }

    static func hasRecord(_ s: GameState, _ id: String) -> Bool {
        if case .some = record(s, id) { return true }
        return false
    }

    static func put(_ s: inout GameState, _ id: String, week: Int, shown: Bool, company: Int) {
        var g: JSONValue = s.rest[globalKey] ?? .object([:])
        g[id] = .object(["w": .number(Double(week)), "shown": .number(shown ? 1 : 0), "c": .number(Double(company))])
        s.rest[globalKey] = g
    }

    /// Merges the older per-company records into the player's table: the earliest week wins, and an unlock counts as shown only when
    /// every record of it was shown.
    public static func migrate(_ s: inout GameState) {
        if case .some = s.rest[globalKey] { return }
        guard case .some(let t) = s.rest[key] else { return }
        var g: JSONValue = .object([:])
        for cid in t.object.keys.sorted() {
            for id in t[cid].object.keys.sorted() {
                let r: JSONValue = t[cid][id]
                let w: Int = r["w"].int
                let shown: Bool = r["shown"].int != 0
                let comp: Double = Double(Int(cid) ?? 0)
                let old: JSONValue = g[id]
                if old.isNull {
                    g[id] = .object(["w": .number(Double(w)), "shown": .number(shown ? 1 : 0), "c": .number(comp)])
                } else {
                    let earlier: Bool = w < old["w"].int
                    g[id] = .object(["w": .number(Double(min(w, old["w"].int))), "shown": .number(shown && old["shown"].int != 0 ? 1 : 0),
                                     "c": earlier ? .number(comp) : old["c"]])
                }
            }
        }
        s.rest[globalKey] = g
    }

    // MARK: Reads

    public static func state(_ s: GameState, companyID: Int, context: FinanceContext) -> [UnlockItem] {
        guard let co = s.company(companyID) else { return [] }
        var out: [UnlockItem] = []
        for d in defs {
            let c = check(d, s, co, context: context)
            let ok: Bool = c.ok || (co.type == "hold" && d.id != "board") || playerHas(s, d.id)
            out.append(UnlockItem(id: d.id, companyID: companyID, title: d.title, unlocked: ok, reason: ok ? "Open" : c.reason,
                                  since: record(s, d.id)?["w"].int, hiddenUntilUnlocked: d.hidden, silent: d.silent, target: d.target))
        }
        return out
    }

    /// Unlocks the player earned and has not been told about yet, oldest first: one per unlock, not one per company. Each item names the
    /// company that earned it (or the first live company when that one is gone) for the announcement and its target.
    public static func pending(_ s: GameState, context: FinanceContext) -> [UnlockItem] {
        guard case .some(let g) = s.rest[globalKey] else { return [] }
        let live: [Company] = s.companies.filter { (c: Company) -> Bool in c.status.isLive && c.type != "hold" }
        var out: [UnlockItem] = []
        for d in defs where !d.silent {
            let r: JSONValue = g[d.id]
            if r.isNull || r["shown"].int != 0 { continue }
            guard let co = live.first(where: { (c: Company) -> Bool in c.id == r["c"].int }) ?? live.first else { continue }
            if let it = state(s, companyID: co.id, context: context).first(where: { (u: UnlockItem) -> Bool in u.id == d.id }) { out.append(it) }
        }
        return out.sorted { (a: UnlockItem, b: UnlockItem) -> Bool in
            let wa: Int = a.since ?? 0
            let wb: Int = b.since ?? 0
            if wa != wb { return wa < wb }
            return a.id < b.id
        }
    }

    /// The player has seen the announcement. The unlock is the player's, so `companyID` is not used.
    public static func markShown(_ s: inout GameState, id: String, companyID: Int) {
        guard let r = record(s, id) else { return }
        put(&s, id, week: r["w"].int, shown: true, company: r["c"].int)
    }

    // MARK: Weekly sweep

    public static func weekly(_ s: inout GameState, context: FinanceContext) {
        migrate(&s)
        var first: Bool = true
        if case .some = s.rest[globalKey] { first = false } else { s.rest[globalKey] = .object([:]) }
        let ids: [Int] = s.companies.filter { (c: Company) -> Bool in (first ? c.status.isLive : (c.status == .open || c.status == .closed)) && c.type != "hold" }.map { (c: Company) -> Int in c.id }
        for id in ids {
            for it in state(s, companyID: id, context: context) where it.unlocked && !hasRecord(s, it.id) {
                put(&s, it.id, week: s.week, shown: first || it.silent, company: id)
            }
        }
    }
}
