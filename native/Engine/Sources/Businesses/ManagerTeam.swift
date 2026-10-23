import Foundation
import GameCore
import Countries
import Employees
import Finance

/// The management team above the manager: a managing director (CEO) per company, department heads, regional managers, and for a chain
/// the chain manager and CEO, and for the whole group a managing director. Who decides what climbs this ladder (`decisionChain`).
/// Originals: features/people/management_team.js (TEAM56, MR56), features/company/org_chart.js (ORG56), engine/management/managers.js
/// (`chainOf`, `decider`, `genExec`, `groupWagesMonth`), features/company/chain_hierarchy.js (CHN56).
/// Saved on the company as `team` {ceo, heads{sales,ops,fin,hr,mkt}} (each {npc, wage, lvl, buy, w0}); regional and chain managers in
/// `rest["group"]["regional"]`, the group's managing director in `rest["org56"]["md"]`, a chain's CEO in the chain's `ceo56`.
extension ManagerModel {
    // MARK: Roles

    public struct TeamRole: Equatable, Sendable {
        public var key: String
        public var title: String
        public var stat: String
        public var payFactor: Double
        public var text: String
        public var fromPeople: Double
    }

    /// Department heads. Original: `ROLES` in management_team.js.
    public static let teamRoles: [TeamRole] = [
        TeamRole(key: "sales", title: "Sales director", stat: "sales", payFactor: 1.85, text: "More customers: about 2% more demand, up to 5% in business-to-business trades.", fromPeople: 10),
        TeamRole(key: "ops", title: "Operations manager", stat: "ops", payFactor: 1.8, text: "Runs the place better: about 5% more capacity.", fromPeople: 15),
        TeamRole(key: "fin", title: "Finance manager", stat: "fin", payFactor: 2.1, text: "Cheaper money and books: a lower loan margin, lower accountant fees and fines.", fromPeople: 20),
        TeamRole(key: "hr", title: "HR manager", stat: "people", payFactor: 2, text: "People stay longer (about 7% fewer leave), better mood, long weeks wear less.", fromPeople: 25),
        TeamRole(key: "mkt", title: "Marketing manager", stat: "sales", payFactor: 1.85, text: "Campaigns reach about 8% more people.", fromPeople: 10),
    ]
    static let bigTrades: Set<String> = ["bank", "insco", "fund", "airline", "shipping", "oilgas", "hotel", "factory", "casino"]
    static let teamStatNames: [String: String] = ["ops": "Running things", "people": "People", "sales": "Sales", "fin": "Money", "risk": "Risk sense"]

    // MARK: Small helpers

    static func playerCurrency(_ s: GameState, _ data: GameData) -> Currency {
        let w = World(state: s, data: data)
        return Currency(country: w.countries[s.homeCountryCode]!, rates: w.rates)
    }
    static func firstName(_ n: String) -> String { n.split(separator: " ").first.map(String.init) ?? n }
    /// Average of the five leadership numbers, 0 to 1. Original: `qOf`.
    public static func leadership(_ n: Person?) -> Double {
        guard let n = n, !n.value("stats").isNull else { return 0.5 }
        let st = n.value("stats")
        return (st["ops"].double + st["people"].double + st["sales"].double + st["fin"].double + st["risk"].double) / 500
    }
    static func person(_ s: GameState, _ rec: JSONValue) -> Person? { rec.isNull ? nil : s.people[rec["npc"].int] }
    static func skill01(_ n: Person?, _ stat: String) -> Double {
        guard let n = n, !n.value("stats").isNull else { return 0 }
        let v = n.value("stats")[stat]
        return clamp((v.isNull ? 55 : v.double) / 100, 0.15, 1)
    }
    static func updateGroup(_ s: inout GameState, _ f: (inout JSONValue) -> Void) {
        var g = s.rest["group"] ?? .object(["ceo": .null, "regional": .array([]), "big": 0])
        f(&g)
        s.rest["group"] = g
    }
    public static func regionals(_ s: GameState) -> [JSONValue] { (s.rest["group"]?["regional"].array ?? []).filter { s.people[$0["npc"].int] != nil } }
    static func headCount(_ co: Company) -> Int { co.staff.count + (co.managerID != nil ? 1 : 0) }
    static func underHolding(_ s: GameState, _ co: Company) -> [Company] {
        co.type == "hold" ? s.companies.filter { $0.holdingID == co.id && $0.status.isLive } : []
    }
    static func branchesOf(_ s: GameState, _ co: Company) -> [Company] {
        s.companies.filter { $0.status.isLive && $0.value("branch")["of"].int == co.id && !$0.value("branch").isNull }
    }
    static func team(_ co: Company) -> JSONValue { co.value("team").isNull ? .object(["ceo": .null, "heads": .object([:])]) : co.value("team") }

