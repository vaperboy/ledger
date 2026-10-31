import Foundation
import GameCore
import Countries
import Employees
import Businesses

// The Negotiation screen's two reads (new look, Oct 2026): what a hire at a wage costs a year with the employer's charges, and where a pay talk
// with a candidate stands. Reads only; the hidden figures of the candidate (what they would settle for, how much patience is left) are not in them.

/// What hiring someone at a monthly wage costs a year: the wages and the employer's charges (social contributions, pension, injury insurance).
public struct HiringYearlyCost: Equatable, Sendable {
    /// The monthly wage the engine would book: the offer, lifted to the country's minimum wage if it is lower.
    public var monthlyWage: Double
    public var yearlyWages: Double
    public var yearlyOnCosts: Double
    public var yearlyTotal: Double { yearlyWages + yearlyOnCosts }
    public var liftedToMinimum: Bool
}

/// A pay talk that is open with a candidate, as the player has lived it so far.
public struct HiringTalk: Equatable, Sendable {
    public var personID: Int
    /// Offers the candidate has answered so far for this company (0 = no talk yet).
    public var rounds: Int
    /// The figure they named last (a monthly wage), 0 if none stands.
    public var standingCounter: Double
    /// Your last offer in this talk (a monthly wage), 0 if none.
    public var lastOffer: Double
    public var isOpen: Bool { rounds > 0 }
}

public extension GameEngine {
    func hiringYearlyCost(companyID: Int, monthlyWage: Double) -> HiringYearlyCost? {
        guard let co = state.company(companyID) else { return nil }
        let world = World(state: state, data: data)
        let minimum = world.minimumWage(co)
        let wage = max(monthlyWage, minimum)
        let b = EmployerCost.monthly(wage: wage, country: world.country(co))
        return HiringYearlyCost(monthlyWage: wage, yearlyWages: wage * 12, yearlyOnCosts: b.totalAnnual - wage * 12, liftedToMinimum: wage > monthlyWage)
    }

    /// The employer cost of a hire under the given contract terms: the same breakdown payroll will book (hours, percentage, contributions, insurance,
    /// paid-leave cover, benefits, monthly and annual). `monthlyWage` is the offer for a full week.
    func hiringEmployerCost(companyID: Int, personID: Int, monthlyWage: Double, terms: Hiring.Terms = Hiring.Terms()) -> EmployerCost.Breakdown? {
        EmployerCosts.hire(companyID: companyID, personID: personID, offered: monthlyWage, terms: terms, state: state, data: data)
    }

    /// One employee's employer cost as payroll books it.
    func employerCost(companyID: Int, personID: Int) -> EmployerCost.Breakdown? {
        guard let co = state.company(companyID), let m = co.staff.first(where: { $0.id == personID }) else { return nil }
        return EmployerCosts.staff(m, company: co, state: state, data: data)
    }

    /// The whole company's monthly people cost (every job, manager, perks and expenses).
    func companyEmployerCost(companyID: Int) -> EmployerCosts.CompanyCost? {
        state.company(companyID).map { EmployerCosts.company($0, state: state, data: data) }
    }

    func hiringTalk(personID: Int, companyID: Int) -> HiringTalk {
        guard let p = state.people[personID] else { return HiringTalk(personID: personID, rounds: 0, standingCounter: 0, lastOffer: 0) }
        let t = Negotiation.State.resume(p, party: companyID, week: state.week)
        return HiringTalk(personID: personID, rounds: t.round, standingCounter: t.counter, lastOffer: t.lastOffer)
    }
}
