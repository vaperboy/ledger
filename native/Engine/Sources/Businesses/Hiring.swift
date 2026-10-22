import Foundation
import GameCore
import Countries
import Employees
import Finance

/// Finding and hiring people. Original: `genCand`, `searchWorkers`, `hireWorkerCore` (engine/people/people.js).
///
/// A candidate has a *true* skill and a *claimed* skill: some exaggerate. Checking references or a trial week
/// reveals more. People ask for pay by their skill, age and the local market.
public enum Hiring {
    public enum SearchMode: Sendable { case ads, network, agency }

    static let tiers: [String: (age: (Int, Int), skill: (Double, Double), exp: (Double, Double), ask: Double, lie: Double)] = [
        "young": ((18, 24), (12, 48), (0, 1.5), 0.82, 0.3),
        "mid": ((25, 40), (35, 78), (2, 12), 1.0, 0.22),
        "senior": ((41, 63), (42, 90), (10, 35), 1.2, 0.15),
    ]
    static let personalities = ["driven", "steady", "loyal", "arrogant", "lazy", "restless"]
    static let traits = ["late", "lazy", "conflict", "sick", "theft"]
    static let experienceLines = ["Held a similar role for {y} years.", "Worked in the industry for {y} years.", "{y} years at a competitor.",
                                  "Short stints at several firms, {y} years in total.", "Ran a small operation of their own for {y} years."]

    static func personName(_ c: Country, _ r: inout DeterministicRandom) -> String { r.pick(c.firstNames) + " " + r.pick(c.lastNames) }

    /// Make a new candidate for a role and store them on the labour market. Original: `genCand`.
    @discardableResult
    public static func generateCandidate(role: String, company co: Company?, tier requested: String? = nil, state s: inout GameState, data: GameData) -> Person {
        let w = World(state: s, data: data)
        let tier: String
        if let t = requested { tier = t } else {
            tier = s.random.weightedPick([("young", 3.0), ("mid", 5.0), ("senior", 3.0)], weight: { $0.1 })!.0
        }
        let T = tiers[tier]!
        let lie = !s.random.chance(1 - T.lie)
        let age = s.random.int(T.age.0, T.age.1)
        var skill = jsRound(s.random.range(T.skill.0, T.skill.1))
        let exp = jsRound(s.random.range(T.exp.0, T.exp.1) * 2) / 2
        let superOne = s.random.chance(["sales", "cardealer", "estate"].contains(role) ? 0.04 : 0.015)
        if superOne { skill = Double(s.random.int(88, 100)) }
        // a company with good perks draws better people, with fewer bad habits, who ask a little less (StaffPerks)
        let pull = co.map { StaffPerks.pull($0) } ?? 0
        if pull > 0 && !superOne { skill = min(97, skill + jsRound(pull * s.random.range(2, 7))) }
        let claimSkill = lie ? clamp(skill + Double(s.random.int(8, 28)), 0, 98) : clamp(skill + Double(s.random.int(-4, 4)), 0, 98)
        let claimExp = lie ? exp + Double(s.random.int(2, 8)) : exp
        let base = w.catalog.tables.roles[role]?.baseMonthlyWage ?? 40000
        let country = co.map { w.country($0) } ?? w.countries[s.homeCountryCode]!
        let cityWage = (co.flatMap { w.city($0) }?.wage) ?? 1
        let spread = Wages.paySpread(baseMonthlyWage: base, country: country)
        let perkAsk = 1 - 0.04 * pull
        let ask = roundTo(base * cityWage * T.ask * (0.55 + skill / 110 + (lie ? 0.05 : 0)) * w.inflationIndex * (w.catalog.tables.roles[role] != nil ? spread : 1) * perkAsk * (co.map { Rivals.hiringPressure(s, $0) } ?? 1), step: 100)
        let trait: String? = s.random.chance(0.14 * (1 - 0.4 * pull)) ? s.random.pick(traits) : nil
        let rel = clamp(s.random.range(0.55, 1) - (trait != nil ? 0.12 : 0), 0.3, 1)
        let name = personName(country, &s.random)
        let resume = s.random.pick(experienceLines).replacingOccurrences(of: "{y}", with: String(format: "%g", claimExp)) + (lie && s.random.chance(0.4) ? " References available on request." : "")
        let pers = s.random.pick(personalities)
        let sec = jsRound(s.random.range(0, 1) * 100) / 100
        let golden = tier == "young" && s.random.chance(0.07)
        var p = Person(raw: [:])
        p.id = s.makeID()
        p.name = uniqueName(name, state: s)
        p.age = age
        p.role = role
        p.set("tier", tier); p.skill = skill; p.claimedSkill = claimSkill
        p.set("exp", exp); p.set("claimExp", claimExp); p.set("lie", lie)
        p.askingMonthlyWage = ask
        if let t = trait { p.set("trait", t) }
        p.set("rel", rel); p.set("super", superOne); p.set("resume", resume)
        p.set("checked", 0); p.set("trial", 0); p.employerID = 0
        p.set("pers", pers); p.set("sec", sec); p.set("golden", golden)
        s.people[p.id] = p
        return p
    }