    /// Titles by country and level. Original: `titleFor`.
    public static func titleFor(_ co: Company?, kind: String, data: GameData, state s: GameState) -> String {
        let code = co?.countryCode ?? s.homeCountryCode
        switch kind {
        case "chainmgr": return "Chain manager"
        case "ceo56": return "CEO"
        case "md": return "Managing director"
        case "region": return "Regional manager"
        case "mdir": return CountryTraits.text(code, "mdirTitle") ?? "Managing director"
        case "ceo": return "CEO"
        case "mgr": return co.flatMap { data.catalog[$0.type] }.map { title($0) } ?? "General manager"
        default: return kind
        }
    }

    // MARK: What the team does

    static func headsOK(_ co: Company, _ r: TeamRole) -> Bool {
        co.type != "hold" && Double(headCount(co)) >= r.fromPeople * (bigTrades.contains(co.type) ? 0.5 : 1)
    }
    static func mdOK(_ s: GameState, _ co: Company) -> Bool {
        co.type == "hold" ? underHolding(s, co).count >= 2 : headCount(co) >= 20 || (bigTrades.contains(co.type) && headCount(co) >= 8)
    }
    static func headSkill(_ s: GameState, _ co: Company, _ key: String) -> Double {
        guard let r = teamRoles.first(where: { $0.key == key }) else { return 0 }
        let rec = team(co)["heads"][key]
        guard let n = person(s, rec) else { return 0 }
        return skill01(n, r.stat)
    }
    /// The managing director of the company, or of the holding above it.
    static func companyMD(_ s: GameState, _ co: Company) -> Person? {
        if let n = person(s, team(co)["ceo"]) { return n }
        if co.holdingID != 0, let h = s.company(co.holdingID), let n = person(s, team(h)["ceo"]) { return n }
        return nil
    }

