import Foundation
import GameCore
import Countries
import Employees
import Finance

/// The owner sits down with one person and talks. What they can ask depends on the person's position: the CEO reports on results and
/// answers for decisions, the finance head on cash and margins, the sales director on customers and price, HR on people. Every talk is a
/// short scene (what they say, then two or three choices with a visible consequence). The owner sets direction and expectations; the
/// managers keep the day-to-day. A talk on one topic with one person can be repeated after a cool-down. Saved as `rest["ownerMtg"]`
/// {"company:person:topic": week}; the strategic direction is the company's `dir` ("growth", "lean", "quality", "cash").
public enum OwnerMeetings {
    public static let cooldownWeeks = 3
    public static let directives: [(key: String, label: String)] = [("growth", "Grow"), ("lean", "Keep costs lean"), ("quality", "Quality first"), ("cash", "Keep cash")]

    public struct Counterpart: Identifiable, Equatable, Sendable {
        public var id: Int
        public var name: String
        public var title: String
        /// ceo, fin, sales, hr, ops or mkt.
        public var position: String
        public var companyID: Int
    }
    public struct Topic: Identifiable, Equatable, Sendable {
        public var id: String
        public var label: String
        public var hint: String
        /// Weeks until this talk can be held again (0 = now).
        public var waitWeeks: Int
    }
    public struct Choice: Identifiable, Equatable, Sendable {
        public var id: String
        public var label: String
        /// What it will do, shown before you pick.
        public var preview: String
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

    // MARK: Who and what

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
        // Everyone in a board seat sits at the same table, so they can be talked to and speak in a board round.
        for seat in ManagerModel.seats(s, key: ManagerModel.boardKey(s, co)) {
            if let n = s.people[seat.id], seen.insert(n.id).inserted {
                out.append(Counterpart(id: n.id, name: n.name, title: seat.title, position: seatPosition(seat.role), companyID: companyID))
            }
        }
        return out
    }

    /// The talks a board seat answers: money seats talk finance, the people and marketing seats their field, the rest operations.
    static func seatPosition(_ role: String) -> String {
        switch role {
        case "cfo", "analyst", "chair", "director": return "fin"
        case "mkt": return "mkt"
        case "hr": return "hr"
        default: return "ops"
        }
    }

    public static let topicTable: [String: [(String, String, String)]] = [
        "ceo": [("results", "Go through the results", "Last month and the trend"), ("forecast", "Ask for a forecast", "Where this is heading"),
                ("explain", "Question a decision", "What they did lately and why"), ("challenge", "Challenge the result", "Push back"),
                ("expect", "Set expectations", "Targets for this month"), ("review", "Progress review", "How they have done since they started"),
                ("advice", "Give strategic direction", "Where you want it to go")],
        "fin": [("update", "Financial update", "Cash, debt and profit"), ("forecast", "Cash forecast", "The next three months"), ("margin", "Explain the margin", "Where the money goes")],
        "sales": [("pipeline", "Sales report", "Customers and demand"), ("pricing", "Price or volume?", "What to chase")],
        "hr": [("people", "People report", "Staff, notice and mood")],
        "ops": [("capacity", "Capacity report", "What is stretched"), ("upkeep", "Upkeep and quality", "How much to spend")],
        "mkt": [("reach", "Marketing report", "Reach and awareness")],
    ]

    public static func topics(_ s: GameState, companyID: Int, personID: Int) -> [Topic] {
        guard let c = counterparts(s, companyID: companyID).first(where: { $0.id == personID }) else { return [] }
        return (topicTable[c.position] ?? []).map { Topic(id: $0.0, label: $0.1, hint: $0.2, waitWeeks: waitWeeks(s, companyID: companyID, personID: personID, topic: $0.0)) }
    }

