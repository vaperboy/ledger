import Foundation
import GameCore
import Countries
import Employees
import Finance

public enum ManagerVoice {
    public enum Family: String, CaseIterable, Sendable { case general, ops, kitchen, store, sales, fin, site, fleet, clinic }

    public static func family(type: String) -> Family {
        switch type {
        case "ops", "ind", "energy", "tech": return .ops
        case "host": return .kitchen
        case "retail": return .store
        case "sales", "game": return .sales
        case "fin", "fund", "prop": return .fin
        case "site": return .site
        case "fleet": return .fleet
        case "clin": return .clinic
        default: return .general
        }
    }
    public static func family(title: String) -> Family {
        let t = title.lowercased()
        if t.contains("financ") || t.contains("cfo") || t.contains("treasur") { return .fin }
        if t.contains("sales") || t.contains("commercial") { return .sales }
        if t.contains("operat") || t.contains("coo") || t.contains("plant") { return .ops }
        if t.contains("store") || t.contains("retail") || t.contains("shop") { return .store }
        if t.contains("kitchen") || t.contains("chef") || t.contains("restaurant") || t.contains("hospitality") { return .kitchen }
        if t.contains("foreman") || t.contains("site") { return .site }
        if t.contains("fleet") || t.contains("logistic") { return .fleet }
        if t.contains("clinic") { return .clinic }
        return .general
    }

    public enum Situation: String, CaseIterable, Sendable { case hire, equip, cash, cut, ad, raise, poach, resign, digest }

    public struct Traits: Equatable, Sendable {
        public var bold: Bool
        public var detail: Bool
        public var label: String { (bold ? "Bold" : "Cautious") + ", " + (detail ? "detail-minded" : "people-minded") }
    }
    public static func traits(_ n: Person) -> Traits {
        let st = n.value("stats")
        let riskLean = st["risk"].isNull ? 0.5 : 1 - st["risk"].double / 100
        let bold = (HashedRandom.first("tr1:\(n.id)") * 0.7 + riskLean * 0.3) > 0.5
        let detail = (HashedRandom.first("tr2:\(n.id)") * 0.7 + (st["fin"].isNull ? 0.5 : st["fin"].double / 100) * 0.3) > 0.5
        return Traits(bold: bold, detail: detail)
    }
    public static func budgetUse(_ n: Person) -> Double { traits(n).bold ? 1 : 0.75 }

    struct Vocab { var kpi: String; var close: String }
    static let vocab: [Family: Vocab] = [
        .general: Vocab(kpi: "turnover", close: "Your call."),
        .ops: Vocab(kpi: "throughput", close: "I would like a yes by Friday."),
        .kitchen: Vocab(kpi: "covers", close: "Chef's view: do it."),
        .store: Vocab(kpi: "footfall", close: "I can have it on the floor by Monday."),
        .sales: Vocab(kpi: "pipeline", close: "Give me the green light and I will close it."),
        .fin: Vocab(kpi: "cash conversion", close: "I recommend we act before month end."),
        .site: Vocab(kpi: "programme", close: "Every week we wait is a week of slip."),
        .fleet: Vocab(kpi: "vehicle utilisation", close: "Standing vehicles earn nothing."),
        .clinic: Vocab(kpi: "appointment book", close: "Patients first; this helps.")]