    /// Pay of a team member for a week (with employer's tax). Chain and group levels are paid in `groupMonthly`.
    static func teamWeek(_ s: inout GameState, _ ci: Int, _ bd: Trade, data: GameData) {
        let co = s.companies[ci]
        guard co.status == .open else { return }
        let t = team(co)
        var monthly = 0.0
        if person(s, t["ceo"]) != nil { monthly += t["ceo"]["wage"].double }
        for (k, rec) in t["heads"].object where person(s, rec) != nil && teamRoles.contains(where: { $0.key == k }) { monthly += rec["wage"].double }
        for r in regionals(s) where r["payCo"].int == co.id && r["payCo"].string != "chain" { monthly += r["wage"].double }
        if monthly > 0 {
            let social = World(state: s, data: data).country(co).employerSocial
            Payments.companyPays(&s, companyID: co.id, amount: monthly * 12 / 52 * (1 + social), category: "wages")
        }
        // what they do, cached for demand, capacity, marketing and quits (read in Demand, Capacity, Marketing, StaffRoutine)
        var tm: [String: JSONValue] = [:]
        for r in teamRoles { let v = headSkill(s, co, r.key); if v > 0 { tm[r.key] = .number(v) } }
        s.companies[ci].set("tm", .object(tm))
        // a managing director coaches the manager
        let md = companyMD(s, co)
        s.companies[ci].set("mdCoach", md.map { 0.06 * skill01($0, "people") } ?? 0)
        let hr = headSkill(s, co, "hr")
        if hr > 0 {
            if co.managerID != nil { s.companies[ci].set("mood", clamp(mood(co) + (72 - mood(co)) * 0.03 * hr, 0, 100)) }
            var staff = s.companies[ci].staff
            for k in staff.indices where staff[k].tiredness > 0 { staff[k].tiredness = max(0, staff[k].tiredness - 2 * hr) }
            s.companies[ci].staff = staff
        }
        if md != nil && co.managerID != nil { s.companies[ci].set("mood", clamp(mood(s.companies[ci]) + 0.15 * skill01(md, "people"), 0, 100)) }
        // bosses above lift (or drag) every manager under them; a boss also halves how fast a left-alone manager slips
        var lift = 1.0
        let boss = decisionChain(s, s.companies[ci], data: data).filter { $0.kind != "mgr" }
        if let rg = s.companies[ci].value("region").isNull ? nil : regionals(s).first(where: { $0["id"].int == s.companies[ci].value("region").int }) {
            lift *= 1 + 0.1 * (leadership(person(s, rg)) - 0.5)
        }
        if let gm = person(s, s.rest["group"]?["ceo"] ?? .null) { lift *= 1 + 0.06 * (leadership(gm) - 0.5) }
        s.companies[ci].set("mgrLift", lift)
        s.companies[ci].set("drift56", attentionDrift(s.companies[ci], week: s.week))
        s.companies[ci].set("boss56", !boss.isEmpty)
    }

    // MARK: Who decides

    public struct Boss: Equatable, Sendable {
        public var kind: String        // mgr, region, chainmgr, ceo56, mdir, md
        public var personID: Int
        public var level: Int
        public var buy: Double
        public var regionalID: Int?
        public var name: String
    }

    /// Who stands above a company's manager, lowest first. Original: `chainOf`.
    public static func decisionChain(_ s: GameState, _ co: Company, data: GameData) -> [Boss] {
        var out: [Boss] = []
        func add(_ kind: String, _ rec: JSONValue, rg: Int? = nil) {
            guard let n = person(s, rec) else { return }
            out.append(Boss(kind: kind, personID: n.id, level: Int(rec["lvl"].double), buy: rec["buy"].double, regionalID: rg, name: n.name))
        }
        if let mid = co.managerID, let n = s.people[mid] {
            out.append(Boss(kind: "mgr", personID: n.id, level: Int(co.value("auth")["lvl"].double), buy: co.value("auth")["buy"].double, regionalID: nil, name: n.name))
        }
        let regs = s.rest["group"]?["regional"].array ?? []
        if let ch = Chains.chain(s, of: co) {
            let id = ch["id"].int
            if let area = regs.first(where: { $0["scope"].string == "chain:\(id):\(co.cityID)" }) { add("region", area, rg: area["id"].int) }
            if let cm = regs.first(where: { $0["scope"].string == "chain:\(id)" }) { add("chainmgr", cm, rg: cm["id"].int) }
            add("ceo56", ch["ceo56"])
        } else {
            let t = team(co)
            if person(s, t["ceo"]) != nil { add("mdir", t["ceo"]) }
            else if co.holdingID != 0, let h = s.company(co.holdingID), person(s, team(h)["ceo"]) != nil { add("mdir", team(h)["ceo"]) }
            if !co.value("region").isNull, let rg = regs.first(where: { $0["id"].int == co.value("region").int }) { add("region", rg, rg: rg["id"].int) }
        }
        let gm = s.rest["org56"]?["md"] ?? .null
        if person(s, gm) != nil { add("md", gm) } else { add("md", s.rest["group"]?["ceo"] ?? .null) }
        return out
    }