    static func memoKey(_ co: Int, _ p: Int, _ t: String) -> String { "\(co):\(p):\(t)" }
    public static func waitWeeks(_ s: GameState, companyID: Int, personID: Int, topic: String) -> Int {
        guard let w = s.rest["ownerMtg"]?[memoKey(companyID, personID, topic)], !w.isNull else { return 0 }
        return max(0, w.int + cooldownWeeks - s.week)
    }
    static func stamp(_ s: inout GameState, _ co: Int, _ p: Int, _ t: String) {
        var m = s.rest["ownerMtg"] ?? .object([:])
        for (k, v) in m.object where v.int + cooldownWeeks <= s.week { m[k] = .null }   // forget what has run out
        m[memoKey(co, p, t)] = .number(Double(s.week))
        s.rest["ownerMtg"] = .object(m.object.filter { !$0.value.isNull })
    }

    public static func directive(_ co: Company) -> String? { let d = co.str("dir"); return d.isEmpty ? nil : d }
    public static func directiveLabel(_ key: String) -> String { directives.first { $0.key == key }?.label ?? key }

    /// How much a strategic direction favours (+) or disfavours (-) a kind of proposal when the manager ranks them.
    public static func bias(directive d: String, kind: String) -> Double {
        let favoured: [String: Set<String>] = ["growth": ["hire", "mkt_more", "price_down", "eq"], "lean": ["cut", "save", "mkt_less", "price_up"],
                                               "quality": ["quality", "eq", "hire"], "cash": ["save", "cut", "price_up"]]
        let against: [String: Set<String>] = ["growth": ["cut", "save"], "lean": ["hire", "mkt_more", "eq"], "quality": ["cut", "save"], "cash": ["eq", "hire", "mkt_more"]]
        return favoured[d]?.contains(kind) == true ? 0.8 : against[d]?.contains(kind) == true ? -0.5 : 0
    }

    // MARK: Facts the scenes read

    struct Facts {
        var cur: Currency
        var rev = 0.0, profit = 0.0, p3 = 0.0, r3 = 0.0, prevP3: Double? = nil, avgProfit = 0.0
        var util = 0.0, cash = 0.0, debt = 0.0, mood = 60.0, awareness = 0.0
        var staff = 0, notice = 0
        var payroll = 0.0
        var months = 0
    }
    static func facts(_ s: GameState, _ co: Company, data: GameData) -> Facts {
        var f = Facts(cur: World(state: s, data: data).currency(co))
        let h = co.monthlyHistory
        f.months = h.count
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
        f.payroll = co.staff.reduce(0) { $0 + $1.monthlyWage }
        return f
    }
    static func pct(_ v: Double) -> String { "\(Int(jsRound(v * 100)))%" }
    static func money(_ f: Facts, _ v: Double) -> String { v < 0 ? "-" + f.cur.short(-v) : f.cur.short(v) }
    static func moodWord(_ m: Double) -> String { m >= 70 ? "high" : m >= 50 ? "fine" : m >= 35 ? "low" : "bad" }

    // MARK: A talk

    static func ch(_ id: String, _ label: String, _ preview: String) -> Choice { Choice(id: id, label: label, preview: preview) }

