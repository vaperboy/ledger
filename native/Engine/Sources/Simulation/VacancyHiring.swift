import Foundation
import GameCore
import Countries
import Businesses

/// Open posts: how the owner (or the screen on the owner's behalf) searches for and hires into each vacancy of `teamOverview().vacancies`, and what the
/// boss above the post does about it (`HierarchyHiring`: the CEO appoints the chain manager, the chain manager the regional managers, the regional
/// manager the store managers). The owner can always search and hire into any post themselves; this is the override of the delegated hire.

/// Where a vacancy is filled: the post for the going rate and the two-page flow, and the employer ids the flow needs.
public struct VacancyRoute: Equatable, Sendable {
    public var post: HirePost
    public var companyID: Int?
    public var chainID: Int?
    public var city: String?
    public var roleTitle: String
    /// What the agency search costs the owner.
    public var searchFee: Double
}

public extension GameEngine {
    /// The route into a vacancy, nil for posts with their own screen (main-office roles).
    func vacancyRoute(_ v: TeamOverview.Vacancy) -> VacancyRoute? {
        let fee = ManagerModel.searchFee(currency: homeCurrency)
        switch v.post {
        case "mgr": return v.companyID.map { VacancyRoute(post: .manager, companyID: $0, chainID: nil, city: nil, roleTitle: v.title, searchFee: fee) }
        case "team": return v.companyID.map { VacancyRoute(post: .team(key: v.key), companyID: $0, chainID: nil, city: nil, roleTitle: v.title, searchFee: fee) }
        case "chainmgr": return VacancyRoute(post: .executive(.chainmgr), companyID: nil, chainID: v.chainID, city: nil, roleTitle: v.title, searchFee: fee)
        case "ceo56": return VacancyRoute(post: .executive(.ceo56), companyID: nil, chainID: v.chainID, city: nil, roleTitle: v.title, searchFee: fee)
        case "region": return VacancyRoute(post: .executive(.region), companyID: nil, chainID: v.chainID, city: v.key, roleTitle: v.title, searchFee: fee)
        case "md": return VacancyRoute(post: .executive(.md), companyID: nil, chainID: nil, city: nil, roleTitle: v.title, searchFee: fee)
        default: return nil
        }
    }

    /// Pay the search and get the shortlist for a vacancy (nil when the cash is not there or the post has no route).
    mutating func searchVacancy(_ v: TeamOverview.Vacancy) -> [Person]? {
        guard let route = vacancyRoute(v) else { return nil }
        switch route.post {
        case .manager:
            guard let id = route.companyID else { return nil }
            if let co = state.company(id), !co.value("mgrNotice").isNull { return findSuccessor(companyID: id) }
            return searchManagers(companyID: id)
        case .team(let key): return route.companyID.flatMap { searchTeam(companyID: $0, key: key) }
        case .executive(let level): return searchExecutive(level)
        default: return nil
        }
    }

    /// One line for the screens on who hires into this vacancy and with what authority, in words. Empty when only the owner can.
    func vacancyHirerLine(_ v: TeamOverview.Vacancy) -> String {
        guard let name = v.hirerName else { return "" }
        let title = (v.hirerTitle ?? "boss").lowercased()
        switch v.hirerAuthority {
        case ...0: return "\(name), the \(title), looks for someone and asks you before every hire."
        case 1: return "\(name), the \(title), hires within the limit you set and asks you above it."
        default: return "\(name), the \(title), hires on their own and tells you."
        }
    }
}