    // MARK: Slots (what the screens show)

    public struct TeamSlot: Identifiable, Equatable, Sendable {
        public var id: String
        public var key: String
        public var title: String
        public var detail: String
        public var personID: Int?
        public var monthlyWage: Double
        public var level: Int
        public var buy: Double
        public var since: Int
        public var regionalID: Int?
    }

    /// The roles a company has room for, each with the person in it or empty. Original: `T56.slots`.
    public static func teamSlots(_ s: GameState, companyID: Int, data: GameData) -> [TeamSlot] {
        guard let co = s.company(companyID), co.status != .setup, data.catalog[co.type]?.family != "club" else { return [] }
        let t = team(co)
        var out: [TeamSlot] = []
        func slot(_ key: String, rec: JSONValue, rg: Int? = nil) -> TeamSlot {
            let n = person(s, rec)
            return TeamSlot(id: rg.map { "reg:\($0)" } ?? key, key: key, title: slotTitle(s, co, key, data: data), detail: slotText(s, co, key), personID: n?.id,
                            monthlyWage: n == nil ? 0 : rec["wage"].double, level: Int(rec["lvl"].double), buy: rec["buy"].double, since: rec["w0"].int, regionalID: rg)
        }
        let md = t["ceo"]
        if person(s, md) != nil || mdOK(s, co) { out.append(slot("ceo", rec: md)) }
        for r in teamRoles {
            let rec = t["heads"][r.key]
            if person(s, rec) != nil || headsOK(co, r) { out.append(slot(r.key, rec: rec)) }
        }
        let mine = regionals(s).filter { $0["payCo"].int == co.id && $0["payCo"].string != "chain" }
        for r in mine { out.append(slot("reg", rec: r, rg: r["id"].int)) }
        if !branchesOf(s, co).isEmpty && mine.isEmpty { out.append(slot("reg", rec: .null)) }
        return out
    }

    static func slotTitle(_ s: GameState, _ co: Company, _ key: String, data: GameData) -> String {
        switch key {
        case "ceo": return titleFor(co, kind: "mdir", data: data, state: s)
        case "reg": return titleFor(co, kind: "region", data: data, state: s)
        default: return teamRoles.first { $0.key == key }?.title ?? key
        }
    }
    static func slotText(_ s: GameState, _ co: Company, _ key: String) -> String {
        switch key {
        case "ceo": return (co.type == "hold" ? "Runs the \(underHolding(s, co).count) companies under the holding" : "Runs the company above the manager") + ", with the authority you give, and coaches the manager."
        case "reg": return "Runs \(co.name) and its \(branchesOf(s, co).count) branches in one city or country."
        default: return teamRoles.first { $0.key == key }?.text ?? ""
        }
    }

    // MARK: Hiring through the agency

    /// Pay an executive search and get three candidates for a team role. `key`: ceo, reg, sales, ops, fin, hr, mkt. Original: `MR56[k].gen`.
    public static func searchTeam(_ s: inout GameState, companyID: Int, key: String, data: GameData) -> [Person]? {
        guard let ci = s.companyIndex(companyID), key == "ceo" || key == "reg" || teamRoles.contains(where: { $0.key == key }) else { return nil }
        let cur = World(state: s, data: data).currency(s.companies[ci])
        let fee = cur.scaledPrice(15000)
        guard s.companies[ci].cash >= fee || Payments.liquid(s) >= fee else { return nil }
        Payments.companyPays(&s, companyID: companyID, amount: fee, category: "oth", label: "Executive search: \(slotTitle(s, s.companies[ci], key, data: data))")
        let f = key == "ceo" ? 2.4 : key == "reg" ? 1.6 : teamRoles.first { $0.key == key }!.payFactor
        return (0..<3).map { _ in
            var n = generateCandidate(company: s.companies[ci], type: "gen", state: &s, data: data)
            n.askingMonthlyWage = cur.roundedStep(n.askingMonthlyWage * f, about: 500)
            s.people[n.id] = n
            return n
        }
    }

