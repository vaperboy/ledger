import Foundation
import GameCore
import Countries
import Businesses

public struct HiringSearchOption: Identifiable, Equatable, Sendable {
    public var id: String { title }
    public var mode: Hiring.SearchMode
    public var title: String
    public var fee: Double
    public var applicantsMin: Int
    public var applicantsMax: Int
    public var note: String
}

public struct Applicant: Identifiable, Equatable, Sendable {
    public var id: Int { personID }
    public var personID: Int
    public var name: String
    public var age: Int
    public var role: String
    public var cvImpression: String
    public var claimedExperienceYears: Double?
    public var resume: String
    public var marketMonthly: Double
    public var seems: String
    public var referencesChecked: Bool
    public var trialObservations: [String]
    public var faceKey: String? = nil
    public var marketYearly: Double { marketMonthly * 12 }
}

public struct HiringBoard: Equatable, Sendable {
    public var companyID: Int
    public var role: String
    public var roleName: String
    public var marketMonthly: Double
    public var searches: [HiringSearchOption]
    public var applicants: [Applicant]
    public var marketYearly: Double { marketMonthly * 12 }
}

public extension GameEngine {
    func hiringSearchOptions() -> [HiringSearchOption] {
        func option(_ m: Hiring.SearchMode, _ title: String, _ note: String) -> HiringSearchOption {
            let n = Hiring.applicantsFound(m)
            return HiringSearchOption(mode: m, title: title, fee: Hiring.searchFee(m), applicantsMin: n.lowerBound, applicantsMax: n.upperBound, note: note)
        }
        return [option(.ads, "Job ad", "Ads reach many people over a few weeks, but skills vary."),
                option(.agency, "Agency", "Costs much more and keeps a share of the pay for two years: suggestions now, better fits later.")]
    }

    func applicant(personID: Int, companyID: Int) -> Applicant? {
        guard let p = state.people[personID], p.employerID == 0 else { return nil }
        let market = marketWage(role: p.role, companyID: companyID)
        let exp = claimedExperienceYears(personID: personID)
        return Applicant(personID: p.id, name: p.name, age: p.age, role: p.role, cvImpression: Self.cvImpression(claimed: p.claimedSkill, experience: exp), claimedExperienceYears: exp,
                         resume: p.str("resume"), marketMonthly: market, seems: Self.firstImpression(experience: exp),
                         referencesChecked: p.flag("checked"), trialObservations: p.value("trialObs").array.map { $0.string }, faceKey: p.faceKey)
    }

    func hiringBoard(companyID: Int, role: String, personIDs: [Int]) -> HiringBoard {
        HiringBoard(companyID: companyID, role: role, roleName: data.catalog.tables.roles[role]?.name ?? role, marketMonthly: marketWage(role: role, companyID: companyID),
                    searches: hiringSearchOptions(), applicants: personIDs.compactMap { applicant(personID: $0, companyID: companyID) })
    }

    private static func firstImpression(experience: Double?) -> String {
        if (experience ?? 0) <= 1 { return "Eager" }
        if (experience ?? 0) >= 12 { return "Seasoned" }
        return "Steady"
    }

    static func cvImpression(claimed: Double, experience: Double?) -> String {
        let level = claimed >= 70 ? "presents as highly capable" : claimed >= 50 ? "presents as capable" : claimed >= 30 ? "presents as still learning the work" : "presents as a beginner"
        guard let e = experience, e > 0 else { return level }
        return level + ", with \(String(format: "%g", e)) years on the CV"
    }
}
