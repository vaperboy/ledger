import Foundation
import GameCore
import Countries

public enum Budget: Int, CaseIterable, Comparable, Sendable {
    case tight = 0, normal, free

    public static func < (a: Budget, b: Budget) -> Bool { a.rawValue < b.rawValue }

    public var title: String {
        switch self { case .tight: return "Tight"; case .normal: return "Normal"; case .free: return "Free" }
    }

    public var text: String {
        switch self { case .tight: return "asks you first"; case .normal: return "decides within your limits"; case .free: return "decides on their own" }
    }

    public static let unlimited = 1e12

    public var actsAlone: Bool { self != .tight }

    public func spendLimit(_ cur: Currency, kind: String = "mgr", monthlyRevenue: Double = 0) -> Double {
        switch self {
        case .tight: return 0
        case .free: return Budget.unlimited
        case .normal:
            switch kind {
            case "region": return cur.scaledPrice(80000)
            case "chainmgr": return cur.scaledPrice(250000)
            case "ceo56": return cur.scaledPrice(600000)
            case "mdir": return cur.scaledPrice(100000)
            case "md": return cur.scaledPrice(2000000)
            default: return max(cur.scaledPrice(25000), cur.roundedStep(monthlyRevenue * 0.08, about: 1000))
            }
        }
    }

    public func payLimit(_ cur: Currency, kind: String = "mgr", monthlyRevenue: Double = 0) -> Double {
        let spend = spendLimit(cur, kind: kind, monthlyRevenue: monthlyRevenue)
        return self == .free ? spend : cur.tidy(spend / 3)
    }

    public func covers(_ amount: Double, monthly: Bool = false, _ cur: Currency, kind: String = "mgr", monthlyRevenue: Double = 0) -> Bool {
        amount <= (monthly ? payLimit(cur, kind: kind, monthlyRevenue: monthlyRevenue) : spendLimit(cur, kind: kind, monthlyRevenue: monthlyRevenue))
    }

    public static func of(_ rec: JSONValue) -> Budget {
        if !rec["bud"].isNull { return Budget(rawValue: min(2, max(0, rec["bud"].int))) ?? .normal }
        return nearest(level: rec["lvl"].int, buy: rec["buy"].double)
    }

    static func isChosen(_ rec: JSONValue) -> Bool { rec["chosen"].bool || rec["set22"].bool }

    public static func nearest(level: Int, buy: Double) -> Budget {
        if level >= 2 { return .free }
        if level == 1 { return buy > 0 ? .normal : .tight }
        return .tight
    }

    static let legacyKeys: Set<String> = ["lvl", "buy"]

    public static func write(_ b: Budget, into rec: inout JSONValue) {
        var o = rec.object.filter { !legacyKeys.contains($0.key) }
        o["bud"] = .number(Double(b.rawValue))
        rec = .object(o)
    }

    static func authRecord(_ b: Budget, spend: Double, chosen: Bool) -> JSONValue {
        .object(["bud": .number(Double(b.rawValue)), "lvl": .number(Double(b.rawValue)), "buy": .number(spend), "chosen": .bool(chosen)])
    }

    static var initialAuth: JSONValue { authRecord(.tight, spend: 0, chosen: false) }

    public static func migrate(_ s: inout GameState) {
        func fix(_ rec: JSONValue) -> JSONValue {
            guard rec["bud"].isNull, !(rec["lvl"].isNull && rec["buy"].isNull) else { return rec }
            var r = rec
            write(of(rec), into: &r)
            return r
        }
        ManagerModel.retireLegacyProposals(&s)
        for i in s.companies.indices {
            var a = s.companies[i].value("auth")
            if !a.isNull, a["bud"].isNull {
                let b = of(a)
                a = authRecord(b, spend: b == .normal ? a["buy"].double : b == .free ? unlimited : 0, chosen: isChosen(a))
                s.companies[i].set("auth", a)
            }
            var t = s.companies[i].value("team")
            if !t.isNull {
                if !t["ceo"].isNull { t["ceo"] = fix(t["ceo"]) }
                var h = t["heads"]
                for (k, v) in h.object { h[k] = fix(v) }
                if !h.isNull { t["heads"] = h }
                s.companies[i].set("team", t)
            }
        }
        if var g = s.rest["group"] {
            g["regional"] = .array(g["regional"].array.map(fix))
            if !g["ceo"].isNull { g["ceo"] = fix(g["ceo"]) }
            s.rest["group"] = g
        }
        if var o = s.rest["org56"], !o["md"].isNull { o["md"] = fix(o["md"]); s.rest["org56"] = o }
        if let chains = s.rest["chains"] {
            s.rest["chains"] = .array(chains.array.map { (chain: JSONValue) -> JSONValue in
                var c = chain
                if !c["ceo56"].isNull { c["ceo56"] = fix(c["ceo56"]) }
                return c
            })
        }
    }
}

public extension ManagerModel {
    static func recentMonthlyRevenue(_ co: Company) -> Double {
        let h = co.monthlyHistory.suffix(3)
        return h.isEmpty ? 0 : h.reduce(0) { $0 + $1.revenue } / Double(h.count)
    }

    static func budget(of co: Company) -> Budget { Budget.of(co.value("auth")) }

    static func spendLimit(of co: Company, _ s: GameState, data: GameData) -> Double {
        budget(of: co).spendLimit(World(state: s, data: data).currency(co), monthlyRevenue: recentMonthlyRevenue(co))
    }

    static func withinBudget(_ co: Company, amount: Double, monthly: Bool = false, _ s: GameState, data: GameData) -> Bool {
        guard co.managerID != nil else { return false }
        return budget(of: co).covers(amount, monthly: monthly, World(state: s, data: data).currency(co), monthlyRevenue: recentMonthlyRevenue(co))
    }

    static func setBudget(_ s: inout GameState, companyID: Int, budget: Budget, data: GameData) {
        guard let ci = s.companyIndex(companyID) else { return }
        let co = s.companies[ci]
        let spend = budget.spendLimit(World(state: s, data: data).currency(co), monthlyRevenue: recentMonthlyRevenue(co))
        s.companies[ci].set("auth", Budget.authRecord(budget, spend: spend, chosen: true))
    }

    static func setTeamBudget(_ s: inout GameState, companyID: Int, budget: Budget) {
        guard let ci = s.companyIndex(companyID) else { return }
        var t = team(s.companies[ci])
        guard !t["ceo"].isNull else { return }
        Budget.write(budget, into: &t["ceo"])
        s.companies[ci].set("team", t)
    }

    static func setExecutiveBudget(_ s: inout GameState, level: ExecLevel, chainID: Int? = nil, regionalID: Int? = nil, budget: Budget) {
        switch level {
        case .md:
            var m = s.rest["org56"]?["md"] ?? .null
            guard !m.isNull else { return }
            Budget.write(budget, into: &m)
            s.rest["org56"] = (s.rest["org56"] ?? .object([:])).with("md", m)
        case .ceo56:
            guard let id = chainID, var ch = Chains.chain(s, id: id), !ch["ceo56"].isNull else { return }
            var c = ch["ceo56"]; Budget.write(budget, into: &c); ch["ceo56"] = c; Chains.save(&s, ch)
        default:
            updateGroup(&s) { g in
                var l = g["regional"].array
                if let k = l.firstIndex(where: { $0["id"].int == regionalID }) { Budget.write(budget, into: &l[k]); g["regional"] = .array(l) }
            }
        }
    }
}
