import Foundation
import GameCore
import Countries
import Finance

public struct UnlockItem: Equatable, Sendable {
    public var id: String
    public var companyID: Int
    public var title: String
    public var unlocked: Bool
    public var reason: String
    public var since: Int?
    public var hiddenUntilUnlocked: Bool
    public var silent: Bool
    public var target: String
}

public enum Unlocks {
    static let key = "unlk"
    static let globalKey = "unlkG"
    public static let weeksResearch = 8
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
        Def(id: "research", title: "Market research", hidden: false, silent: false, target: "research"),
        Def(id: "dividends", title: "Dividends", hidden: false, silent: false, target: "money"),
        Def(id: "marketplace", title: "Marketplace", hidden: false, silent: true, target: "marketplace"),
        Def(id: "desk", title: "Desk", hidden: true, silent: true, target: "desk"),
        Def(id: "focus", title: "Weekly plan", hidden: true, silent: true, target: "focus"),
        Def(id: "rivals", title: "Rivals", hidden: true, silent: true, target: "rivals"),
    ]

    static func playerHas(_ s: GameState, _ id: String) -> Bool {
        if case .some(let g) = s.rest[globalKey], !g[id].isNull { return true }
        guard case .some(let t) = s.rest[key] else { return false }
        for cid in t.object.keys where !t[cid][id].isNull { return true }
        return false
    }

    public static func unlockedFeatures(_ s: GameState) -> [String] {
        defs.map { (d: Def) -> String in d.id }.filter { (id: String) -> Bool in playerHas(s, id) }
    }

    public static func weeksTraded(_ s: GameState, _ co: Company) -> Int {
        guard let w = co.openedWeek else { return 0 }
        return max(0, s.week - w)
    }

    static func boardPossible(_ s: GameState, _ co: Company) -> Bool {
        if ManagerModel.boardActive(s, key: ManagerModel.boardKey(s, co)) { return true }
        return co.managerID != nil
    }

    static func alreadyUses(_ id: String, _ s: GameState, _ co: Company) -> Bool {
        switch id {
        case "research": return !co.value("res27")["r"].array.isEmpty
        default: return false
        }
    }

    static let weeksLadderPast = 13

    static func ladderPast(_ s: GameState) -> Bool { !Gates.ladderOn(s) || Gates.goalDone(s, 7) || s.week >= weeksLadderPast }

    public static func isOpen(_ s: GameState, _ id: String) -> Bool { playerHas(s, id) }

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
        return (ok, reason)
    }

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

    public static func markShown(_ s: inout GameState, id: String, companyID: Int) {
        guard let r = record(s, id) else { return }
        put(&s, id, week: r["w"].int, shown: true, company: r["c"].int)
    }

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
