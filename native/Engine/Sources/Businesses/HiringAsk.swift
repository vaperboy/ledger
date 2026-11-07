import Foundation
import GameCore
import Countries
import Employees
import Finance

/// What a candidate asks and why: asks are CENTRED on the market pay of the job with a spread by skill and experience
/// (no age-group multipliers); on top of that the candidate looks at the company that offers (its finances, size and stage) and at the whole package
/// (a better package lowers the ask a little). Nothing here is shown as a number to the player: `reasons` are plain words for the salary page.
public extension Hiring {
    /// How much a person's skill and experience move their ask around the market pay: about 1 for a typical candidate (skill in the middle fifties,
    /// a few years of experience), 0.82 for a beginner, up to 1.3 for an outstanding veteran. One curve for candidates and for whoever weighs them (`AutoHire`).
    static func askSpread(skill: Double, experience: Double, lie: Bool = false) -> Double {
        let bySkill = (skill - 55) / 55 * 0.2
        let byExperience = (min(max(experience, 0), 20) - 6) / 20 * 0.08
        return clamp(1 + bySkill + byExperience + (lie ? 0.03 : 0), 0.78, 1.35)
    }

    /// The company side of an ask: reasons and the multiplier they add up to.
    struct AskReading: Equatable, Sendable {
        /// Multiplies the candidate's ask (1 = no change). Between 0.9 and 1.12.
        public var factor: Double
        /// In words: why the ask is a little higher or lower for this company and this package. Never a number.
        public var reasons: [String]
    }

    /// Adjust a candidate's ask for the company that makes the offer and the whole contract package. `terms` is the page-1 draft; a default `Terms()` is a
    /// plain permanent job. Deterministic (no random draw), so the figure shown is the figure the answer uses.
    static func askReading(person n: Person, terms: Terms, company co: Company?, state s: GameState, data: GameData) -> AskReading {
        var f = 1.0
        var why: [String] = []
        if let co {
            // Finances: a company that is short of money, late with its bills or losing money asks more of a new hire (risk); a comfortable one a little less.
            let w = World(state: s, data: data)
            let monthlyPeople = EmployerCosts.company(co, state: s, data: data).totalMonthly
            let runwayMonths = monthlyPeople > 0 ? co.cash / monthlyPeople : 6
            let lately = co.monthlyHistory.suffix(3)
            let profit = lately.reduce(0) { $0 + $1.profit }
            if co.unpaidMonths > 0 || co.wageShortfall > 0 || co.weeksNegative > 2 {
                f += 0.04; why.append("The company has been late with its bills, which makes the job look risky.")
            } else if runwayMonths < 1.5 && !lately.isEmpty {
                f += 0.02; why.append("The company has little cash in hand.")
            } else if runwayMonths >= 6 && (lately.isEmpty || profit > 0) {
                f -= 0.01; why.append("The company looks financially safe.")
            }
            // Size and stage: a young or very small business is a gamble, but offers room to grow; an established one is a safe, steady employer.
            let heads = co.staff.count + (co.managerID != nil ? 1 : 0)
            let weeksOld = max(0, s.week - co.foundedWeek)
            let startup = weeksOld < 26
            let established = weeksOld >= 156 && heads >= 8
            let growthOffered = terms.expectations.contains("responsibility") || terms.expectations.contains("career")
                || terms.promises.contains { $0.kind == .promotion || $0.kind == .responsibility }
            if startup { f += 0.015; why.append("It is a new business, so the future is less certain.") }
            if established { f -= 0.01; why.append("It is an established employer.") }
            if heads <= 3 && growthOffered && n.num("sec") <= 0.65 {
                // Some people value responsibility and a chance to grow in a small business; not everyone, and not for nothing.
                f -= 0.02; why.append("A small team with real responsibility appeals to them.")
            }
            _ = w
        }
        // The whole package: each real extra lowers the ask a little; the first few count most.
        var package = 0.0
        if let plan = terms.bonusPlan, let l = WorkerBonus.level(plan), !l.isNone { package += 0.012; why.append("The bonus plan is worth something to them.") }
        if !terms.expenseItems.isEmpty { package += 0.008 * Double(min(3, terms.expenseItems.count)) }
        if !terms.promises.isEmpty {
            package += 0.008 * Double(min(3, terms.promises.count))
            why.append("What you have promised counts as part of the offer.")
        }
        if terms.ownCar { package += 0.0 }   // an own car is paid by mileage: neutral
        if let co {
            let group = StaffPerks.group(ofRole: n.role)
            let perks = StaffPerks.onPerks(co).filter { StaffPerks.covers(co, $0, group: group) }
            if !perks.isEmpty { package += min(0.025, 0.01 * Double(perks.count)); why.append("The company's perks count in its favour.") }
        }
        f -= min(0.06, package)
        // Security: someone who needs it values a permanent contract and wants more for a temporary one (and may refuse it, see `hire`).
        if n.num("sec") > FixedTerm.securityThreshold {
            if terms.fixedTermWeeks > 0 || terms.seasonCount > 0 { f += 0.03; why.append("They would rather have a permanent job.") }
            else if terms.seasonMonths == nil { f -= 0.01 }
        }
        return AskReading(factor: clamp(f, 0.9, 1.12), reasons: why)
    }