    static let lines: [Situation: [Family: [String]]] = [
        .hire: [
            .general: ["We run at {util}% and turn work away. A {role} costs {cost} a year and pays back inside a season. Approve?",
                       "Demand is ahead of us at {util}% load. I want one more {role} ({cost}/yr) before we lose regulars.",
                       "Short of a {role}; at {util}% we are stretching people thin. Recommend hiring."],
            .ops: ["Capacity is {util}% used and the shifts are stacked. A {role} ({cost}/yr) unblocks the bottleneck. Approve?",
                   "Overtime is creeping up at {util}% utilisation. Add a {role} for {cost} a year or throughput stalls.",
                   "I cannot cover every shift with the current crew. One {role}, {cost}/yr, and the rota closes."],
            .kitchen: ["Service is {util}% full and tickets are backing up. I need a {role} ({cost}/yr) on the line.",
                       "We are turning covers away on busy nights. One more {role} and waste drops too: {cost}/yr.",
                       "The pass is jammed at {util}%. Hire a {role}, {cost} a year, before the weekend rush."],
            .store: ["Footfall is fine but the floor is thin at {util}%. A {role} ({cost}/yr) fixes the rota gaps.",
                     "Queues at peak and nobody to cover breaks. One {role}, {cost} a year.",
                     "Rota is full at {util}% and people are doubling up. Request: a {role}, {cost}/yr."],
            .sales: ["Pipeline is moving but I cannot work every lead at {util}% load. A {role} ({cost}/yr) lifts conversion.",
                     "Leads are going cold while we stay at {util}%. One {role}, {cost} a year, pays for itself in new accounts.",
                     "Targets are reachable with another {role}: {cost}/yr. I will own the ramp-up."],
            .fin: ["Headcount case: a {role} at {cost}/yr is covered by the extra margin at {util}% load. Approve.",
                   "Utilisation {util}%. Marginal hire of a {role} ({cost}/yr) clears payback within the year.",
                   "I ran the numbers: one {role} for {cost} a year is accretive. Recommend approval."],
            .site: ["The gang is stretched at {util}% and we are losing days. A {role} ({cost}/yr) keeps the programme.",
                    "Short of a {role} on site; slip is building. {cost} a year to catch up.",
                    "I need one more {role} or the next phase starts late. {cost}/yr."],
            .fleet: ["Jobs are queuing at {util}% and drivers are on max hours. One {role}, {cost}/yr, keeps vehicles moving.",
                     "Dispatch is turning loads down. Hire a {role}: {cost} a year.",
                     "Hours rules cap my drivers at {util}% load. A {role} ({cost}/yr) gets the vehicles full."],
            .clinic: ["The appointment book is {util}% full and waits are growing. A {role} ({cost}/yr) shortens them.",
                      "Patients wait too long at {util}% load. I recommend one more {role}, {cost} a year.",
                      "Cover is thin for the clinic list. One {role}, {cost}/yr, and the book clears."]],
        .equip: [
            .general: ["We are turning customers away because of {role}. {cost} fixes it; I think it pays back within the year.",
                       "The limit is {role}. Spend of {cost} lifts what we can serve. Approve?",
                       "Sales are capped by {role}. {cost} to remove the cap."],
            .ops: ["{role} is the bottleneck at {util}% utilisation. {cost} lifts capacity; downtime drops too.",
                   "The line is constrained by {role}. Investment {cost}: I expect throughput up and rework down.",
                   "We keep queuing at {role}. {cost} clears it. Recommend yes."],
            .kitchen: ["The kitchen is held up by {role}. {cost} and service speeds up, covers go up.",
                       "I am losing tickets at {role}. {cost} and we stop turning guests away.",
                       "Service times suffer without better {role}. It is {cost}; worth it."],
            .store: ["The floor is limited by {role}. {cost} and customers stop walking out.",
                     "We lose sales at {role}. {cost} fixes the limit.",
                     "Shoppers queue at {role}. {cost}; I would do it before the next sale."],
            .sales: ["I could sell more if {role} were not capping us. {cost} unlocks it.",
                     "Orders are waiting on {role}. {cost}: the extra revenue covers it.",
                     "Capacity ({role}) is now the limit on the pipeline. {cost}."],
            .fin: ["Capex request: {role}, {cost}. Return is inside the year on current volume; cash holds after it.",
                   "Recommend {cost} for {role}: payback under twelve months, within our cash cover.",
                   "{role} caps revenue. {cost} spend is justified by the marginal margin."],
            .site: ["We are stuck without proper {role}. {cost} and we stop losing days.",
                    "Kit shortfall: {role}. {cost}; hiring in costs more than owning.",
                    "{role} is holding the programme. {cost}, bought once, saves every job."],
            .fleet: ["More {role} puts loads on the road that I turn down today. {cost}.",
                     "Vehicle capacity is the limit: {role}, {cost}. Utilisation justifies it.",
                     "Jobs are waiting for {role}. {cost} and they move."],
            .clinic: ["The clinic is limited by {role}. {cost} cuts waiting times.",
                      "Treatment slots are capped by {role}. {cost} reopens them.",
                      "Patients are waiting on {role}. {cost}; I would prioritise it."]],
        .cash: [
            .general: ["Cash is down to about {cash} weeks of costs. I recommend putting money in or borrowing now.",
                       "We have {cash} weeks of runway. Please top up before we miss a payment.",
                       "Only {cash} weeks of cash left. Inject or I start delaying purchases."],
            .ops: ["Cash covers {cash} weeks of running costs. I am holding non-essential orders until you top up.",
                   "Runway is {cash} weeks. Maintenance and parts come first; the rest waits unless you inject.",
                   "Only {cash} weeks of costs in the account. Please fund it before suppliers tighten terms."],
            .kitchen: ["The till covers {cash} weeks of suppliers and wages. Please top up before the next delivery.",
                       "{cash} weeks of cash: the produce bill alone is a worry. Put money in.",
                       "We are {cash} weeks from trouble with the suppliers. Inject, or I cut the menu."],
            .store: ["Takings cover {cash} weeks of rent and wages. Top up before the next stock order.",
                     "{cash} weeks of cash. I will hold the reorder unless you fund the till.",
                     "Stock orders are at risk: {cash} weeks of cash left. Please fund it."],
            .sales: ["Cash in hand is {cash} weeks of costs. I will chase customer payments, but you should top up.",
                     "Receivables are slow and cash is {cash} weeks. Inject while I collect.",
                     "Only {cash} weeks of cash: I will push early-payment deals, but please add funds."],
            .fin: ["Liquidity alert: {cash} weeks of cover, below my floor of eight. Recommend an injection or a facility draw.",
                   "Cash cover is {cash} weeks. Covenant headroom is thin; fund it before month end.",
                   "Runway {cash} weeks. Options: owner injection, loan, or defer capex. I prefer the injection."],
            .site: ["Cash covers {cash} weeks; subcontractors are paid on the 30th. Please top up.",
                    "{cash} weeks of cash on a live site. Fund it or I slow the pours.",
                    "Materials and wages need cover: {cash} weeks left."],
            .fleet: ["Fuel and driver pay need cash: {cash} weeks left. Please fund it.",
                     "{cash} weeks of runway. Maintenance on the vehicles comes before anything else.",
                     "Only {cash} weeks of cash for the fleet. Inject before fuel cards bounce."],
            .clinic: ["The clinic has {cash} weeks of cash for wages and consumables. Please fund it.",
                      "Runway is {cash} weeks. I will not compromise on supplies; top up, please.",
                      "{cash} weeks of cash left: payroll comes first. Inject or I defer purchases."]],
        .cut: [
            .general: ["We use under half our capacity ({util}%). I suggest letting one person go; severance applies.",
                       "Load is only {util}%. Payroll is ahead of the work; I recommend a reduction of one.",
                       "At {util}% we carry more people than we need. Reduce by one?"],
            .ops: ["Utilisation is {util}%. I can run the lines with one less; saves payroll.",
                   "Shifts are half empty ({util}%). Consolidate and release one head.",
                   "Idle time at {util}%. Cut one position and rebalance."],
            .kitchen: ["Covers are down and the kitchen is overstaffed at {util}%. One fewer on the rota.",
                       "Quiet service, {util}% load. I would drop one prep shift.",
                       "Labour cost is high against covers at {util}%. Release one."],
            .store: ["Footfall does not justify the rota ({util}%). I suggest cutting one position.",
                     "The floor is overstaffed at {util}%. One less on the rota.",
                     "Quiet weeks and {util}% load. Reduce hours by one head."],
            .sales: ["Not enough pipeline for the team at {util}%. I would release one rep until it fills.",
                     "Capacity exceeds demand ({util}%). One position goes unless pipeline grows.",
                     "We carry one more seller than the leads support. Reduce."],
            .fin: ["Labour is {util}% productive. Cutting one head saves the annual cost with no revenue loss.",
                   "Payroll to revenue is out of band at {util}% load. Recommend one redundancy.",
                   "Utilisation {util}%. Margin improves by trimming one role."],
            .site: ["Not enough work on the books for this gang ({util}%). Stand one down.",
                    "Idle crew at {util}%. I will release one until the next job starts.",
                    "The gang is bigger than the order book. Reduce by one."],
            .fleet: ["Vehicles stand at {util}% load. Fewer drivers needed: release one.",
                     "Under-used crew at {util}%. I suggest letting one driver go.",
                     "Dispatch is light. One fewer on the roster."],
            .clinic: ["The book is under half full ({util}%). One post can go.",
                      "Clinic load is {util}%. Recommend reducing staffing by one.",
                      "Fewer appointments than we staff for. Reduce by one."]],
        .ad: [
            .general: ["Awareness is low; people do not know we exist. A campaign of {cost} would start filling the books.",
                       "Few customers know about us. I would start ads at {cost}.",
                       "We are invisible locally. {cost} on advertising to begin."],
            .ops: ["We have capacity but no demand. Ads at {cost} fill the idle hours.",
                   "Utilisation lags because nobody knows us. {cost} on a campaign.",
                   "Spare capacity, low awareness. Recommend {cost} in ads."],
            .kitchen: ["The dining room has empty tables. A local campaign at {cost} would fill them.",
                       "Nobody knows we are here. {cost} on ads to put covers on the book.",
                       "Quiet service, low awareness. Approve {cost} for promotion."],
            .store: ["Footfall is thin because awareness is low. {cost} on ads to bring people in.",
                     "Few people know the shop. A campaign at {cost}.",
                     "Walk-ins are low. I would put {cost} behind local ads."],
            .sales: ["Pipeline is thin: awareness is the problem. A campaign at {cost} feeds the funnel.",
                     "No inbound leads. {cost} on marketing to start the conversation.",
                     "I need leads. {cost} on ads and I will work them."],
            .fin: ["Revenue is limited by awareness. Marketing spend of {cost} is affordable from cash on hand.",
                   "Recommend {cost} on advertising: cost of acquisition looks acceptable.",
                   "Awareness is low and we have cash cover. Spend {cost} to build the base."],
            .site: ["The order book is thin. Marketing of {cost} to get tenders in.",
                    "Nobody calls for quotes. {cost} on advertising.",
                    "To keep the gang busy we need more enquiries: {cost}."],
            .fleet: ["Vehicles are under-booked. {cost} on advertising for more jobs.",
                     "Low awareness with shippers. A campaign at {cost}.",
                     "I need more loads. {cost} on ads."],
            .clinic: ["Not enough patients know about us. {cost} on local advertising.",
                      "The book has gaps. A campaign of {cost} would fill them.",
                      "Awareness is low for the clinic. Recommend {cost} in ads."]]]