    static func uniqueName(_ name: String, state s: GameState) -> String {
        let used = Set(s.people.values.map { $0.name })
        if !used.contains(name) { return name }
        let parts = name.split(separator: " ").map(String.init)
        for ini in "ABCDEFGHJKLMNOPRSTV" {
            let t = "\(parts[0]) \(ini). \(parts.dropFirst().joined(separator: " "))"
            if !used.contains(t) { return t }
        }
        return name
    }

    /// Advertise, ask around or use an agency. Ads are cheap but bring few; an agency finds more, better ones.
    public static func search(role: String, company co: Company, mode: SearchMode, state s: inout GameState, data: GameData) -> [Person] {
        let n: Int
        switch mode {
        case .agency: n = s.random.int(6, 9)
        case .network: n = s.random.int(3, 5)
        case .ads: n = s.random.int(3, 7)
        }
        var out: [Person] = []
        for _ in 0..<n {
            let tier: String? = mode == .agency ? s.random.weightedPick([("young", 2.0), ("mid", 6.0), ("senior", 4.0)], weight: { $0.1 })!.0 : nil
            out.append(generateCandidate(role: role, company: co, tier: tier, state: &s, data: data))
        }
        return out
    }

    public enum HireResult: Equatable { case ok, taken, refused }

    /// What kind of job is offered: full time (hours 0), part time or seasonal (months 1-12), and the pay basis of a full-timer
    /// (nil = the custom for the job). Original: `HIRE_HOURS`, `HIRE_SEAS`, `HIRE_BASIS` (engine/people/people.js).
    public struct Terms: Equatable, Sendable {
        public var hours: Double = 0
        public var seasonMonths: [Int]? = nil
        public var basis: String? = nil
        /// An estate agent who uses their own car for work, paid by mileage. Original: `ui.carc` ("own").
        public var ownCar = false
        public init(hours: Double = 0, seasonMonths: [Int]? = nil, basis: String? = nil, ownCar: Bool = false) {
            self.hours = hours; self.seasonMonths = seasonMonths; self.basis = basis; self.ownCar = ownCar
        }
        public var isPartTime: Bool { hours > 0 || seasonMonths != nil }
    }

    /// A paid trial week (a quarter of the monthly ask) shows how good someone really is, give or take a few points.
    /// Returns the skill seen, or nil if the person or company is unknown or the company cannot pay. Original: `trialWeek`, `ACT.trial`.
    public static func trialWeek(_ personID: Int, for companyID: Int, state s: inout GameState) -> Double? {
        guard var n = s.people[personID], n.employerID == 0, s.companyIndex(companyID) != nil else { return nil }
        guard Payments.companyPays(&s, companyID: companyID, amount: jsRound(n.askingMonthlyWage / 4), category: "wages", label: "Trial week") else { return nil }
        n.set("trial", 1)
        let seen = jsRound(n.skill + s.random.gauss() * 6)
        n.set("trialRes", seen)
        s.people[personID] = n
        return seen
    }

    /// The candidate a sensible manager would pick: the most skill for the money, among people who can do the job.
    public static func bestValue(_ cands: [Person]) -> Person {
        let able = cands.filter { $0.skill >= 35 }
        let pool = able.isEmpty ? cands : able
        return pool.max { (0.5 + $0.skill / 100) / max(1, $0.askingMonthlyWage) < (0.5 + $1.skill / 100) / max(1, $1.askingMonthlyWage) } ?? cands[0]
    }