    /// The factor `Hiring.answer` needs for this person, terms and company: the pay-basis value (a fixed salary is worth a little more or less than the same
    /// figure by the hour) over the company/package reading of the ask. Offers are made in the unit of a full week.
    static func talkFactor(person n: Person, terms: Terms, company co: Company?, state s: GameState, data: GameData) -> Double {
        let (_, basis) = payBasis(n, terms: terms, fixedSalaryRoles: fixedSalaryNorm)
        let reading = askReading(person: n, terms: terms, company: co, state: s, data: data)
        return basis / reading.factor
    }

    /// What this person opens with in a talk with this company about these terms (their ask on the CV, read for the company and the package), a full-week
    /// monthly wage. For callers that hire at the ask (company set-up, taking over a rival's staff).
    static func askInThisTalk(_ n: Person, terms: Terms = Terms(), company co: Company?, state s: GameState, data: GameData) -> Double {
        n.askingMonthlyWage / talkFactor(person: n, terms: terms, company: co, state: s, data: data)
    }

    /// A fingerprint of everything in the terms that moves the ask, so a talk knows when its standing figures belong to other terms.
    static func termsSignature(_ t: Terms) -> Int {
        // A stable fold (Swift's Hasher is seeded per process).
        var v = 17
        for x in [Int(t.effectiveHours * 100), t.fixedTermWeeks, t.seasonCount, t.ownCar ? 1 : 0, Int(t.commissionRate * 100), t.promises.count, t.expenseItems.count,
                  t.expectations.count, (t.seasonMonths ?? []).reduce(0) { $0 * 13 + $1 }, t.basis == "fix" ? 1 : 2, t.payPlan == nil ? 0 : (t.payPlan == "mix" ? 1 : 2)] { v = v &* 31 &+ x }
        for c in (t.bonusPlan ?? "").unicodeScalars { v = v &* 31 &+ Int(c.value) }
        for k in t.promises { for c in k.kind.rawValue.unicodeScalars { v = v &* 31 &+ Int(c.value) } }
        for e in t.expectations + t.expenseItems { for c in e.unicodeScalars { v = v &* 31 &+ Int(c.value) } }
        v &= 0x3fffffff
        return v == 0 ? 1 : v
    }

    // MARK: Hours

    /// The most hours a week this person can work, when something limits it (one candidate in four studies and can work 20 or 30 hours at most).
    /// An explicit constraint: an offer over it is refused with a reason (`termsProblem`), never silently cut. Stable per person.
    static func maxHoursPerWeek(personID: Int) -> Double? {
        var r = HashedRandom("stu:\(personID)")
        if r.next() < 0.25 { return r.next() < 0.5 ? 20 : 30 }
        return nil
    }

    /// Why these terms cannot be agreed with this person, in words; nil when nothing stands in the way. The hire door answers `.planRefused` for the same reason.
    static func termsProblem(person n: Person, terms: Terms, company co: Company?, state s: GameState, data: GameData) -> String? {
        let first = n.name.split(separator: " ").first.map(String.init) ?? "They"
        if terms.percent != 0, !workingPercentRange.contains(terms.percent) {
            return "A working percentage has to be between \(Int(workingPercentRange.lowerBound)) and \(Int(workingPercentRange.upperBound)) percent."
        }
        let hours = terms.effectiveHours > 0 ? terms.effectiveHours : (terms.seasonMonths != nil ? 30 : StaffModel.fullWeekHours)
        if terms.isPartTime, let cap = maxHoursPerWeek(personID: n.id), hours > cap + 1e-9 {
            return "\(first) studies and can work at most \(Int(cap)) hours a week."
        }
        if terms.fixedTermWeeks != 0, !(workingFixedTermWeeks.contains(terms.fixedTermWeeks)) {
            return "A temporary contract runs for between \(workingFixedTermWeeks.lowerBound) and \(workingFixedTermWeeks.upperBound) weeks."
        }
        if terms.fixedTermWeeks > 0 && terms.seasonMonths != nil && terms.seasonCount > 0 {
            return "A seasonal job ends with its season; choose either a number of seasons or a temporary term."
        }
        if terms.seasonCount > 0 && terms.seasonMonths == nil { return "Seasonal terms need the months of the season." }
        if let months = terms.seasonMonths, months.isEmpty || months.contains(where: { !(1...12).contains($0) }) { return "Choose the months of the season." }
        if terms.fixedTermWeeks > 0, let co, let lab = Optional(World(state: s, data: data).labour(co)),
           let why = FixedTerm.renewalBlock(lab, StaffMember.init(raw: [:]), weeks: terms.fixedTermWeeks, now: s.week) { return why }
        if let plan = terms.bonusPlan, WorkerBonus.level(plan) == nil { return "That bonus plan does not exist." }
        for x in terms.expenseItems where StaffExpenses.item(x) == nil { return "That expense does not exist." }
        for p in terms.promises where !p.isPlausible { return "A promise needs a due date in the future." }
        return nil
    }

    /// Weeks a temporary (fixed-term) contract may run, as the engine accepts them (the choices the screens offer are `FixedTerm.termChoices`).
    static var workingFixedTermWeeks: ClosedRange<Int> { 4...208 }
    /// The working percentages a contract may have: the usual ones are 20, 50, 80 and 100 (`standardPercents`), any value in this range is accepted.
    static var workingPercentRange: ClosedRange<Double> { 10...100 }
    static var standardPercents: [Double] { [20, 50, 80, 100] }
}