    static let shared: [Situation: [String]] = [
        .raise: ["A year in, and {kpi} is up on my watch. I would like +{up}/month ({pct}). I think it is fair.",
                 "I have run this for a year and kept {kpi} where it should be. Asking for +{up}/month ({pct}).",
                 "Review time. Given how {kpi} has gone, I am asking for +{up}/month. Rivals pay more.",
                 "After twelve months I would like my pay to reflect the results: +{up}/month ({pct})."],
        .poach: ["A rival has offered me about {up}/month more. I would rather stay: can you match it?",
                 "I have an offer on the table, {up} a month above what I earn. Say the word and I stay.",
                 "A competitor is after me. To keep {kpi} on track I would need +{up}/month.",
                 "I came to you before answering a rival. Match +{up}/month and the conversation is over."],
        .resign: ["I am handing in my notice. {why}",
                  "This is my notice. {why}",
                  "I have decided to leave. {why}",
                  "It is time for me to move on. {why}"]]

    public static func pick(_ s: inout GameState, companyIndex ci: Int, situation: String, seed: Int, variants v: [String]) -> String {
        guard !v.isEmpty else { return "" }
        var fl = s.companies[ci].value("flags")
        var vo = fl["voice"]
        let last = vo[situation].array.map { $0.int }
        var i = Int(HashedRandom.first("voice:\(seed):\(situation):\(s.week)") * Double(v.count)) % v.count
        var guardN = 0
        while last.contains(i) && guardN < v.count { i = (i + 1) % v.count; guardN += 1 }
        vo[situation] = .array(([i] + last).prefix(2).map { .number(Double($0)) })
        fl["voice"] = vo
        s.companies[ci].set("flags", fl)
        return v[i]
    }