    /// Make an offer. The lower it is against what the person asks, the likelier a refusal. Original: `hireWorkerCore`.
    public static func hire(_ personID: Int, into companyID: Int, monthlyWage wage0: Double, state s: inout GameState, data: GameData,
                            terms: Terms = Terms(), fixedSalaryRoles: Set<String> = Hiring.fixedSalaryNorm) -> HireResult {
        guard let ci = s.companyIndex(companyID), var n = s.people[personID] else { return .refused }
        if n.employerID != 0 { return .taken }
        let part = terms.isPartTime
        let basis = part ? "hour" : terms.basis ?? (fixedSalaryRoles.contains(n.role) ? "fix" : "hour")
        var wage = wage0
        let wantsFixed = HashedRandom.first("fix:\(personID)") < (n.age < 26 ? 0.55 : 0.8)
        wage *= basis == "fix" ? (fixedSalaryRoles.contains(n.role) ? 1 : 1.03) : (wantsFixed && !part ? (fixedSalaryRoles.contains(n.role) ? 0.94 : 0.98) : 1)
        let ask = n.askingMonthlyWage
        if wage < ask * 0.82 && !s.random.chance(0.1) { return .refused }
        let p = clamp((wage / ask - 0.86) / 0.18, 0, 1)
        if !s.random.chance(p) && wage < ask { return .refused }
        n.employerID = companyID
        s.people[personID] = n
        var m = StaffMember(raw: [:])
        m.id = personID; m.set("role", n.role); m.monthlyWage = wage0
        m.hiredWeek = s.week; m.payBasis = basis; m.lastRaiseWeek = s.week
        m.set("pm", 0); m.skillGain = 0; m.set("warn", 0); m.set("crs", 0); m.set("onb", .object([:]))
        if part { StaffTalks.applyPartTime(&m, terms: terms, week: s.week) }
        else if terms.ownCar, m.role == "estate" { m.set("ownCar", 1) }
        onboardByManager(&m, company: s.companies[ci], state: &s)
        var staff = s.companies[ci].staff
        staff.append(m)
        s.companies[ci].staff = staff
        return .ok
    }

    /// A manager does the new person's paperwork. Experienced managers (5+ years), or ones who have been fined before, do all of it;
    /// newer ones sometimes forget one or two items. Original: `managerOnboard`.
    static func onboardByManager(_ m: inout StaffMember, company co: Company, state s: inout GameState) {
        guard let mid = co.managerID, let mgr = s.people[mid] else { return }
        let items = StaffExtras.items(role: m.role)
        let experience = mgr.num("exp")
        if co.value("flags")["onbAll"].bool || experience >= 5 { items.forEach { StaffExtras.tick(&m, key: $0.key) }; return }
        var missed = 0
        for it in items {
            if missed < 2 && !s.random.chance(0.78 + experience * 0.03) { missed += 1 } else { StaffExtras.tick(&m, key: it.key) }
        }
    }

    /// Roles where a fixed salary is the custom from the start. Original: `FIX_NORM`.
    public static let fixedSalaryNorm: Set<String> = ["dentist", "dentnurse", "vintner", "physio", "lawyer", "paralegal", "acct", "dev", "designer", "marketer",
                                                      "consult", "foreman", "engineer", "architect", "fishtech", "underw", "claims", "banker", "credit", "analyst", "propm"]

    /// Let someone go. Severance depends on how long they have worked: half a month, one or two months of pay.
    @discardableResult
    public static func fire(_ personID: Int, from companyID: Int, state s: inout GameState, data: GameData, withCause: Bool = false) -> Double {
        guard let ci = s.companyIndex(companyID), let k = s.companies[ci].staff.firstIndex(where: { $0.id == personID }) else { return 0 }
        let m = s.companies[ci].staff[k]
        let months: Double = m.hiredWeek < s.week - 52 ? 2 : m.hiredWeek < s.week - 13 ? 1 : 0.5
        let w = World(state: s, data: data)
        let sev = (withCause || m.noticeWeeks > 0) ? 0 : m.monthlyWage * months * (1 + w.country(s.companies[ci]).employerSocial)
        s.companies[ci].staff.remove(at: k)
        if var p = s.people[personID] { p.employerID = 0; s.people[personID] = p }
        if sev > 0 { Payments.companyPays(&s, companyID: companyID, amount: sev, category: "wages", label: "Severance") }
        return sev
    }
}
