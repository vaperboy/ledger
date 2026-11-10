import Foundation
import GameCore
import Countries
import Employees
import Businesses

public struct HiringYearlyCost: Equatable, Sendable {
    public var monthlyWage: Double
    public var yearlyWages: Double
    public var yearlyOnCosts: Double
    public var yearlyTotal: Double { yearlyWages + yearlyOnCosts }
    public var liftedToMinimum: Bool
}

public struct HiringTalk: Equatable, Sendable {
    public var personID: Int
    public var rounds: Int
    public var standingCounter: Double
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

    func hiringEmployerCost(companyID: Int, personID: Int, monthlyWage: Double, terms: Hiring.Terms = Hiring.Terms()) -> EmployerCost.Breakdown? {
        EmployerCosts.hire(companyID: companyID, personID: personID, offered: monthlyWage, terms: terms, state: state, data: data)
    }

    func employerCost(companyID: Int, personID: Int) -> EmployerCost.Breakdown? {
        guard let co = state.company(companyID), let m = co.staff.first(where: { $0.id == personID }) else { return nil }
        return EmployerCosts.staff(m, company: co, state: state, data: data)
    }

    func companyEmployerCost(companyID: Int) -> EmployerCosts.CompanyCost? {
        state.company(companyID).map { EmployerCosts.company($0, state: state, data: data) }
    }

    func hiringTalk(personID: Int, companyID: Int) -> HiringTalk {
        guard let p = state.people[personID] else { return HiringTalk(personID: personID, rounds: 0, standingCounter: 0, lastOffer: 0) }
        let t = Negotiation.State.resume(p, party: companyID, week: state.week)
        return HiringTalk(personID: personID, rounds: t.round, standingCounter: t.counter, lastOffer: t.lastOffer)
    }
}