    static func fill(_ t: String, _ vars: [String: String]) -> String {
        var r = t
        for (k, x) in vars { r = r.replacingOccurrences(of: "{\(k)}", with: x) }
        return r
    }

    public static func variants(_ sit: Situation, family f: Family) -> [String] {
        if let l = lines[sit]?[f] { return l }
        return shared[sit] ?? []
    }

    static func familyOf(_ n: Person, _ bd: Trade?) -> Family {
        family(type: n.str("mtype").isEmpty ? (bd?.managerType ?? "gen") : n.str("mtype"))
    }

    public static func say(_ s: inout GameState, companyIndex ci: Int, manager n: Person, bd: Trade?, situation sit: Situation, vars: [String: String] = [:]) -> String {
        let fam = familyOf(n, bd)
        var all = vars
        all["kpi"] = (vocab[fam] ?? vocab[.general]!).kpi
        let text = pick(&s, companyIndex: ci, situation: sit.rawValue, seed: n.id, variants: variants(sit, family: fam))
        return fill(text, all)
    }

    public static func stance(_ n: Person) -> String {
        let t = traits(n)
        switch (t.bold, t.detail) {
        case (true, true): return "I have the numbers; I would go ahead."
        case (true, false): return "The team is ready for it; I would go ahead."
        case (false, true): return "I checked it twice; the case holds, but there is risk."
        case (false, false): return "I would rather we did it carefully, with the team on board."
        }
    }

