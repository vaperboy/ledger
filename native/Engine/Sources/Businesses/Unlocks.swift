import Foundation
import GameCore
import Countries
import Finance

/// Every feature outside the core game. Each opens at its own player level, one per level.
public enum LevelFeature: String, CaseIterable, Sendable {
    case marketing, marketplace, management, newCompany, techpro, insurance, auctions, weeklyPlan, research, rivals, desk
    case exchange, chain, ventures, franchise, jointVentures, government, abroad, politics, luxury
}

/// The XP curve shared by the level bar and the unlock table.
public enum LevelCurve {
    public static let maxLevel = 100

    public static func threshold(_ level: Int) -> Int { 25 * level * max(0, level - 1) }

    public static func level(forXP xp: Int) -> Int {
        var l = 1
        while l < maxLevel && threshold(l + 1) <= xp { l += 1 }
        return l
    }

    public static func xp(_ s: GameState) -> Int { max(0, s.rest["lvl"]?["xp"].int ?? 0) }
    public static func level(_ s: GameState) -> Int { level(forXP: xp(s)) }
}

/// The one unlock table. Level 1 is the core game (products, prices, staff, premises, bank, suppliers, inbox, goals);
/// every other feature opens at its listed level and stays shut until then.
public enum FeatureUnlocks {
    public struct Row: Equatable, Sendable {
        public var feature: LevelFeature
        public var level: Int
        public var title: String
        public var gives: String
    }

    public static let table: [Row] = [
        Row(feature: .marketing, level: 2, title: "Marketing", gives: "advertise to bring in more customers and see what they say about you"),
        Row(feature: .marketplace, level: 3, title: "Marketplace", gives: "buy used items from private sellers and haggle"),
        Row(feature: .management, level: 4, title: "Managers", gives: "hire a manager to run a company day to day"),
        Row(feature: .newCompany, level: 5, title: "More companies", gives: "start a second company and see them all as one group"),
        Row(feature: .techpro, level: 6, title: "TechPro", gives: "buy software, equipment and vehicles that make a company work better"),
        Row(feature: .insurance, level: 7, title: "Insurance", gives: "cover your companies against fire, theft and lawsuits"),
        Row(feature: .auctions, level: 8, title: "Auctions", gives: "sell your artifacts or bid on other players' pieces"),
        Row(feature: .weeklyPlan, level: 9, title: "Weekly plan", gives: "pick one thing each company focuses on this week"),
        Row(feature: .research, level: 10, title: "Market research", gives: "study a market before you spend on it"),
        Row(feature: .rivals, level: 11, title: "Rivals", gives: "watch the competition in your market and answer their moves"),
        Row(feature: .desk, level: 12, title: "Desk", gives: "answer one small question a day that shapes a company's story"),
        Row(feature: .exchange, level: 13, title: "Stock exchange", gives: "list a company and sell shares in it"),
        Row(feature: .chain, level: 14, title: "Start a chain", gives: "turn a company into a chain of stores under one name"),
        Row(feature: .ventures, level: 15, title: "Ventures", gives: "start startups, back funds and make group deals"),
        Row(feature: .franchise, level: 16, title: "Franchise this company", gives: "let other owners open units under your name"),
        Row(feature: .jointVentures, level: 17, title: "Joint ventures", gives: "start a company together with a friend"),
        Row(feature: .government, level: 18, title: "Government", gives: "see the treasury, tax rates and the president"),
        Row(feature: .abroad, level: 19, title: "Expand abroad", gives: "open a subsidiary of a company in another country"),
        Row(feature: .politics, level: 20, title: "Politics", gives: "donate, stand in elections and shape the law"),
        Row(feature: .luxury, level: 21, title: "Luxury", gives: "spend your wealth on cars, art, yachts and homes"),
    ]

    public static func row(_ f: LevelFeature) -> Row {
        table.first { (r: Row) -> Bool in r.feature == f } ?? Row(feature: f, level: LevelCurve.maxLevel, title: f.rawValue, gives: "")
    }

    public static func unlockLevel(_ f: LevelFeature) -> Int { row(f).level }

    public static func lockLine(_ f: LevelFeature) -> String { "Unlocks at level \(unlockLevel(f))" }

    /// Saves without the ladder are never gated; features a save already opened under older rules stay open.
    public static func isUnlocked(_ f: LevelFeature, _ s: GameState) -> Bool {
        guard s.rest["ldr"] != nil else { return true }
        return LevelCurve.level(s) >= unlockLevel(f) || openedBefore(f, s)
    }

