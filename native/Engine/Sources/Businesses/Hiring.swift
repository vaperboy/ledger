import Foundation
import GameCore
import Countries
import Employees
import Finance

public enum Hiring {
    public enum SearchMode: Sendable { case ads, network, agency }

    static let tiers: [String: (age: (Int, Int), skill: (Double, Double), exp: (Double, Double), lie: Double)] = [
        "young": ((18, 24), (12, 48), (0, 1.5), 0.3),
        "mid": ((25, 40), (35, 78), (2, 12), 0.22),
        "senior": ((41, 63), (42, 90), (10, 35), 0.15),
    ]
    static let personalities = ["driven", "steady", "loyal", "arrogant", "lazy", "restless"]
    static let traits = ["late", "lazy", "conflict", "sick", "theft"]
    static let experienceLines = ["Held a similar role for {y} years.", "Worked in the industry for {y} years.", "{y} years at a competitor.",
                                  "Short stints at several firms, {y} years in total.", "Ran a small operation of their own for {y} years."]

    static func personName(_ c: Country, _ r: inout DeterministicRandom) -> String { r.pick(c.firstNames) + " " + r.pick(c.lastNames) }

    public static func marketWage(role: String, company co: Company?, state s: GameState, data: GameData) -> Double {
        let w = World(state: s, data: data)
        let base = w.catalog.tables.roles[role]?.baseMonthlyWage ?? 40000
        let country = co.map { w.country($0) } ?? w.countries[s.homeCountryCode]!
        let cityWage = (co.flatMap { w.city($0 ) }?.wage) ?? 1
        let spread = w.catalog.tables.roles[role] != nil ? Wages.paySpread(baseMonthlyWage: base, country: country) : 1
        return roundTo(base * cityWage * w.inflationIndex * spread, step: 100)
    }