    public static func scene(_ s: GameState, companyID: Int, personID: Int, topic: String, data: GameData) -> Scene? {
        guard let co = s.company(companyID), let c = counterparts(s, companyID: companyID).first(where: { $0.id == personID }),
              (topicTable[c.position] ?? []).contains(where: { $0.0 == topic }) else { return nil }
        let f = facts(s, co, data: data)
        let first = ManagerModel.firstName(c.name)
        var L: [String] = []
        var C: [Choice] = []
        let trend: String = {
            guard let p = f.prevP3 else { return "" }
            return f.p3 >= p ? " That is better than the quarter before." : " That is worse than the quarter before."
        }()
        switch (c.position, topic) {
        case ("ceo", "results"):
            L = ["Last month we took in \(f.cur.short(f.rev)) and \(f.profit >= 0 ? "made \(f.cur.short(f.profit))" : "lost \(f.cur.short(-f.profit))").",
                 "Over three months: \(money(f, f.p3)).\(trend)"]
            if f.util > 0 { L.append("We are using about \(pct(f.util)) of what we can deliver.") }
            C = [ch("thanks", "Good work", "They feel noticed. Mood up."), ch("more", "I expected more", "They push harder, and it stings. Mood down."), ch("fix", "Fix the weak spot", "They go after costs now.")]
        case ("ceo", "forecast"):
            let next = f.avgProfit
            L = ["At this pace the next month brings about \(money(f, next)) in profit.",
                 f.cash + next * 3 < 0 ? "Cash would run out in about \(max(1, Int(jsRound(f.cash / max(1, -next))))) months if nothing changes." : "Cash stays positive for the next three months (about \(money(f, f.cash + next * 3)))."]
            if f.prevP3 != nil { L.append(f.p3 >= (f.prevP3 ?? 0) ? "The trend is up." : "The trend is down.") }
            C = [ch("ok", "Good, carry on", "Nothing changes."), ch("grow", "Spend to grow", "Direction: grow. They favour hiring and marketing."), ch("cash", "Keep a cushion", "Direction: keep cash. They favour savings.")]
        case ("ceo", "explain"):
            let log = co.value("mgrLog").array.suffix(3).map { $0["t"].string }.filter { !$0.isEmpty }
            L = log.isEmpty ? ["I have not changed anything lately. The numbers moved by themselves."] : log.map { "I \($0.prefix(1).lowercased() + $0.dropFirst())" }
            L.append(f.util > 0 && f.util < 0.6 ? "We have free capacity, so I went for customers first." : "I kept the service steady and watched the costs.")
            C = [ch("trust", "Fair enough", "They feel trusted. Mood up."), ch("why", "Why not cut costs instead?", "They trim running costs. Mood down a little.")]
        case ("ceo", "challenge"):
            L = [f.profit < 0 ? "I know. We lost \(f.cur.short(-f.profit)) last month and it has to turn." : "We made \(f.cur.short(f.profit)). It is thinner than I want, I agree.",
                 "What do you want me to do about it?"]
            C = [ch("listen", "Hear them out", "They explain. Mood steady."), ch("demand", "Demand a fix", "They cut costs. Mood down."), ch("final", "Final warning", "Mood drops hard. A weak spirit may make them quit.")]
        case ("ceo", "expect"):
            L = ["What do you expect this month? I will plan for it and you can judge me on it at month end."]
            C = [ch("easy", "A steady month", "Easier targets. Mood up."), ch("real", "Realistic targets", "Targets in line with the trend."), ch("stretch", "Stretch targets", "Harder targets. Mood down a little.")]
        case ("ceo", "review"):
            if let rep = ManagerModel.personReport(s, companyID: companyID, personID: personID, data: data) {
                L = ((rep.sections.first?.lines.prefix(4).map { "\($0.label): \($0.value)." } ?? []) + [rep.verdict]).filter { !$0.isEmpty }
            } else { L = ["It is too early to review me. Give it a few months."] }
            C = [ch("ok", "Good, keep going", "They feel trusted. Mood up."), ch("ideas", "Ask for their ideas", "They bring proposals to your Inbox."), ch("bar", "Set a higher bar", "Stretch targets this month. Mood down a little.")]
        case ("ceo", "advice"):
            let now = directive(co).map { " Today I lean toward: \(directiveLabel($0).lowercased())." } ?? ""
            L = ["Tell me where you want this to go and I will decide the small things myself.\(now)"]
            C = directives.prefix(3).map { ch($0.key, $0.label, "Their choices lean this way from now on.") }
        case ("fin", "update"):
            L = ["Cash in the company: \(money(f, f.cash)). Loans: \(f.debt > 0 ? f.cur.short(f.debt) : "none").",
                 "Last month: \(f.profit >= 0 ? "profit" : "loss") \(f.cur.short(abs(f.profit))). Over three months: \(money(f, f.p3))."]
            C = [ch("ok", "Thanks", "Nothing changes."), ch("cushion", "Keep a cash cushion", "Direction: keep cash."), ch("trim", "Trim a cost line", "Upkeep is reduced one step.")]
        case ("fin", "forecast"):
            let a = f.cash + f.avgProfit, b = f.cash + f.avgProfit * 2, d = f.cash + f.avgProfit * 3
            L = ["Cash at the end of each of the next three months: \(money(f, a)), \(money(f, b)), \(money(f, d)).",
                 d < 0 ? "We run short. I would act now." : "We are covered."]
            C = [ch("ok", "Good", "Nothing changes."), ch("cushion", "Plan for a rainy day", "Direction: keep cash.")]
        case ("fin", "margin"):
            let m = f.r3 > 0 ? f.p3 / f.r3 : 0
            L = ["Our margin over three months is \(pct(m)).", f.staff > 0 ? "Each person brings in about \(f.cur.short(f.r3 / 3 / Double(max(1, f.staff)))) a month." : "We have no staff on the books.",
                 m < 0.05 ? "Money leaves almost as fast as it arrives." : "It is a healthy margin."]
            C = [ch("ok", "Understood", "Nothing changes."), ch("trim", "Trim a cost line", "Upkeep is reduced one step.")]
        case ("sales", "pipeline"):
            L = ["We are at \(pct(f.util)) of capacity and \(Int(jsRound(f.awareness)))% known in the area.",
                 f.util > 0.85 ? "We turn people away. There is room for a higher price." : f.util < 0.6 ? "We have free capacity. We need more customers." : "Demand and capacity are in balance."]
            C = [ch("ok", "Thanks", "Nothing changes."), ch("volume", "Chase volume", "Direction: grow."), ch("hold", "Hold the line on price", "Direction: quality first.")]
        case ("sales", "pricing"):
            L = [f.util > 0.85 ? "We are nearly full. A higher price costs few customers." : f.util < 0.6 ? "We have room. A lower price fills it." : "We are balanced. A price move would shift the mix.",
                 "Current price step: \(co.priceLevel > 0 ? "+" : "")\(Int(co.priceLevel))."]
            C = [ch("up", "Raise the price a step", "More per customer, a few leave."), ch("down", "Lower the price a step", "More customers, thinner margin."), ch("hold", "Leave it", "Nothing changes.")]
        case ("hr", "people"):
            L = ["We have \(f.staff) \(f.staff == 1 ? "person" : "people"), \(f.notice) working their notice. Mood is \(moodWord(f.mood)).",
                 f.mood < 45 ? "People are tired. A thank-you would help." : "The team is steady."]
            let treat = f.payroll * 0.05
            C = [ch("ok", "Thanks", "Nothing changes."), ch("treat", "Treat the team", "Costs \(f.cur.short(treat)). Mood up."), ch("tight", "Tighten up", "Mood down; costs stay put.")]
        case ("ops", "capacity"):
            let d = co.value("lastW")["D"].double, cap = co.value("lastW")["cap"].double
            L = ["We use \(pct(f.util)) of capacity.", d > cap && cap > 0 ? "Demand is above what we can serve." : "We can serve what comes."]
            C = [ch("ok", "Thanks", "Nothing changes."), ch("upkeep", "Spend more on upkeep", "Fewer breakdowns, higher costs."), ch("lean", "Run it lean", "Lower costs, more breakdowns.")]
        case ("ops", "upkeep"):
            let e = co.value("eqc")
            L = [e.isNull ? "Equipment is in an unremarkable state." : "Equipment is at \(pct(e.double)).", "Maintenance level: \(co.maintenance) of 2."]
            C = [ch("upkeep", "Spend more on upkeep", "Fewer breakdowns, higher costs."), ch("lean", "Run it lean", "Lower costs, more breakdowns."), ch("ok", "Keep it", "Nothing changes.")]
        case ("mkt", "reach"):
            let spend = co.value("mkt").object.values.reduce(0.0) { $0 + $1["b"].double }
            L = ["\(Int(jsRound(f.awareness)))% of the area knows us. We spend \(f.cur.short(spend)) a week on marketing."]
            C = [ch("ok", "Thanks", "Nothing changes."), ch("push", "Push harder", "Marketing goes up one step."), ch("hold", "Hold it", "Direction: keep costs lean.")]
        default: return nil
        }
        return Scene(companyID: companyID, personID: personID, topic: topic, speaker: first, lines: L, choices: C)
    }

