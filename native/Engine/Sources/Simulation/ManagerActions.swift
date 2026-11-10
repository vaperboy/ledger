import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses

public extension GameEngine {
    func managerQuality(companyID: Int) -> Double {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return 0 }
        return ManagerModel.quality(co, bd, people: state.people)
    }

    mutating func searchManagers(companyID: Int) -> [Person]? {
        var out: [Person]?
        update { s, data, _ in out = ManagerModel.search(&s, companyID: companyID, data: data) }
        return out
    }

    @discardableResult
    mutating func findSuccessor(companyID: Int) -> [Person]? {
        var out: [Person]?
        update { s, data, _ in out = ManagerModel.findSuccessor(&s, companyID: companyID, data: data) }
        return out
    }
    func successorCandidates(companyID: Int) -> [Person] { ManagerModel.successorCandidates(state, companyID: companyID) }

    mutating func interviewManager(personID: Int, skill: String) -> Double? {
        var out: Double?
        update { s, _, _ in out = ManagerModel.interview(&s, personID: personID, key: skill) }
        return out
    }

    mutating func checkManagerReferences(personID: Int, companyID: Int) -> Bool {
        var ok = false
        update { s, data, _ in ok = ManagerModel.referenceCheck(&s, personID: personID, companyID: companyID, data: data) }
        return ok
    }

    mutating func hireManager(personID: Int, companyID: Int, monthlyWage: Double, profitBonus: Double = 0) -> ManagerModel.HireResult {
        var r = ManagerModel.HireResult.refused
        update { s, data, _ in r = ManagerModel.hire(&s, personID: personID, companyID: companyID, monthlyWage: monthlyWage, profitBonus: profitBonus, data: data) }
        return r
    }

    @discardableResult
    mutating func dismissManager(companyID: Int) -> Double {
        var sev = 0.0
        update { s, data, _ in sev = ManagerModel.fire(&s, companyID: companyID, data: data) }
        return sev
    }

    @discardableResult
    mutating func setManagerBudget(companyID: Int, budget: Budget) -> SettingResult {
        applySetting(refuse: { $0.company(companyID) == nil ? "That company no longer exists." : nil }, probe: { $0.companySnapshot(companyID) }) { s, data, _ in ManagerModel.setBudget(&s, companyID: companyID, budget: budget, data: data) }
    }

    @discardableResult
    mutating func setManagerAuthority(companyID: Int, level: Int? = nil, buy: Double? = nil, pay: Double? = nil, ad: Double? = nil) -> SettingResult {
        guard let level else { return .unchanged }
        return setManagerBudget(companyID: companyID, budget: Budget(rawValue: min(2, max(0, level))) ?? .normal)
    }

    @discardableResult
    mutating func askManager(companyID: Int, key: String) -> String? {
        var say: String?
        let m = marketing
        update { s, data, _ in say = ManagerModel.ask(&s, companyID: companyID, key: key, data: data, marketing: m) }
        return say
    }

    mutating func searchAssistants(companyID: Int) -> [Person]? {
        var out: [Person]?
        update { s, data, _ in out = ManagerModel.searchAssistants(&s, companyID: companyID, data: data) }
        return out
    }

    mutating func hireAssistant(personID: Int, companyID: Int, monthlyWage: Double) -> ManagerModel.OfferResult {
        var r = ManagerModel.OfferResult.refused
        update { s, d, _ in r = ManagerModel.hireAssistant(&s, personID: personID, companyID: companyID, monthlyWage: monthlyWage, data: d) }
        return r
    }

    @discardableResult
    mutating func toggleAssistantDuty(companyID: Int, duty: String) -> Bool {
        var ok = false
        update { s, _, _ in ok = ManagerModel.toggleAssistantDuty(&s, companyID: companyID, duty: duty) }
        return ok
    }

    mutating func dismissAssistant(companyID: Int) { update { s, data, _ in ManagerModel.fireAssistant(&s, companyID: companyID, data: data) } }

    func managerWarning(companyID: Int) -> String? {
        ManagerModel.managerWarning(state, companyID: companyID, data: data)
    }

    func managerVoiceCard(companyID: Int) -> ManagerVoice.Scorecard? { ManagerVoice.scorecard(state, companyID: companyID, data: data) }
}