    /// Hire into a team role. Below what they ask, the closer the offer the likelier they say yes. Original: `hireTeam`.
    public static func hireTeam(_ s: inout GameState, companyID: Int, key: String, personID: Int, monthlyWage w: Double, data: GameData) -> OfferResult {
        guard let ci = s.companyIndex(companyID), var n = s.people[personID] else { return .refused }
        if n.employerID != 0 { return .taken }
        let ask = max(1, n.askingMonthlyWage)
        if w < ask && !s.random.chance(clamp((w / ask - 0.88) / 0.14, 0, 1)) { return .refused }
        let co = s.companies[ci]
        var t = team(co)
        let hq = w
        n.employerID = -6
        n.set("stats", n.value("stats"))
        s.people[personID] = n
        if key == "ceo" {
            let buy = World(state: s, data: data).currency(co).roundedStep(max(co.value("lastW")["rev"].double * 4, Playing.scaled(s, data, co, 50000)), about: 1000)
            t["ceo"] = .object(["npc": .number(Double(personID)), "wage": .number(hq), "w0": .number(Double(s.week)), "lvl": 1, "buy": .number(buy)])
        } else if key == "reg" {
            let id = s.makeID()
            let buy = Playing.scaled(s, data, co, 50000)
            let rg: JSONValue = .object(["id": .number(Double(id)), "npc": .number(Double(personID)), "scope": .string("co:\(co.id)"), "wage": .number(hq), "lvl": 1,
                                         "buy": .number(buy), "payCo": .number(Double(co.id)), "w0": .number(Double(s.week))])
            updateGroup(&s) { g in var l = g["regional"].array; l.append(rg); g["regional"] = .array(l) }
            for c in [co] + branchesOf(s, co) { if let k = s.companyIndex(c.id) { s.companies[k].set("region", id) } }
        } else {
            var h = t["heads"]
            h[key] = .object(["npc": .number(Double(personID)), "wage": .number(hq), "w0": .number(Double(s.week))])
            t["heads"] = h
        }
        s.companies[ci].set("team", t)
        s.note("\(n.name) starts as \(slotTitle(s, co, key, data: data).lowercased()) at \(co.name).", tone: "good", companyID: co.id)
        return .ok
    }

    /// Let a team member go: one month of pay. Original: `ACT.tm56fire`.
    @discardableResult
    public static func releaseTeam(_ s: inout GameState, companyID: Int, key: String, regionalID: Int? = nil, data: GameData) -> Bool {
        guard let ci = s.companyIndex(companyID) else { return false }
        let co = s.companies[ci]
        var t = team(co)
        var rec: JSONValue = .null
        if key == "ceo" { rec = t["ceo"] } else if key == "reg" { rec = regionals(s).first { $0["id"].int == regionalID } ?? .null } else { rec = t["heads"][key] }
        guard let n = person(s, rec) else { return false }
        let social = World(state: s, data: data).country(co).employerSocial
        Dismissal.book(&s, payer: .company(companyID), severance: Dismissal.monthOfPay(wage: rec["wage"].double, employerSocial: social), labels: .post(slotTitle(s, co, key, data: data)))
        var p = n; p.employerID = 0; s.people[n.id] = p
        if key == "ceo" { t["ceo"] = .null }
        else if key == "reg" {
            let rid = rec["id"].int
            updateGroup(&s) { g in g["regional"] = .array(g["regional"].array.filter { $0["id"].int != rid }) }
            for k in s.companies.indices where s.companies[k].value("region").int == rid && !s.companies[k].value("region").isNull { s.companies[k].set("region", .null) }
        } else { var h = t["heads"]; h[key] = .null; t["heads"] = h }
        if let k = s.companyIndex(companyID) { s.companies[k].set("team", t) }
        return true
    }