    public static func record(_ s: inout GameState, companyIndex ci: Int, _ text: String) {
        var log = s.companies[ci].value("mgrLog").array
        log.append(.object(["w": .number(Double(s.week)), "t": .string(text)]))
        s.companies[ci].set("mgrLog", .array(Array(log.suffix(12))))
    }

    static func digestWeek(_ s: inout GameState, companyIndex ci: Int, manager n: Person, bd: Trade, utilisation util: Double) {
        let co = s.companies[ci]
        let budget = ManagerModel.budget(of: co)
        let weekly = budget == .free
        guard budget.actsAlone, weekly || s.week % 2 == 0 else { return }
        let span = Double(weekly ? 1 : 2)
        let fresh = co.value("mgrLog").array.filter { $0["w"].double > Double(s.week) - span - 1 }
        guard !fresh.isEmpty else { return }
        let fam = familyOf(n, bd)
        let v = vocab[fam] ?? vocab[.general]!
        let dir = util > 0.85 ? "strong" : util < 0.55 ? "soft" : "steady"
        let opener = pick(&s, companyIndex: ci, situation: "digest", seed: n.id, variants: [
            "This \(weekly ? "week" : "fortnight"), on my own authority:", "Done since the last report (\(v.kpi) \(dir)):",
            "What I did, within the limits you set:", "Handled \(weekly ? "this week" : "this fortnight"):"])
        var body = opener + "\n" + fresh.prefix(5).map { "• " + $0["t"].string }.joined(separator: "\n")
        body += "\n" + (util > 0.95 ? "Next: \(v.kpi) is at the limit; expect a capacity request." : util < 0.5 ? "Next: \(v.kpi) is soft; I will look at pricing and promotion." : stance(n))
        s.addMessage(kind: "info", from: n.name, title: "\(co.name): what I did", body: body, companyID: co.id, tone: "n", status: "done")
        s.companies[ci].set("mgrLog", .array([]))
    }

    public struct Scorecard: Sendable {
        public var rows: [(label: String, word: String)]
        public var traits: String
        public var verdict: String
    }
    static func word(_ x: Double) -> String { x < 30 ? "weak" : x < 45 ? "shaky" : x < 60 ? "steady" : x < 75 ? "solid" : x < 88 ? "strong" : "outstanding" }

    public static func scorecard(_ s: GameState, companyID: Int, data: GameData) -> Scorecard? {
        guard let co = s.company(companyID), let mid = co.managerID, let n = s.people[mid] else { return nil }
        let st = n.value("stats")
        var rows: [(label: String, word: String)] = ManagerModel.skillKeys.map { ($0.label, word(st[$0.key].double)) }
        let going = ManagerModel.managerGoingRate(company: co, state: s, data: data)
        let ratio = going > 0 ? co.managerMonthlyWage / going : 1
        rows.append(("Pay against the market", ratio < 0.85 ? "underpaid" : ratio < 1.1 ? "fair" : "generous"))
        let mood = co.value("mood").isNull ? 60 : co.num("mood")
        rows.append(("Morale", mood < 30 ? "ready to leave" : mood < 50 ? "restless" : mood < 75 ? "content" : "keen"))
        let q = co.value("mgrQ").isNull ? 0.5 : co.num("mgrQ")
        rows.append(("Results", word(q * 100)))
        let v = vocab[familyOf(n, data.catalog[co.type])] ?? vocab[.general]!
        let k = v.kpi.prefix(1).uppercased() + v.kpi.dropFirst()
        let verdict: String
        if mood < 35 || ratio < 0.8 { verdict = "I keep \(v.kpi) on track, but I do not feel I am paid for it. Talk to me before a rival does." }
        else if q > 0.7 { verdict = "\(k) is where it should be. Leave it with me." }
        else if q > 0.45 { verdict = "\(k) is acceptable, not great. I am working on it." }
        else { verdict = "\(k) is below where it should be. I need support or time." }
        return Scorecard(rows: rows, traits: traits(n).label, verdict: verdict)
    }
}
