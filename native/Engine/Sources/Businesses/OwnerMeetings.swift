import Foundation
import GameCore
import Countries
import Employees
import Finance

public enum OwnerMeetings {
    public static let cooldownWeeks = 13
    public static let directives: [(key: String, label: String)] = [("growth", "Grow"), ("lean", "Keep costs lean"), ("quality", "Quality first"), ("cash", "Keep cash")]
    static let reviewTopic = "review"
    static let groups = ["direction", "budget"]

    public struct Counterpart: Identifiable, Equatable, Sendable {
        public var id: Int
        public var name: String
        public var title: String
        public var position: String
        public var companyID: Int
    }
    public struct Topic: Identifiable, Equatable, Sendable {
        public var id: String
        public var label: String
        public var hint: String
        public var waitWeeks: Int
    }
    public struct Choice: Identifiable, Equatable, Sendable {
        public var id: String
        public var label: String
        public var preview: String
        public var group: String = ""
    }
    public struct Scene: Equatable, Sendable {
        public var companyID: Int
        public var personID: Int
        public var topic: String
        public var speaker: String
        public var lines: [String]
        public var choices: [Choice]
    }
    public struct Outcome: Equatable, Sendable {
        public var text: String
        public var tone: String
        public var resigned: Bool
    }

    public static func counterparts(_ s: GameState, companyID: Int) -> [Counterpart] {
        guard let co = s.company(companyID), co.status.isLive, co.type != "hold" else { return [] }
        var out: [Counterpart] = []
        var seen = Set<Int>()
        let t = ManagerModel.team(co)
        if let n = ManagerModel.person(s, t["ceo"]), seen.insert(n.id).inserted { out.append(Counterpart(id: n.id, name: n.name, title: "CEO", position: "ceo", companyID: companyID)) }
        if let mid = co.managerID, let n = s.people[mid], seen.insert(n.id).inserted { out.append(Counterpart(id: n.id, name: n.name, title: "Manager", position: "ceo", companyID: companyID)) }
        for r in ManagerModel.teamRoles {
            if let n = ManagerModel.person(s, t["heads"][r.key]), seen.insert(n.id).inserted { out.append(Counterpart(id: n.id, name: n.name, title: r.title, position: r.key, companyID: companyID)) }
        }
        for seat in ManagerModel.seats(s, key: ManagerModel.boardKey(s, co)) {
            if let n = s.people[seat.id], seen.insert(n.id).inserted {
                out.append(Counterpart(id: n.id, name: n.name, title: seat.title, position: seatPosition(seat.role), companyID: companyID))
            }
        }
        return out
    }

    static func seatPosition(_ role: String) -> String {
        switch role {
        case "cfo", "analyst", "chair", "director": return "fin"
        default: return "ops"
        }
    }

    public static let topicTable: [String: [(String, String, String)]] = [
        "ceo": [(reviewTopic, "Quarterly review", "The quarter so far, your direction and their budget")],
    ]

    public static func topics(_ s: GameState, companyID: Int, personID: Int) -> [Topic] {
        guard let c = counterparts(s, companyID: companyID).first(where: { $0.id == personID }) else { return [] }
        return (topicTable[c.position] ?? []).map { Topic(id: $0.0, label: $0.1, hint: $0.2, waitWeeks: waitWeeks(s, companyID: companyID, personID: personID, topic: $0.0)) }
    }

    static func memoKey(_ co: Int, _ p: Int, _ group: String) -> String { "\(co):\(p):\(group)" }
    static func groupWait(_ s: GameState, _ co: Int, _ p: Int, _ group: String) -> Int {
        guard let w = s.rest["ownerMtg"]?[memoKey(co, p, group)], !w.isNull else { return 0 }
        return max(0, w.int + cooldownWeeks - s.week)
    }
    public static func waitWeeks(_ s: GameState, companyID: Int, personID: Int, topic: String) -> Int {
        topic == reviewTopic ? (groups.map { groupWait(s, companyID, personID, $0) }.min() ?? 0) : 0
    }
    static func stamp(_ s: inout GameState, _ co: Int, _ p: Int, _ group: String) {
        var m = s.rest["ownerMtg"] ?? .object([:])
        for (k, v) in m.object where v.int + cooldownWeeks <= s.week { m[k] = .null }
        m[memoKey(co, p, group)] = .number(Double(s.week))
        s.rest["ownerMtg"] = .object(m.object.filter { !$0.value.isNull })
    }

    public static func directive(_ co: Company) -> String? { let d = co.str("dir"); return d.isEmpty ? nil : d }
    public static func directiveLabel(_ key: String) -> String { directives.first { $0.key == key }?.label ?? key }