    @discardableResult
    public static func generateCandidate(role: String, company co: Company?, tier requested: String? = nil, faces: Bool = true, state s: inout GameState, data: GameData) -> Person {
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
        let pull = co.map { StaffPerks.pull($0, role: role) } ?? 0
        if pull > 0 && !superOne { skill = min(97, skill + jsRound(pull * s.random.range(2, 7))) }
        let claimSkill = lie ? clamp(skill + Double(s.random.int(8, 28)), 0, 98) : clamp(skill + Double(s.random.int(-4, 4)), 0, 98)
        let claimExp = lie ? exp + Double(s.random.int(2, 8)) : exp
        let base = w.catalog.tables.roles[role]?.baseMonthlyWage ?? 40000
        let country = co.map { w.country($0) } ?? w.countries[s.homeCountryCode]!
        let cityWage = (co.flatMap { w.city($0) }?.wage) ?? 1
        let spread = Wages.paySpread(baseMonthlyWage: base, country: country)
        let perkAsk = 1 - 0.04 * pull
        let ask = roundTo(base * cityWage * askSpread(skill: skill, experience: exp, lie: lie) * w.inflationIndex * (w.catalog.tables.roles[role] != nil ? spread : 1) * perkAsk * (co.map { Rivals.hiringPressure(s, $0) } ?? 1), step: 100)
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
        p.askingMonthlyWage = roundTo(ask * (0.92 + 0.16 * HashedRandom.first("ask:\(p.id)")), step: 100)
        if let t = trait { p.set("trait", t) }
        p.set("rel", rel); p.set("super", superOne); p.set("resume", resume)
        p.set("checked", 0); p.set("trial", 0); p.employerID = 0
        p.set("pers", pers); p.set("sec", sec); p.set("golden", golden)
        s.people[p.id] = p
        if faces { FaceBook.assign(personID: p.id, countryCode: country.code, style: FaceBook.style(for: p, trade: co.flatMap { data.catalog[$0.type] }), state: &s) }
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

    public static func searchFee(_ mode: SearchMode) -> Double { 0 }

    public static func applicantsFound(_ mode: SearchMode) -> ClosedRange<Int> {
        switch mode {
        case .agency: return 6...9
        case .network: return 3...5
        case .ads: return 3...7
        }
    }

    public static func search(role: String, company co: Company, mode: SearchMode, faces: Bool = true, state s: inout GameState, data: GameData) -> [Person] {
        let range = applicantsFound(mode)
        let n = s.random.int(range.lowerBound, range.upperBound)
        var out: [Person] = []
        for _ in 0..<n {
            let tier: String? = mode == .agency ? s.random.weightedPick([("young", 2.0), ("mid", 6.0), ("senior", 4.0)], weight: { $0.1 })!.0 : nil
            out.append(generateCandidate(role: role, company: co, tier: tier, faces: faces, state: &s, data: data))
        }
        return out
    }

    public enum HireResult: Equatable { case ok, taken, refused, countered(Negotiation.Counter), walkedAway
        case planRefused }

    public struct Terms: Equatable, Sendable {
        public var hours: Double = 0
        public var seasonMonths: [Int]? = nil
        public var basis: String? = nil
        public var ownCar = false
        public var payPlan: String? = nil
        public var commissionRate = 0.0
        public var fixedTermWeeks = 0
        public var percent = 0.0
        public var seasonCount = 0
        public var bonusPlan: String? = nil
        public var expenseItems: [String] = []
        public var promises: [StaffPromises.Draft] = []
        public var expectations: [String] = []
        public init(hours: Double = 0, seasonMonths: [Int]? = nil, basis: String? = nil, ownCar: Bool = false, payPlan: String? = nil, commissionRate: Double = 0, fixedTermWeeks: Int = 0,
                    percent: Double = 0, seasonCount: Int = 0, bonusPlan: String? = nil, expenseItems: [String] = [], promises: [StaffPromises.Draft] = [], expectations: [String] = []) {
            self.hours = hours; self.seasonMonths = seasonMonths; self.basis = basis; self.ownCar = ownCar; self.payPlan = payPlan; self.commissionRate = commissionRate
            self.fixedTermWeeks = fixedTermWeeks
            self.percent = percent; self.seasonCount = seasonCount; self.bonusPlan = bonusPlan; self.expenseItems = expenseItems; self.promises = promises; self.expectations = expectations
        }
        public var effectiveHours: Double {
            if percent > 0 { return percent >= 100 ? 0 : percent / 100 * StaffModel.fullWeekHours }
            return hours
        }
        public var isPartTime: Bool { effectiveHours > 0 || seasonMonths != nil }
    }

    static func previewRecord(person n: Person, offered: Double, terms: Terms, company co: Company, week: Int, data: GameData) -> StaffMember {
        var m = StaffMember(raw: [:])
        m.id = n.id; m.set("role", n.role)
        m.monthlyWage = offered
        m.payBasis = payBasis(n, terms: terms, fixedSalaryRoles: fixedSalaryNorm).basis
        if terms.isPartTime { StaffTalks.applyPartTime(&m, terms: terms, week: week) } else if terms.ownCar { m.set("ownCar", 1) }
        if terms.payPlan == "com", PayPlans.eligible(role: n.role, trade: co.type, salesRoles: data.catalog.tables.salesRoles) { m.monthlyWage = 0 }
        if let plan = terms.bonusPlan, let l = WorkerBonus.level(plan), !l.isNone { m.set("bp", l.id) }
        for x in terms.expenseItems where StaffExpenses.item(x) != nil { var ex = m.value("ex"); if ex.isNull { ex = .object([:]) }; ex[x] = 1; m.set("ex", ex) }
        if let k = terms.fixedTermWeeks as Int?, k > 0 { m.set("ft", week + k) }
        return m
    }

    public static func trialWeek(_ personID: Int, for companyID: Int, state s: inout GameState, data: GameData) -> [WorkLog.Observation]? {
        guard var n = s.people[personID], n.employerID == 0, s.companyIndex(companyID) != nil else { return nil }
        guard (n.raw["trial"]?.double ?? 0) == 0 else { return nil }
        let trialCost = jsRound(marketWage(role: n.role, company: s.companies[s.companyIndex(companyID)!], state: s, data: data) / 4)
        guard Payments.companyPays(&s, companyID: companyID, amount: trialCost, category: "wages", label: "Trial week") else { return nil }
        n.set("trial", 1)
        let seen = WorkLog.trialObservations(person: n, role: n.role, week: s.week &+ Int(s.random.next() * 500))
        n.set("trialObs", .array(seen.map { .string($0.text) }))
        s.people[personID] = n
        return seen
    }

    public static func bestValue(_ cands: [Person]) -> Person {
        let able = cands.filter { $0.skill >= 35 }
        let pool = able.isEmpty ? cands : able
        return pool.max { valueScore(skill: $0.skill, price: $0.askingMonthlyWage) < valueScore(skill: $1.skill, price: $1.askingMonthlyWage) } ?? cands[0]
    }

    static func valueScore(skill: Double, price: Double) -> Double { (0.5 + skill / 100) / max(1, price) }

    static func payBasis(_ n: Person, terms: Terms, fixedSalaryRoles: Set<String>) -> (basis: String, factor: Double) {
        let part = terms.isPartTime
        let basis = part ? (terms.basis == "fix" ? "fix" : "hour") : terms.basis ?? (fixedSalaryRoles.contains(n.role) ? "fix" : "hour")
        let wantsFixed = StaffTalks.wantsFixedSalary(n)
        let factor = basis == "fix" ? (fixedSalaryRoles.contains(n.role) ? 1 : 1.03) : (wantsFixed && !part ? (fixedSalaryRoles.contains(n.role) ? 0.94 : 0.98) : 1)
        return (basis, factor)
    }

    static func skillCurve(_ skill: Double, lie: Bool = false, experience: Double = 6) -> Double { askSpread(skill: skill, experience: experience, lie: lie) }
    static func askCurve(tier: String, skill: Double) -> Double { askSpread(skill: skill, experience: (tiers[tier]!.exp.0 + tiers[tier]!.exp.1) / 2) }

    public static let goneElsewhere = -9

    public static func position(for n: Person, factor f: Double = 1) -> Negotiation.Position {
        let f = f > 0 ? f : 1
        return Negotiation.position(opening: n.askingMonthlyWage / f, direction: .higher, temperament: temperament(of: n), key: "\(n.id)")
    }

    public static func temperament(of n: Person) -> Negotiation.Temperament {
        Negotiation.temperament(personality: n.str("pers").isEmpty ? nil : n.str("pers"), key: "\(n.id)")
    }

    public static func answer(personID: Int, employer: Int, rank: String, offer: Double, factor: Double = 1, currency: Currency, about: Double,
                              state s: inout GameState) -> Negotiation.Response {
        guard var n = s.people[personID] else { return Negotiation.Response(.refuse) }
        var talk = Negotiation.State.resume(n, party: employer, week: s.week)
        let r = Negotiation.respond(offer: offer, position: position(for: n, factor: factor * n.num("tf", 1)), temperament: temperament(of: n), rank: rank, state: &talk,
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

    public static func probe(_ n: Person, offer: Double, factor: Double = 1, rank: String, talk: inout Negotiation.State, currency: Currency, about: Double,
                             state s: inout GameState) -> Negotiation.Response {
        Negotiation.respond(offer: offer, position: position(for: n, factor: factor), temperament: temperament(of: n), rank: rank, state: &talk,
                            week: s.week, step: currency.stepSize(about: about), random: &s.random)
    }

    public static func hire(_ personID: Int, into companyID: Int, monthlyWage offered: Double, state s: inout GameState, data: GameData,
                            terms: Terms = Terms(), fixedSalaryRoles: Set<String> = Hiring.fixedSalaryNorm) -> HireResult {
        guard let ci = s.companyIndex(companyID), let n0 = s.people[personID] else { return .refused }
        if n0.employerID != 0 { return .taken }
        let world = World(state: s, data: data)
        let wage0 = max(offered, world.minimumWage(s.companies[ci]))
        if wage0 > offered { s.note("The offer to \(n0.name) was raised to the minimum wage of \(world.country(s.companies[ci]).name).", companyID: companyID) }
        let part = terms.isPartTime
        let (basis, _) = payBasis(n0, terms: terms, fixedSalaryRoles: fixedSalaryRoles)
        if termsProblem(person: n0, terms: terms, company: s.companies[ci], state: s, data: data) != nil { return .planRefused }
        let factor = talkFactor(person: n0, terms: terms, company: s.companies[ci], state: s, data: data)
        let reply = answer(personID: personID, employer: companyID, rank: "worker", offer: wage0, factor: factor,
                           currency: world.currency(s.companies[ci]), about: 100, state: &s)
        switch reply.answer {
        case .refuse: return .refused
        case .walkAway: return .walkedAway
        case .counter(let c): return .countered(c)
        case .accept: break
        }
        guard var n = s.people[personID] else { return .refused }
        let plan: String? = (!part && (terms.payPlan == "mix" || terms.payPlan == "com") && PayPlans.eligible(role: n.role, trade: s.companies[ci].type, salesRoles: data.catalog.tables.salesRoles)) ? terms.payPlan : nil
        if plan == "com", n.num("sec") > 0.65, s.random.chance(0.6) { return .planRefused }
        var term = workingFixedTermWeeks.contains(terms.fixedTermWeeks) ? terms.fixedTermWeeks : 0
        var seasonEnd: Int? = nil
        if terms.seasonCount > 0, let months = terms.seasonMonths {
            guard let e = StaffTalks.seasonEnd(months: months, fromWeek: s.week, occurrences: terms.seasonCount) else { return .planRefused }
            seasonEnd = e; term = max(1, e - s.week)
        }
        if term > 0, FixedTerm.wantsPermanent(n) { return .planRefused }
        if term > 0, FixedTerm.renewalBlock(World(state: s, data: data).labour(s.companies[ci]), StaffMember(raw: [:]), weeks: term, now: s.week) != nil { return .planRefused }
        n.employerID = companyID
        s.people[personID] = n
        var m = StaffMember(raw: [:])
        m.id = personID; m.set("role", n.role); m.monthlyWage = wage0
        m.hiredWeek = s.week; m.payBasis = basis; m.lastRaiseWeek = s.week
        m.set("pm", 0); m.skillGain = 0; m.set("warn", 0); m.set("crs", 0)
        if part { StaffTalks.applyPartTime(&m, terms: terms, week: s.week) }
        else if terms.ownCar { m.set("ownCar", 1) }
        if m.flag("ownCar"), let bd = data.catalog[s.companies[ci].type], !PersonalEquipment.canUseOwnCar(role: m.role, bd, tables: data.catalog.tables) { m.set("ownCar", 0) }
        if let plan {
            let rate = terms.commissionRate > 0 ? terms.commissionRate : (PayPlans.mode(plan)?.defaultRate ?? 0)
            m.set("pay", .object(["m": .string(plan), "rate": .number(rate)])); m.set("commEma", 0)
            if plan == "com" { m.monthlyWage = 0 }
            if PayPlans.isExtra(role: m.role, trade: s.companies[ci].type, salesRoles: data.catalog.tables.salesRoles) { m.set("ppx", 1) }
        }
        if term > 0 { m.set("ft", s.week + term); m.set("ftl", term); m.set("fts", s.week) }
        _ = seasonEnd
        if let plan = terms.bonusPlan, let l = WorkerBonus.level(plan), !l.isNone { m.set("bp", l.id) }
        for x in terms.expenseItems where StaffExpenses.item(x) != nil { var ex = m.value("ex"); if ex.isNull { ex = .object([:]) }; ex[x] = 1; m.set("ex", ex) }
        ContractHistory.append(&m, week: s.week, kind: "hired", text: "Hired: " + EmploymentContract.typeLabels(m).joined(separator: ", ").lowercased() + ", \(ContractHistory.fmt(EmploymentContract.percent(m))) percent of a full week.")
        Agency.markHire(&m, person: n, week: s.week)
        var staff = s.companies[ci].staff
        staff.append(m)
        s.companies[ci].staff = staff
        for d in terms.promises { StaffPromises.make(&s, companyID: companyID, personID: personID, draft: d) }
        return .ok
    }

    public static let fixedSalaryNorm: Set<String> = ["dentist", "dentnurse", "vintner", "physio", "lawyer", "paralegal", "acct", "dev", "designer", "marketer",
                                                      "consult", "foreman", "engineer", "architect", "fishtech", "underw", "claims", "banker", "credit", "analyst", "propm"]
}