    /// What the managing director may decide: level 0 to 2, and how much they may spend at level 1. Original: `ACT.tm56auth`.
    public static func setTeamAuthority(_ s: inout GameState, companyID: Int, level: Int? = nil, buy: Double? = nil) {
        guard let ci = s.companyIndex(companyID) else { return }
        var t = team(s.companies[ci])
        guard !t["ceo"].isNull else { return }
        if let l = level { t["ceo"]["lvl"] = .number(Double(min(2, max(0, l)))) }
        if let b = buy { t["ceo"]["buy"] = .number(b) }
        s.companies[ci].set("team", t)
    }

    // MARK: Chain and group levels

    public enum ExecLevel: String, Sendable, CaseIterable { case md, ceo56, chainmgr, region
        public var title: String { self == .md ? "Managing director" : self == .ceo56 ? "CEO" : self == .chainmgr ? "Chain manager" : "Regional manager" }
        var pay: Double { self == .md ? 130000 : self == .ceo56 ? 95000 : self == .chainmgr ? 70000 : 58000 }
        var buy: Double { self == .md ? 2_000_000 : self == .ceo56 ? 600_000 : self == .chainmgr ? 250_000 : 80_000 }
        public var text: String {
            switch self {
            case .md: return "Runs the whole group under you and approves what the chains cannot. Paid by all your companies."
            case .ceo56: return "Sets the chain's strategy and takes it into new cities. Paid by the chain's stores."
            case .chainmgr: return "Keeps every store on the chain's rules, coaches the store managers, opens new stores where they are full. Paid by the chain's stores."
            case .region: return "Runs the chain's stores in one city and expands the ones that are too small. Paid by the chain's stores."
            }
        }
    }

    /// Search for a chain or group executive; the agency is paid by the player (group) or the first store. Original: `MR56` in org_chart.js, `genExec`.
    public static func searchExecutive(_ s: inout GameState, level: ExecLevel, data: GameData) -> [Person]? {
        let cur = playerCurrency(s, data)
        let fee = cur.scaledPrice(15000)
        guard Payments.liquid(s) >= fee else { return nil }
        Payments.playerPays(&s, fee, label: "Executive search: \(level.title)")
        return (0..<3).map { _ in
            var n = generateCandidate(company: nil, type: "gen", state: &s, data: data)
            var st = n.value("stats")
            st["ops"] = .number(clamp(st["ops"].double + 8, 5, 99)); st["fin"] = .number(clamp(st["fin"].double + 6, 5, 99))
            n.set("stats", st); n.set("exec", level.rawValue)
            n.askingMonthlyWage = cur.roundedStep(cur.scaledPrice(level.pay) * s.random.range(0.85, 1.15), about: 1000)
            s.people[n.id] = n
            return n
        }
    }