    public static func bias(directive d: String, kind: String) -> Double {
        let favoured: [String: Set<String>] = ["growth": ["hire", "mkt_more", "price_down", "eq"], "lean": ["cut", "save", "mkt_less", "price_up"],
                                               "quality": ["quality", "eq", "hire"], "cash": ["save", "cut", "price_up"]]
        let against: [String: Set<String>] = ["growth": ["cut", "save"], "lean": ["hire", "mkt_more", "eq"], "quality": ["cut", "save"], "cash": ["eq", "hire", "mkt_more"]]
        return favoured[d]?.contains(kind) == true ? 0.8 : against[d]?.contains(kind) == true ? -0.5 : 0
    }

    static func budget(_ s: GameState, _ co: Company, personID: Int) -> Budget {
        co.managerID == personID ? ManagerModel.budget(of: co) : Budget.of(ManagerModel.team(co)["ceo"])
    }

    struct Facts {
        var cur: Currency
        var rev = 0.0, profit = 0.0, p3 = 0.0, r3 = 0.0, prevP3: Double? = nil, avgProfit = 0.0
        var util = 0.0, cash = 0.0, debt = 0.0, mood = 60.0, awareness = 0.0
        var staff = 0, notice = 0
    }
    static func facts(_ s: GameState, _ co: Company, data: GameData) -> Facts {
        var f = Facts(cur: World(state: s, data: data).currency(co))
        let h = co.monthlyHistory
        f.rev = h.last?.revenue ?? 0; f.profit = h.last?.profit ?? 0
        let last3 = h.suffix(3)
        f.p3 = last3.reduce(0) { $0 + $1.profit }; f.r3 = last3.reduce(0) { $0 + $1.revenue }
        f.avgProfit = last3.isEmpty ? 0 : f.p3 / Double(last3.count)
        if h.count >= 6 { f.prevP3 = h.dropLast(3).suffix(3).reduce(0) { $0 + $1.profit } }
        f.util = co.value("lastW")["util"].double
        f.cash = co.cash
        f.debt = s.loans.filter { $0.companyID == co.id }.reduce(0) { $0 + $1.balance }
        f.mood = ManagerModel.mood(co)
        f.awareness = co.awareness
        f.staff = co.staff.count
        f.notice = co.staff.filter { $0.noticeWeeks > 0 }.count
        return f
    }
    static func pct(_ v: Double) -> String { "\(Int(saturating: jsRound(v * 100)))%" }
    static func money(_ f: Facts, _ v: Double) -> String { v < 0 ? "-" + f.cur.short(-v) : f.cur.short(v) }
    static func moodWord(_ m: Double) -> String { m >= 70 ? "high" : m >= 50 ? "fine" : m >= 35 ? "low" : "bad" }

    static func suggestion(_ f: Facts) -> String {
        if f.cash + f.avgProfit * 3 < 0 { return "cash" }
        if f.p3 < 0 { return "lean" }
        if f.util > 0.85 { return "growth" }
        return f.mood < 45 ? "quality" : "growth"
    }

    static func ch(_ id: String, _ label: String, _ preview: String, _ group: String) -> Choice { Choice(id: id, label: label, preview: preview, group: group) }

    static func directionPreview(_ key: String) -> String {
        switch key {
        case "growth": return "Sales targets stretch. They favour hiring and marketing."
        case "lean": return "Profit targets stretch. They favour savings and cuts."
        case "quality": return "The rating target stretches. They favour upkeep and quality."
        default: return "Profit targets stretch, sales may slip. They favour savings."
        }
    }

    public static func scene(_ s: GameState, companyID: Int, personID: Int, topic: String, data: GameData) -> Scene? {
        guard topic == reviewTopic, let co = s.company(companyID), let c = counterparts(s, companyID: companyID).first(where: { $0.id == personID }), c.position == "ceo" else { return nil }
        let f = facts(s, co, data: data)
        let trend: String = {
            guard let p = f.prevP3 else { return "" }
            return f.p3 >= p ? " That is better than the quarter before." : " That is worse than the quarter before."
        }()
        let dir = directive(co)
        let now = budget(s, co, personID: personID)
        var L: [String] = ["Over three months we took in \(f.cur.short(f.r3)) and \(f.p3 >= 0 ? "made \(f.cur.short(f.p3))" : "lost \(f.cur.short(-f.p3))").\(trend)"]
        if f.util > 0 { L.append("We are using about \(pct(f.util)) of what we can deliver and \(Int(saturating: jsRound(f.awareness)))% of the area knows us.") }
        L.append(f.cash + f.avgProfit * 3 < 0 ? "At this pace cash runs short within three months (cash now \(money(f, f.cash)))."
                 : "Cash stays positive for the next three months (about \(money(f, f.cash + f.avgProfit * 3))). Loans: \(f.debt > 0 ? f.cur.short(f.debt) : "none").")
        L.append("\(f.staff) \(f.staff == 1 ? "person" : "people") on the team, \(f.notice) working their notice. Mood is \(moodWord(f.mood)).")
        L.append("I would lean toward: \(directiveLabel(suggestion(f)).lowercased()). Direction now: \(dir.map { directiveLabel($0).lowercased() } ?? "not set"). Budget now: \(now.title.lowercased()), \(now.text).")
        var C: [Choice] = []
        for d in directives { C.append(ch("dir:\(d.key)", d.label, (d.key == dir ? "Current. " : "") + directionPreview(d.key), "direction")) }
        for b in Budget.allCases {
            let said: String = String(b.text.prefix(1)).uppercased() + String(b.text.dropFirst()) + "."
            C.append(ch("bud:\(b.rawValue)", b.title, (b == now ? "Current. " : "") + said, "budget"))
        }
        return Scene(companyID: companyID, personID: personID, topic: topic, speaker: ManagerModel.firstName(c.name), lines: L, choices: C)
    }