    /// Carry out one choice. Nil when the talk is not possible; an outcome with the reason when it is too soon.
    public static func choose(_ s: inout GameState, companyID: Int, personID: Int, topic: String, choice: String, data: GameData, marketing: MarketingTables) -> Outcome? {
        guard let sc = scene(s, companyID: companyID, personID: personID, topic: topic, data: data), sc.choices.contains(where: { $0.id == choice }),
              let ci = s.companyIndex(companyID), let c = counterparts(s, companyID: companyID).first(where: { $0.id == personID }) else { return nil }
        let w = waitWeeks(s, companyID: companyID, personID: personID, topic: topic)
        if w > 0 { return Outcome(text: "You covered this with \(sc.speaker) recently. Give it \(w) \(w == 1 ? "week" : "weeks").", tone: "n", resigned: false) }
        stamp(&s, companyID, personID, topic)
        let f = facts(s, s.companies[ci], data: data)
        func bump(_ v: Double) { s.companies[ci].set("mood", clamp(ManagerModel.mood(s.companies[ci]) + v, 0, 100)) }
        func quiet(_ key: String) { if s.companies[ci].managerID != nil { ManagerModel.quietAsk(&s, companyID, key, data: data, marketing: marketing) } }
        func setDir(_ d: String) { s.companies[ci].set("dir", d) }
        func upkeep(_ d: Int) { s.companies[ci].maintenance = max(0, min(2, s.companies[ci].maintenance + d)) }
        var text = "Noted.", tone = "n", resigned = false
        switch (c.position, topic, choice) {
        case ("ceo", "results", "thanks"): bump(5); text = "\(sc.speaker) is glad you noticed. Mood is up."; tone = "good"
        case ("ceo", "results", "more"): bump(-5); quiet(f.profit < 0 ? "save" : "mkt_more"); text = "\(sc.speaker) takes it hard but pushes. Mood is down."
        case ("ceo", "results", "fix"): bump(-2); quiet("save"); text = "\(sc.speaker) goes after the costs."
        case ("ceo", "forecast", "grow"): setDir("growth"); text = "Direction set: grow. \(sc.speaker) will lean toward hiring and marketing."
        case ("ceo", "forecast", "cash"), ("fin", "update", "cushion"), ("fin", "forecast", "cushion"): setDir("cash"); text = "Direction set: keep cash. Spending gets a second look."
        case ("ceo", "explain", "trust"): bump(3); text = "\(sc.speaker) feels trusted. Mood is up."; tone = "good"
        case ("ceo", "explain", "why"): bump(-3); quiet("save"); text = "\(sc.speaker) trims running costs, a little stung."
        case ("ceo", "challenge", "listen"): text = "\(sc.speaker) lays out the plan. You hear it out."
        case ("ceo", "challenge", "demand"): bump(-6); quiet("save"); text = "\(sc.speaker) cuts costs. Mood is down."; tone = "bad"
        case ("ceo", "challenge", "final"):
            bump(-12)
            let risk = HashedRandom.first("ownmtg:\(companyID):\(s.week)") < 0.3 && ManagerModel.mood(s.companies[ci]) < 40
            if risk { ManagerModel.resign(&s, companyIndex: ci, why: "after the final warning I do not see a future here"); resigned = true; text = "\(sc.speaker) resigns after the warning." }
            else { text = "\(sc.speaker) takes the warning. Mood is down hard." }
            tone = "bad"
        case ("ceo", "review", "ok"): bump(3); text = "\(sc.speaker) feels trusted. Mood is up."; tone = "good"
        case ("ceo", "review", "ideas"):
            if let n = ManagerModel.meetForProposals(&s, companyID: companyID, data: data) { text = "\(sc.speaker) brought \(n) \(n == 1 ? "idea" : "ideas") to your Inbox, each with its cost and what it should bring."; tone = "good" }
            else { text = "\(sc.speaker) has nothing to put forward now." }
        case ("ceo", "expect", "easy"), ("ceo", "expect", "real"), ("ceo", "expect", "stretch"), ("ceo", "review", "bar"):
            let mode = choice == "easy" ? 0 : choice == "real" ? 1 : 2
            if ManagerTargets.eligible(s.companies[ci], data: data), ManagerTargets.setTargets(&s, ci, month: ManagerTargets.mi(s), mode: mode, data: data) {
                bump(mode == 0 ? 2 : mode == 2 ? -2 : 0)
                text = "Targets set for this month. \(sc.speaker) will be judged on them at month end."; tone = "good"
            } else { text = "There is not enough history to set targets here yet." }
        case ("ceo", "advice", "growth"), ("ceo", "advice", "lean"), ("ceo", "advice", "quality"): setDir(choice); bump(2); text = "\(sc.speaker) will lean toward \(directiveLabel(choice).lowercased()) and decide the small things alone."; tone = "good"
        case ("fin", "update", "trim"), ("fin", "margin", "trim"), ("ops", "capacity", "lean"), ("ops", "upkeep", "lean"): upkeep(-1); setDir("lean"); text = "Upkeep is trimmed one step. Costs go down; breakdowns may go up."
        case ("sales", "pipeline", "volume"): setDir("growth"); text = "Direction set: grow. \(sc.speaker) will chase volume."
        case ("sales", "pipeline", "hold"), ("mkt", "reach", "hold"):
            setDir(c.position == "mkt" ? "lean" : "quality"); text = "Direction set: \(directiveLabel(c.position == "mkt" ? "lean" : "quality").lowercased())."
        case ("sales", "pricing", "up"): PriceMoves.managerStep(&s, ci, up: true, balance: data.balance); text = "Price up one step. A few customers may leave."
        case ("sales", "pricing", "down"): PriceMoves.managerStep(&s, ci, up: false, balance: data.balance); text = "Price down one step. Expect more customers."
        case ("hr", "people", "treat"):
            let cost = f.payroll * 0.05
            if Payments.companyPays(&s, companyID: companyID, amount: cost, category: "oth", label: "Team treat") { bump(8); text = "The team enjoyed it. Mood is up."; tone = "good" }
            else { text = "The company cannot afford that now." }
        case ("hr", "people", "tight"): bump(-4); text = "The team feels the pressure. Mood is down."; tone = "bad"
        case ("ops", "capacity", "upkeep"), ("ops", "upkeep", "upkeep"): upkeep(1); text = "Upkeep goes up one step. Fewer breakdowns, higher costs."
        case ("mkt", "reach", "push"): quiet("mkt_more"); text = "Marketing goes up one step."
        default: text = "Noted."
        }
        return Outcome(text: text, tone: tone, resigned: resigned)
    }

    // MARK: The boardroom round

    public struct RoundLine: Identifiable, Equatable, Sendable {
        public var id: Int
        public var name: String
        public var title: String
        public var text: String
    }
    /// With nobody else owning a share the board only advises; votes bind only with co-owners.
    public static func isAdvisory(_ s: GameState, companyID: Int) -> Bool {
        guard let co = s.company(companyID) else { return true }
        return !ManagerModel.boardActive(s, key: ManagerModel.boardKey(s, co))
    }
    /// Everybody at the table says the one thing that matters from their seat, so a board call gives a quick report from each position.
    public static func boardRound(_ s: GameState, companyID: Int, data: GameData) -> [RoundLine] {
        counterparts(s, companyID: companyID).compactMap { c in
            guard let first = (topicTable[c.position] ?? []).first, let sc = scene(s, companyID: companyID, personID: c.id, topic: first.0, data: data), let line = sc.lines.first else { return nil }
            return RoundLine(id: c.id, name: c.name, title: c.title, text: line)
        }
    }
}