    /// The next feature the player will open, lowest level first.
    public static func nextUnlock(_ s: GameState) -> Row? {
        table.filter { (r: Row) -> Bool in !isUnlocked(r.feature, s) }.min { (a: Row, b: Row) -> Bool in a.level < b.level }
    }

    public static func unlocks(atLevel l: Int) -> [Row] { table.filter { (r: Row) -> Bool in r.level == l } }

    public static var highestLevel: Int { table.map { (r: Row) -> Int in r.level }.max() ?? 1 }

    /// A refusal line for engine actions behind a locked feature, nil when it is open.
    public static func refusal(_ f: LevelFeature, _ s: GameState) -> String? {
        isUnlocked(f, s) ? nil : row(f).title + " " + lockLine(f).lowercased()
    }

    static func openedBefore(_ f: LevelFeature, _ s: GameState) -> Bool {
        let seen: [JSONValue] = s.rest["lvl"]?["seen"].array ?? []
        if seen.contains(where: { (v: JSONValue) -> Bool in v.string == "level." + f.rawValue }) { return true }
        let gates: JSONValue = s.rest[Gates.openKey] ?? .null
        if Gate.allCases.contains(where: { (g: Gate) -> Bool in g.feature == f && !gates[g.rawValue].isNull }) { return true }
        let opened: JSONValue = s.rest[Unlocks.globalKey] ?? .null
        return Unlocks.defs.contains { (d: Unlocks.Def) -> Bool in d.feature == f && !opened[d.id].isNull }
    }
}

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

    struct Def {
        var id: String
        var title: String
        var hidden: Bool
        var silent: Bool
        var target: String
        var feature: LevelFeature
    }

    /// Per-company pages. Each opens with its level feature; the board also needs someone who could take a seat.
    static let defs: [Def] = [
        Def(id: "board", title: "Board", hidden: true, silent: false, target: "board", feature: .management),
        Def(id: "research", title: "Market research", hidden: false, silent: true, target: "research", feature: .research),
        Def(id: "marketplace", title: "Marketplace", hidden: false, silent: true, target: "marketplace", feature: .marketplace),
        Def(id: "desk", title: "Desk", hidden: true, silent: true, target: "desk", feature: .desk),
        Def(id: "focus", title: "Weekly plan", hidden: true, silent: true, target: "focus", feature: .weeklyPlan),
        Def(id: "rivals", title: "Rivals", hidden: true, silent: true, target: "rivals", feature: .rivals),
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

    /// A page is open once its level is reached or once it was opened before; the board waits for a seat to fill.
    public static func isOpen(_ s: GameState, _ id: String) -> Bool {
        if playerHas(s, id) { return true }
        guard let d = defs.first(where: { (x: Def) -> Bool in x.id == id }), d.id != "board" else { return false }
        return FeatureUnlocks.isUnlocked(d.feature, s)
    }

    static func check(_ d: Def, _ s: GameState, _ co: Company, context: FinanceContext) -> (ok: Bool, reason: String) {
        guard FeatureUnlocks.isUnlocked(d.feature, s) || alreadyUses(d.id, s, co) else { return (false, FeatureUnlocks.lockLine(d.feature)) }
        if d.id == "board" { return (boardPossible(s, co), "Opens when a manager or candidate could take a seat") }
        return (true, "")
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
            let ok: Bool = c.ok || playerHas(s, d.id)
            out.append(UnlockItem(id: d.id, companyID: companyID, title: d.title, unlocked: ok, reason: ok ? "Open" : c.reason,
                                  since: record(s, d.id)?["w"].int, hiddenUntilUnlocked: d.hidden, silent: d.silent, target: d.target))
        }
        return out
    }

    public static func pending(_ s: GameState, context: FinanceContext) -> [UnlockItem] {
        guard case .some(let g) = s.rest[globalKey] else { return [] }
        let live: [Company] = s.companies.filter { (c: Company) -> Bool in c.status.isLive }
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
        let ids: [Int] = s.companies.filter { (c: Company) -> Bool in (first ? c.status.isLive : (c.status == .open || c.status == .closed)) }.map { (c: Company) -> Int in c.id }
        for id in ids {
            for it in state(s, companyID: id, context: context) where it.unlocked && !hasRecord(s, it.id) {
                put(&s, it.id, week: s.week, shown: first || it.silent, company: id)
            }
        }
    }
}