    public static func choose(_ s: inout GameState, companyID: Int, personID: Int, topic: String, choice: String, data: GameData, marketing: MarketingTables) -> Outcome? {
        guard let sc = scene(s, companyID: companyID, personID: personID, topic: topic, data: data), let picked = sc.choices.first(where: { $0.id == choice }),
              let ci = s.companyIndex(companyID) else { return nil }
        let w = groupWait(s, companyID, personID, picked.group)
        if w > 0 { return Outcome(text: "You settled this with \(sc.speaker) this quarter. Give it \(w) \(w == 1 ? "week" : "weeks").", tone: "n", resigned: false) }
        stamp(&s, companyID, personID, picked.group)
        func bump(_ v: Double) { s.companies[ci].set("mood", clamp(ManagerModel.mood(s.companies[ci]) + v, 0, 100)) }
        let key = String(choice.dropFirst(4))
        if picked.group == "direction" {
            s.companies[ci].set("dir", key)
            bump(2)
            if ManagerTargets.eligible(s.companies[ci], data: data), ManagerTargets.current(s.companies[ci], week: s.week) != nil {
                ManagerTargets.setTargets(&s, ci, month: ManagerTargets.mi(s), data: data)
            }
            return Outcome(text: "Direction set: \(directiveLabel(key).lowercased()). \(sc.speaker) will lean that way and decide the small things alone.", tone: "good", resigned: false)
        }
        let b = Budget(rawValue: Int(key) ?? Budget.normal.rawValue) ?? .normal
        if s.companies[ci].managerID == personID { ManagerModel.setBudget(&s, companyID: companyID, budget: b, data: data) }
        else { ManagerModel.setTeamBudget(&s, companyID: companyID, budget: b) }
        bump(b == .free ? 3 : b == .tight ? -3 : 0)
        return Outcome(text: "Budget \(b.title.lowercased()): \(sc.speaker) \(b.text).", tone: b == .tight ? "n" : "good", resigned: false)
    }

    public struct RoundLine: Identifiable, Equatable, Sendable {
        public var id: Int
        public var name: String
        public var title: String
        public var text: String
    }
    public static func isAdvisory(_ s: GameState, companyID: Int) -> Bool {
        guard let co = s.company(companyID) else { return true }
        return !ManagerModel.boardActive(s, key: ManagerModel.boardKey(s, co))
    }

    static func headline(_ c: Counterpart, _ co: Company, _ f: Facts) -> String? {
        switch c.position {
        case "ceo": return "Last month we took in \(f.cur.short(f.rev)) and \(f.profit >= 0 ? "made \(f.cur.short(f.profit))" : "lost \(f.cur.short(-f.profit))")."
        case "fin": return "Cash in the company: \(money(f, f.cash)). Loans: \(f.debt > 0 ? f.cur.short(f.debt) : "none")."
        case "sales": return "We are at \(pct(f.util)) of capacity and \(Int(saturating: jsRound(f.awareness)))% known in the area."
        case "hr": return "We have \(f.staff) \(f.staff == 1 ? "person" : "people"), \(f.notice) working their notice. Mood is \(moodWord(f.mood))."
        case "ops": return "We use \(pct(f.util)) of capacity."
        case "mkt":
            let spend = co.value("mkt").object.values.reduce(0.0) { $0 + $1["b"].double }
            return "\(Int(saturating: jsRound(f.awareness)))% of the area knows us. We spend \(f.cur.short(spend)) a week on marketing."
        default: return nil
        }
    }

    public static func boardRound(_ s: GameState, companyID: Int, data: GameData) -> [RoundLine] {
        guard let co = s.company(companyID) else { return [] }
        let f = facts(s, co, data: data)
        return counterparts(s, companyID: companyID).compactMap { c in
            headline(c, co, f).map { RoundLine(id: c.id, name: c.name, title: c.title, text: $0) }
        }
    }
}
