import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses

/// The player's management actions: hire and replace a manager, set what they decide, ask them for changes, assistant managers,
/// promotions. Original: `ACT.mgr*`, `ACT.auth*`, `ACT.asst*` and `ACT.p11*`.
public extension GameEngine {
    /// How good the company's manager is, 0 to 1.
    func managerQuality(companyID: Int) -> Double {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return 0 }
        return ManagerModel.quality(co, bd, people: state.people)
    }

    /// Pay for an executive search; returns the candidates (nil if there is not enough cash).
    mutating func searchManagers(companyID: Int) -> [Person]? {
        var out: [Person]?
        update { s, data, _ in out = ManagerModel.search(&s, companyID: companyID, data: data) }
        return out
    }

    /// Ask a candidate one of the interview questions (three per candidate); returns what they said.
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

    mutating func hireManager(personID: Int, companyID: Int, monthlyWage: Double) -> ManagerModel.HireResult {
        var r = ManagerModel.HireResult.refused
        update { s, data, _ in r = ManagerModel.hire(&s, personID: personID, companyID: companyID, monthlyWage: monthlyWage, data: data) }
        return r
    }

    /// Dismiss the manager (three months of pay). Returns the severance.
    @discardableResult
    mutating func dismissManager(companyID: Int) -> Double {
        var sev = 0.0
        update { s, data, _ in sev = ManagerModel.fire(&s, companyID: companyID, data: data) }
        return sev
    }

    mutating func giveManagerRaise(companyID: Int) { update { s, data, _ in ManagerModel.raiseManager(&s, companyID: companyID, data: data) } }

    mutating func setManagerAuthority(companyID: Int, level: Int? = nil, buy: Double? = nil, pay: Double? = nil, ad: Double? = nil) {
        update { s, _, _ in ManagerModel.setAuthority(&s, companyID: companyID, level: level, buy: buy, pay: pay, ad: ad) }
    }

    mutating func meetManager(companyID: Int) -> Bool {
        var ok = false
        update { s, data, _ in ok = ManagerModel.meet(&s, companyID: companyID, data: data) }
        return ok
    }

    mutating func moveManager(from: Int, to: Int) -> Bool {
        var ok = false
        update { s, data, _ in ok = ManagerModel.move(&s, fromCompanyID: from, toCompanyID: to, data: data) }
        return ok
    }

    /// Ask the manager for a change (a key of `ManagerModel.askOptions`); returns what they answered.
    @discardableResult
    mutating func askManager(companyID: Int, key: String) -> String? {
        var say: String?
        let m = marketing
        update { s, data, _ in say = ManagerModel.ask(&s, companyID: companyID, key: key, data: data, marketing: m) }
        return say
    }

    // Assistant managers

    mutating func searchAssistants(companyID: Int) -> [Person]? {
        var out: [Person]?
        update { s, data, _ in out = ManagerModel.searchAssistants(&s, companyID: companyID, data: data) }
        return out
    }

    mutating func hireAssistant(personID: Int, companyID: Int, monthlyWage: Double) -> ManagerModel.OfferResult {
        var r = ManagerModel.OfferResult.refused
        update { s, _, _ in r = ManagerModel.hireAssistant(&s, personID: personID, companyID: companyID, monthlyWage: monthlyWage) }
        return r
    }

    @discardableResult
    mutating func toggleAssistantDuty(companyID: Int, duty: String) -> Bool {
        var ok = false
        update { s, _, _ in ok = ManagerModel.toggleAssistantDuty(&s, companyID: companyID, duty: duty) }
        return ok
    }

    mutating func dismissAssistant(companyID: Int) { update { s, data, _ in ManagerModel.fireAssistant(&s, companyID: companyID, data: data) } }

    // Promotions

    func promotionPosts(companyID: Int, personID: Int) -> [ManagerModel.PromotionPost] {
        ManagerModel.promotionPosts(state, companyID: companyID, personID: personID, data: data)
    }

    mutating func offerPromotion(companyID: Int, personID: Int, post: String, monthlyWage: Double, terms: ManagerModel.PromotionTerms = .init()) -> ManagerModel.PromotionOutcome {
        var r = ManagerModel.PromotionOutcome.unavailable("")
        update { s, data, _ in r = ManagerModel.offerPromotion(&s, companyID: companyID, personID: personID, post: post, monthlyWage: monthlyWage, terms: terms, data: data) }
        return r
    }
}
