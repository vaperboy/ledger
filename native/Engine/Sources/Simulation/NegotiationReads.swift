import Foundation
import GameCore
import Countries
import Businesses

/// A post someone can be hired into, for the one read that tells a screen the going rate. Every hiring screen shows it the same way.
public enum HirePost: Equatable, Sendable {
    case worker(role: String)
    case manager
    case assistant
    /// A post on the company's management team: "ceo" (managing director), "reg" (regional manager) or a department head ("sales", "ops", "fin", "hr", "mkt").
    case team(key: String)
    case executive(ManagerModel.ExecLevel)
    case office(role: String)
    case analyst
}

public extension GameEngine {
    /// What the post normally pays a month in this economy: the employer's opening offer in a pay discussion, the same for everyone in the post.
    /// The person's own ask stays hidden. Posts tied to a company need its id.
    func goingRate(for post: HirePost, companyID: Int? = nil) -> Double {
        let co = companyID.flatMap { state.company($0) }
        switch post {
        case .worker(let role): return Hiring.marketWage(role: role, company: co, state: state, data: data)
        case .manager: return ManagerModel.managerGoingRate(company: co, state: state, data: data)
        case .assistant: return ManagerModel.assistantGoingRate(company: co, state: state, data: data)
        case .team(let key): return co.map { ManagerModel.teamGoingRate(company: $0, key: key, state: state, data: data) } ?? 0
        case .executive(let level): return ManagerModel.executiveGoingRate(level: level, state: state, data: data)
        case .office(let role): return Headquarters.goingRate(role: role, state: state, data: data)
        case .analyst: return MarketMap.dataAnalystGoingRate(state: state, data: data)
        }
    }
}
