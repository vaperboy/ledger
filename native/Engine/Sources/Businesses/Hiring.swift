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

    /// What the job normally pays on this labour market: the role, the city, the economy and the country's pay spread, and nothing about the person.
    /// This is where a pay discussion starts, from the employer's side. Experience and skill only decide whether someone takes it, wants more or would take less.
    public static func marketWage(role: String, company co: Company?, state s: GameState, data: GameData) -> Double {
        let w = World(state: s, data: data)
        let base = w.catalog.tables.roles[role]?.baseMonthlyWage ?? 40000
        let country = co.map { w.country($0) } ?? w.countries[s.homeCountryCode]!
        let cityWage = (co.flatMap { w.city($0 ) }?.wage) ?? 1
        let spread = w.catalog.tables.roles[role] != nil ? Wages.paySpread(baseMonthlyWage: base, country: country) : 1
        return roundTo(base * cityWage * w.inflationIndex * spread, step: 100)
    }

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
        let pull = co.map { StaffPerks.pull($0, role: role) } ?? 0
        if pull > 0 && !superOne { skill = min(97, skill + jsRound(pull * s.random.range(2, 7))) }
        let claimSkill = lie ? clamp(skill + Double(s.random.int(8, 28)), 0, 98) : clamp(skill + Double(s.random.int(-4, 4)), 0, 98)
        let claimExp = lie ? exp + Double(s.random.int(2, 8)) : exp
        let base = w.catalog.tables.roles[role]?.baseMonthlyWage ?? 40000
        let country = co.map { w.country($0) } ?? w.countries[s.homeCountryCode]!
        let cityWage = (co.flatMap { w.city($0) }?.wage) ?? 1
        let spread = Wages.paySpread(baseMonthlyWage: base, country: country)
        let perkAsk = 1 - 0.04 * pull
        let ask = roundTo(base * cityWage * T.ask * skillCurve(skill, lie: lie) * w.inflationIndex * (w.catalog.tables.roles[role] != nil ? spread : 1) * perkAsk * (co.map { Rivals.hiringPressure(s, $0) } ?? 1), step: 100)
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
        // people also differ in what they want apart from skill: some take the going rate gladly, some hold out for more
        p.askingMonthlyWage = roundTo(ask * (0.92 + 0.16 * HashedRandom.first("ask:\(p.id)")), step: 100)
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

    /// `ok`: hired. `taken`: has another job. `refused`: the offer was an insult, no figure named. `countered`: they name their own figure
    /// (a hire at that wage is accepted; it may be an unrealistic one, which is for the player to judge). `walkedAway`: patience gone, the person
    /// took another job and is no longer on the market.
    public enum HireResult: Equatable { case ok, taken, refused, countered(Negotiation.Counter), walkedAway
        /// They would take the job on the pay figure but will not work on the pay plan offered (commission only, for someone who wants security); they stay on the market.
        case planRefused }

    /// What kind of job is offered: full time (hours 0), part time or seasonal (months 1-12), and the pay basis of a full-timer
    /// (nil = the custom for the job). Original: `HIRE_HOURS`, `HIRE_SEAS`, `HIRE_BASIS` (engine/people/people.js).
    public struct Terms: Equatable, Sendable {
        public var hours: Double = 0
        public var seasonMonths: [Int]? = nil
        public var basis: String? = nil
        /// An estate agent who uses their own car for work, paid by mileage. Original: `ui.carc` ("own").
        public var ownCar = false
        /// The pay plan of a full-time seller: "mix" (the wage offered is the base salary, commission on top), "com" (commission only: no base at all; the
        /// figure offered is the pay they expect to earn), or nil / "fix" for a plain salary. Only for jobs the data lets sell on commission.
        public var payPlan: String? = nil
        /// The commission share of the plan; 0 = the plan's usual one.
        public var commissionRate = 0.0
        /// A fixed-term contract of this many weeks (one of `FixedTerm.termChoices`); 0 = permanent.
        public var fixedTermWeeks = 0
        public init(hours: Double = 0, seasonMonths: [Int]? = nil, basis: String? = nil, ownCar: Bool = false, payPlan: String? = nil, commissionRate: Double = 0, fixedTermWeeks: Int = 0) {
            self.hours = hours; self.seasonMonths = seasonMonths; self.basis = basis; self.ownCar = ownCar; self.payPlan = payPlan; self.commissionRate = commissionRate
            self.fixedTermWeeks = fixedTermWeeks
        }
        public var isPartTime: Bool { hours > 0 || seasonMonths != nil }
    }

    /// A paid trial week (a quarter of the market wage for the role) shows how good someone really is, give or take a few points.
    /// Returns the skill seen, or nil if the person or company is unknown or the company cannot pay. Original: `trialWeek`, `ACT.trial`.
    public static func trialWeek(_ personID: Int, for companyID: Int, state s: inout GameState, data: GameData) -> Double? {
        guard var n = s.people[personID], n.employerID == 0, s.companyIndex(companyID) != nil else { return nil }
        let trialCost = jsRound(marketWage(role: n.role, company: s.companies[s.companyIndex(companyID)!], state: s, data: data) / 4)
        guard Payments.companyPays(&s, companyID: companyID, amount: trialCost, category: "wages", label: "Trial week") else { return nil }
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
        return pool.max { valueScore(skill: $0.skill, price: $0.askingMonthlyWage) < valueScore(skill: $1.skill, price: $1.askingMonthlyWage) } ?? cands[0]
    }

    /// How much skill a wage buys: the one measure of "skill for the money" (a baseline of 0.5 so that a weak person is worth something).
    static func valueScore(skill: Double, price: Double) -> Double { (0.5 + skill / 100) / max(1, price) }

    /// The pay basis a hire gets and what the person makes of an offer on it: a fixed salary where hours are the custom, or hours for
    /// someone who would rather have a salary, is worth a little more or less to them than the same figure on the other basis.
    static func payBasis(_ n: Person, terms: Terms, fixedSalaryRoles: Set<String>) -> (basis: String, factor: Double) {
        let part = terms.isPartTime
        let basis = part ? "hour" : terms.basis ?? (fixedSalaryRoles.contains(n.role) ? "fix" : "hour")
        let wantsFixed = HashedRandom.first("fix:\(n.id)") < (n.age < 26 ? 0.55 : 0.8)
        let factor = basis == "fix" ? (fixedSalaryRoles.contains(n.role) ? 1 : 1.03) : (wantsFixed && !part ? (fixedSalaryRoles.contains(n.role) ? 0.94 : 0.98) : 1)
        return (basis, factor)
    }

    /// How asking pay rises with skill (a candidate who exaggerates asks a little extra). Candidates are made with it, and whoever weighs
    /// them (`AutoHire`) uses the same curve to judge what someone of a given skill is worth.
    static func skillCurve(_ skill: Double, lie: Bool = false) -> Double { 0.55 + skill / 110 + (lie ? 0.05 : 0) }
    /// What someone of this age group and skill would ask, as a multiple of the going rate for the job.
    static func askCurve(tier: String, skill: Double) -> Double { tiers[tier]!.ask * skillCurve(skill) }

    /// The age group of a person (the groups do not overlap).
    static func tier(forAge age: Int) -> String { age <= tiers["young"]!.age.1 ? "young" : age <= tiers["mid"]!.age.1 ? "mid" : "senior" }

    /// The employer id of someone who took a job somewhere else while the talk went on: no longer on the market.
    public static let goneElsewhere = -9

    // MARK: The candidate's side of a pay talk (every kind of hire uses it)

    /// What a person would say in a pay talk, from their hidden ask: they open at it and settle for a little less, by temperament. `factor`
    /// is how an offer converts into what they value (pay basis, a profit share): the figures are returned in offer units.
    public static func position(for n: Person, factor f: Double = 1) -> Negotiation.Position {
        let f = f > 0 ? f : 1
        return Negotiation.position(opening: n.askingMonthlyWage / f, direction: .higher, temperament: temperament(of: n), key: "\(n.id)")
    }

    public static func temperament(of n: Person) -> Negotiation.Temperament {
        Negotiation.temperament(personality: n.str("pers").isEmpty ? nil : n.str("pers"), key: "\(n.id)")
    }

    /// The person answers an offer made by `employer` for a post of `rank` (see `Negotiation`). Keeps the talk on the person's record, ends it on
    /// an accept, and on a walk away takes the person off the market and says so. The caller does the rest of the hire after an accept and must
    /// read the person again after this call.
    public static func answer(personID: Int, employer: Int, rank: String, offer: Double, factor: Double = 1, currency: Currency, about: Double,
                              state s: inout GameState) -> Negotiation.Response {
        guard var n = s.people[personID] else { return Negotiation.Response(.refuse) }
        var talk = Negotiation.State.resume(n, party: employer, week: s.week)
        let r = Negotiation.respond(offer: offer, position: position(for: n, factor: factor), temperament: temperament(of: n), rank: rank, state: &talk,
                                    week: s.week, step: currency.stepSize(about: about), random: &s.random)
        switch r.answer {
        case .accept: Negotiation.State().store(in: &n)
        case .walkAway:
            Negotiation.State().store(in: &n)
            n.employerID = goneElsewhere
            s.note("\(n.name) lost patience and took another job.", tone: "n", companyID: max(0, employer))
        case .counter, .refuse: talk.store(in: &n)
        }
        s.people[personID] = n
        return r
    }

    /// The same question with nothing changed on the person: what would they answer to this offer? Used by someone who weighs several people
    /// before choosing one (`AutoHire`); the talk is kept in `talk`. It uses the game's random numbers like the real thing.
    public static func probe(_ n: Person, offer: Double, factor: Double = 1, rank: String, talk: inout Negotiation.State, currency: Currency, about: Double,
                             state s: inout GameState) -> Negotiation.Response {
        Negotiation.respond(offer: offer, position: position(for: n, factor: factor), temperament: temperament(of: n), rank: rank, state: &talk,
                            week: s.week, step: currency.stepSize(about: about), random: &s.random)
    }

    /// Make an offer. At or above what the person would settle for (hidden from the player) they accept; below it they counter, refuse an insult,
    /// or, when their patience for this kind of post is gone, walk away. Original: `hireWorkerCore` (the answer is the shared `Negotiation`).
    public static func hire(_ personID: Int, into companyID: Int, monthlyWage offered: Double, state s: inout GameState, data: GameData,
                            terms: Terms = Terms(), fixedSalaryRoles: Set<String> = Hiring.fixedSalaryNorm) -> HireResult {
        guard let ci = s.companyIndex(companyID), let n0 = s.people[personID] else { return .refused }
        if n0.employerID != 0 { return .taken }
        // No offer goes below the minimum pay of the company's country; a lower one is raised to it (pay is per full-time week).
        let world = World(state: s, data: data)
        let wage0 = max(offered, world.minimumWage(s.companies[ci]))
        if wage0 > offered { s.note("The offer to \(n0.name) was raised to the minimum wage of \(world.country(s.companies[ci]).name).", companyID: companyID) }
        let part = terms.isPartTime
        let (basis, factor) = payBasis(n0, terms: terms, fixedSalaryRoles: fixedSalaryRoles)
        let reply = answer(personID: personID, employer: companyID, rank: "worker", offer: wage0, factor: factor,
                           currency: world.currency(s.companies[ci]), about: 100, state: &s)
        switch reply.answer {
        case .refuse: return .refused
        case .walkAway: return .walkedAway
        case .counter(let c): return .countered(c)
        case .accept: break
        }
        guard var n = s.people[personID] else { return .refused }
        // A pay plan on commission: allowed for a job the data lets sell in this trade; someone who wants security may not take commission only.
        let plan: String? = (!part && (terms.payPlan == "mix" || terms.payPlan == "com") && PayPlans.eligible(role: n.role, trade: s.companies[ci].type, salesRoles: data.catalog.tables.salesRoles)) ? terms.payPlan : nil
        if plan == "com", n.num("sec") > 0.65, s.random.chance(0.6) { return .planRefused }
        // Someone who needs security does not take a fixed-term job (see FixedTerm.wantsPermanent).
        let term = FixedTerm.termChoices.contains(terms.fixedTermWeeks) ? terms.fixedTermWeeks : 0
        if term > 0, FixedTerm.wantsPermanent(n) { return .planRefused }
        // A first fixed term longer than the country's maximum is not offered (optional labour data; none by default).
        if term > 0, FixedTerm.renewalBlock(World(state: s, data: data).labour(s.companies[ci]), StaffMember(raw: [:]), weeks: term, now: s.week) != nil { return .planRefused }
        n.employerID = companyID
        s.people[personID] = n
        var m = StaffMember(raw: [:])
        m.id = personID; m.set("role", n.role); m.monthlyWage = wage0
        m.hiredWeek = s.week; m.payBasis = basis; m.lastRaiseWeek = s.week
        m.set("pm", 0); m.skillGain = 0; m.set("warn", 0); m.set("crs", 0); m.set("onb", .object([:]))
        if part { StaffTalks.applyPartTime(&m, terms: terms, week: s.week) }
        else if terms.ownCar { m.set("ownCar", 1) }
        if m.flag("ownCar"), let bd = data.catalog[s.companies[ci].type], !PersonalEquipment.canUseOwnCar(role: m.role, bd, tables: data.catalog.tables) { m.set("ownCar", 0) }
        if let plan {
            let rate = terms.commissionRate > 0 ? terms.commissionRate : (PayPlans.mode(plan)?.defaultRate ?? 0)
            m.set("pay", .object(["m": .string(plan), "rate": .number(rate)])); m.set("commEma", 0)
            if plan == "com" { m.monthlyWage = 0 }   // commission only has no base
            if PayPlans.isExtra(role: m.role, trade: s.companies[ci].type, salesRoles: data.catalog.tables.salesRoles) { m.set("ppx", 1) }
        }
        if term > 0 { m.set("ft", s.week + term); m.set("ftl", term) }
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
}
