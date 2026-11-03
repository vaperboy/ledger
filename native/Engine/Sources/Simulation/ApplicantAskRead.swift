import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses

public extension GameEngine {
    /// What an applicant for a worker post would open with (default terms), against the going rate for the post, both as full-week monthly wages.
    /// A read only: it names nothing in the talk and changes nothing (`hearTheirAsk` is what the talk keeps).
    func applicantAskPreview(personID: Int, companyID: Int) -> (ask: Double, market: Double)? {
        guard let n = state.people[personID], n.employerID == 0 else { return nil }
        let post: HirePost = .worker(role: n.role)
        guard let ctx = postContext(post, companyID: companyID) else { return nil }
        let f: Double = hireTalkFactor(post, person: n, terms: Hiring.Terms(), ctx: ctx)
        let ask: Double = Self.rounded(Hiring.position(for: n, factor: f).opening, ctx.currency, ctx.about)
        return (ask, goingRate(for: post, companyID: companyID))
    }
}