    /// Hire a chain or group executive. `chainID` for chain levels; `city` for a regional manager. Original: `MR56[r].hire`.
    public static func hireExecutive(_ s: inout GameState, level: ExecLevel, personID: Int, monthlyWage w: Double, chainID: Int?, city: String?, data: GameData) -> OfferResult {
        guard var n = s.people[personID] else { return .refused }
        if n.employerID != 0 { return .taken }
        let ask = max(1, n.askingMonthlyWage)
        if w < ask && !s.random.chance(clamp((w / ask - 0.88) / 0.14, 0, 1)) { return .refused }
        let cur = playerCurrency(s, data)
        let rec: JSONValue = .object(["npc": .number(Double(personID)), "wage": .number(w), "lvl": 1, "buy": .number(cur.scaledPrice(level.buy)), "w0": .number(Double(s.week))])
        switch level {
        case .md:
            n.employerID = -2
            s.rest["org56"] = (s.rest["org56"] ?? .object([:])).with("md", rec)
        case .ceo56:
            guard let chainID = chainID, var ch = Chains.chain(s, id: chainID) else { return .refused }
            n.employerID = -2
            ch["ceo56"] = rec
            Chains.save(&s, ch)
            addSeat(&s, boardKey: "ch:\(chainID)", seat: ["id": .number(Double(personID)), "kind": "exec", "t": "CEO"])
        case .chainmgr, .region:
            guard let chainID = chainID, Chains.chain(s, id: chainID) != nil else { return .refused }
            n.employerID = -1
            let id = s.makeID()
            let scope = "chain:\(chainID)" + (level == .region ? ":\(city ?? "")" : "")
            let rg: JSONValue = .object(["id": .number(Double(id)), "npc": .number(Double(personID)), "scope": .string(scope), "wage": .number(w), "lvl": 1,
                                         "buy": .number(cur.scaledPrice(level.buy)), "payCo": "chain", "w0": .number(Double(s.week))])
            updateGroup(&s) { g in var l = g["regional"].array; l.append(rg); g["regional"] = .array(l) }
            assignRegions(&s, chainID: chainID)
            addSeat(&s, boardKey: "ch:\(chainID)", seat: ["id": .number(Double(personID)), "kind": "exec", "t": .string(level.title)])
            n.set("k11", .object(["post": .string(scope), "t": .string(level.title), "wage": .number(w), "bonus": 0, "duties": .array(["quality", "coach"]), "auth": 1, "rep": "month", "w0": .number(Double(s.week))]))
        }
        s.people[personID] = n
        s.note("\(n.name) starts as \(level.title.lowercased()).", tone: "good")
        return .ok
    }

    /// Each store reports to its city's regional manager, else the chain manager. Original: `chiefFor`.
    static func assignRegions(_ s: inout GameState, chainID: Int) {
        guard let ch = Chains.chain(s, id: chainID) else { return }
        let regs = regionals(s)
        for c in Chains.stores(s, ch) {
            let r = regs.first { $0["scope"].string == "chain:\(chainID):\(c.cityID)" } ?? regs.first { $0["scope"].string == "chain:\(chainID)" }
            if let k = s.companyIndex(c.id) { s.companies[k].set("region", r?["id"] ?? .null) }
        }
    }

    /// Let the group managing director, a chain's CEO, or a chain/regional manager go. Original: `fireExec`.
    @discardableResult
    public static func releaseExecutive(_ s: inout GameState, level: ExecLevel, chainID: Int? = nil, regionalID: Int? = nil, data: GameData) -> Bool {
        var rec: JSONValue = .null
        switch level {
        case .md: rec = s.rest["org56"]?["md"] ?? .null
        case .ceo56: rec = chainID.flatMap { Chains.chain(s, id: $0) }?["ceo56"] ?? .null
        default: rec = regionals(s).first { $0["id"].int == regionalID } ?? .null
        }
        guard let n = person(s, rec) else { return false }
        Dismissal.book(&s, payer: .player, severance: Dismissal.monthOfPay(wage: rec["wage"].double, employerSocial: 0.14), labels: .post(level.title))
        var p = n; p.employerID = 0; s.people[n.id] = p
        switch level {
        case .md: s.rest["org56"] = (s.rest["org56"] ?? .object([:])).with("md", .null)
        case .ceo56: if let id = chainID, var ch = Chains.chain(s, id: id) { ch["ceo56"] = .null; Chains.save(&s, ch) }
        default:
            let rid = regionalID ?? 0
            let scope = rec["scope"].string
            updateGroup(&s) { g in g["regional"] = .array(g["regional"].array.filter { $0["id"].int != rid }) }
            if let id = chainID ?? Int(scope.split(separator: ":").dropFirst().first ?? "") { assignRegions(&s, chainID: id) }
            for k in s.companies.indices where s.companies[k].value("region").int == rid && !s.companies[k].value("region").isNull { s.companies[k].set("region", .null) }
        }
        removeSeat(&s, personID: n.id)
        return true
    }

