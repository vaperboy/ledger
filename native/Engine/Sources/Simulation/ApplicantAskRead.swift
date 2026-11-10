import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses

public extension GameEngine {
    func applicantAskPreview(personID: Int, companyID: Int) -> (ask: Double, market: Double)? {
        guard let n = state.people[personID], n.employerID == 0 else { return nil }
        let post: HirePost = .worker(role: n.role)
        guard let ctx = postContext(post, companyID: companyID) else { return nil }
        let f: Double = hireTalkFactor(post, person: n, terms: Hiring.Terms(), ctx: ctx)
        let ask: Double = Self.rounded(Hiring.position(for: n, factor: f).opening, ctx.currency, ctx.about)
        return (ask, goingRate(for: post, companyID: companyID))
    }
}
