import Foundation
import GameCore
import Countries
import Employees
import Finance

public extension Hiring {
    static func askSpread(skill: Double, experience: Double, lie: Bool = false) -> Double {
        let bySkill = (skill - 55) / 55 * 0.2
        let byExperience = (min(max(experience, 0), 20) - 6) / 20 * 0.08
        return clamp(1 + bySkill + byExperience + (lie ? 0.03 : 0), 0.78, 1.35)
    }

    struct AskReading: Equatable, Sendable {
        public var factor: Double
        public var reasons: [String]
    }

    static func askReading(person n: Person, terms: Terms, company co: Company?, state s: GameState, data: GameData) -> AskReading {
        var f = 1.0
        var why: [String] = []
        if let co {
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
            let heads = co.staff.count + (co.managerID != nil ? 1 : 0)
            let weeksOld = max(0, s.week - co.foundedWeek)
            let startup = weeksOld < 26
            let established = weeksOld >= 156 && heads >= 8
            let growthOffered = terms.expectations.contains("responsibility") || terms.expectations.contains("career")
                || terms.promises.contains { $0.kind == .promotion || $0.kind == .responsibility }
            if startup { f += 0.015; why.append("It is a new business, so the future is less certain.") }
            if established { f -= 0.01; why.append("It is an established employer.") }
            if heads <= 3 && growthOffered && n.num("sec") <= 0.65 {
                f -= 0.02; why.append("A small team with real responsibility appeals to them.")
            }
            _ = w
        }
        var package = 0.0
        if let plan = terms.bonusPlan, let l = WorkerBonus.level(plan), !l.isNone { package += 0.012; why.append("The bonus plan is worth something to them.") }
        if !terms.expenseItems.isEmpty { package += 0.008 * Double(min(3, terms.expenseItems.count)) }
        if !terms.promises.isEmpty {
            package += 0.008 * Double(min(3, terms.promises.count))
            why.append("What you have promised counts as part of the offer.")
        }
        if terms.ownCar { package += 0.0 }
        if let co {
            let group = StaffPerks.group(ofRole: n.role)
            let perks = StaffPerks.onPerks(co).filter { StaffPerks.covers(co, $0, group: group) }
            if !perks.isEmpty { package += min(0.025, 0.01 * Double(perks.count)); why.append("The company's perks count in its favour.") }
        }
        f -= min(0.06, package)
        if n.num("sec") > FixedTerm.securityThreshold {
            if terms.fixedTermWeeks > 0 || terms.seasonCount > 0 { f += 0.03; why.append("They would rather have a permanent job.") }
            else if terms.seasonMonths == nil { f -= 0.01 }
        }
        return AskReading(factor: clamp(f, 0.9, 1.12), reasons: why)
    }

    static func talkFactor(person n: Person, terms: Terms, company co: Company?, state s: GameState, data: GameData) -> Double {
        let (_, basis) = payBasis(n, terms: terms, fixedSalaryRoles: fixedSalaryNorm)
        let reading = askReading(person: n, terms: terms, company: co, state: s, data: data)
        return basis / reading.factor
    }

    static func askInThisTalk(_ n: Person, terms: Terms = Terms(), company co: Company?, state s: GameState, data: GameData) -> Double {
        n.askingMonthlyWage / talkFactor(person: n, terms: terms, company: co, state: s, data: data)
    }

    static func termsSignature(_ t: Terms) -> Int {
        var v = 17
        for x in [Int(t.effectiveHours * 100), t.fixedTermWeeks, t.seasonCount, t.ownCar ? 1 : 0, Int(t.commissionRate * 100), t.promises.count, t.expenseItems.count,
                  t.expectations.count, (t.seasonMonths ?? []).reduce(0) { $0 * 13 + $1 }, t.basis == "fix" ? 1 : 2, t.payPlan == nil ? 0 : (t.payPlan == "mix" ? 1 : 2)] { v = v &* 31 &+ x }
        for c in (t.bonusPlan ?? "").unicodeScalars { v = v &* 31 &+ Int(c.value) }
        for k in t.promises { for c in k.kind.rawValue.unicodeScalars { v = v &* 31 &+ Int(c.value) } }
        for e in t.expectations + t.expenseItems { for c in e.unicodeScalars { v = v &* 31 &+ Int(c.value) } }
        v &= 0x3fffffff
        return v == 0 ? 1 : v
    }

    static func maxHoursPerWeek(personID: Int) -> Double? {
        var r = HashedRandom("stu:\(personID)")
        if r.next() < 0.25 { return r.next() < 0.5 ? 20 : 30 }
        return nil
    }

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

    static var workingFixedTermWeeks: ClosedRange<Int> { 4...208 }
    static var workingPercentRange: ClosedRange<Double> { 10...100 }
    static var standardPercents: [Double] { [20, 50, 80, 100] }
}