    /// Authority of a chain or group executive (also the older group CEO). `kind` is md, ceo56, region, chainmgr or gceo.
    public static func setExecutiveAuthority(_ s: inout GameState, level: ExecLevel, chainID: Int? = nil, regionalID: Int? = nil, authority: Int? = nil, buy: Double? = nil) {
        func patch(_ r: inout JSONValue) {
            if let a = authority { r["lvl"] = .number(Double(min(2, max(0, a)))) }
            if let b = buy { r["buy"] = .number(b) }
        }
        switch level {
        case .md: var m = s.rest["org56"]?["md"] ?? .null; guard !m.isNull else { return }; patch(&m); s.rest["org56"] = (s.rest["org56"] ?? .object([:])).with("md", m)
        case .ceo56:
            guard let id = chainID, var ch = Chains.chain(s, id: id), !ch["ceo56"].isNull else { return }
            var c = ch["ceo56"]; patch(&c); ch["ceo56"] = c; Chains.save(&s, ch)
        default:
            updateGroup(&s) { g in
                var l = g["regional"].array
                if let k = l.firstIndex(where: { $0["id"].int == regionalID }) { patch(&l[k]); g["regional"] = .array(l) }
            }
        }
    }

    /// The older group CEO of saves from before round 56. Original: `ACT.fireceo`.
    public static func releaseGroupCEO(_ s: inout GameState) {
        guard let n = person(s, s.rest["group"]?["ceo"] ?? .null) else { return }
        var p = n; p.employerID = 0; s.people[n.id] = p
        updateGroup(&s) { $0["ceo"] = .null }
    }

    /// How much the group may decide before it comes to you. Original: `ACT.setbig`.
    public static func setGroupLimit(_ s: inout GameState, amount: Double) { updateGroup(&s) { $0["big"] = .number(amount) } }

    // MARK: Monthly: group salaries, chain management shared by stores

    /// Original: `groupWagesMonth` and the 'organisation is paid by the companies it runs' step.
    static func groupMonthly(_ s: inout GameState, data: GameData) {
        var g = 0.0
        for r in regionals(s) where r["payCo"].isNull && r["payCo"].int == 0 { g += r["wage"].double }
        if let c = s.rest["group"]?["ceo"], person(s, c) != nil { g += c["wage"].double }
        if g > 0 { Headquarters.payHeadOffice(&s, g * 1.14, label: "Group management salaries") }
        // chain management and the managing director are shared by the stores by revenue
        let md = s.rest["org56"]?["md"] ?? .null
        var share: [(Int, Double)] = []
        for ch in Chains.list(s) {
            let L = Chains.stores(s, ch).filter { $0.status == .open }
            if L.isEmpty { continue }
            var w = 0.0
            for r in regionals(s) where r["scope"].string.hasPrefix("chain:\(ch["id"].int)") { w += r["wage"].double }
            if person(s, ch["ceo56"]) != nil { w += ch["ceo56"]["wage"].double }
            if w > 0 { for c in L { share.append((c.id, w * 1.14 * rev(c) / max(1, L.reduce(0) { $0 + rev($1) }))) } }
        }
        if person(s, md) != nil {
            let L = s.companies.filter { $0.status == .open && $0.type != "hold" }
            let tot = max(1, L.reduce(0) { $0 + rev($1) })
            for c in L { share.append((c.id, md["wage"].double * 1.14 * rev(c) / tot)) }
        }
        for (id, amt) in share where amt > 0 { Payments.companyPays(&s, companyID: id, amount: amt, category: "wages", label: "Chain and group management") }
    }
    static func rev(_ c: Company) -> Double { max(1, c.value("lastW")["rev"].double) }
}

/// A scaled amount for a company's country.
enum Playing {
    static func scaled(_ s: GameState, _ data: GameData, _ co: Company, _ v: Double) -> Double { World(state: s, data: data).currency(co).scaledPrice(v) }
}

extension JSONValue {
    /// A copy with one key set.
    func with(_ key: String, _ v: JSONValue) -> JSONValue { var c = self; c[key] = v; return c }
}
