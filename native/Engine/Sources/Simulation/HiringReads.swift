import Foundation
import GameCore
import Countries
import Businesses

// The Hiring screen (new look, Oct 2026, option A): the three ways to look for people with what each costs, the pay the market gives for the
// role, and for each applicant only what the player can see before an interview. Reads `Hiring` (market wage, search sizes) and the Person
// record; nothing here changes the game, and nothing reveals what a candidate keeps back (true skill, lies, character, bad habits).

public struct HiringSearchOption: Identifiable, Equatable, Sendable {
    public var id: String { title }
    public var mode: Hiring.SearchMode
    public var title: String
    /// What it costs to run the search. Searches are free in the game today, so this is 0; it is read from `Hiring.searchFee`.
    public var fee: Double
    /// How many people it brings.
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
    /// The skill they say they have, 0-100 (what they claim, not what a trial week would show).
    public var claimedSkill: Double
    /// The years of experience on their CV (nil if the CV gives none).
    public var claimedExperienceYears: Double?
    /// The line from the CV.
    public var resume: String
    /// What they ask a month, and what the role pays on this labour market.
    public var askMonthly: Double
    public var marketMonthly: Double
    /// Their ask against the market: +0.03 is 3% above, -0.08 is 8% below.
    public var askVersusMarket: Double
    /// First impression from what is visible before an interview: their age, their CV and what they ask. It does not read character or true skill.
    public var seems: String
    public var referencesChecked: Bool
    /// What a paid trial week showed (about the true skill), once one has been done.
    public var trialSkill: Double?
    /// The portrait the engine gave this person ("c12.0"), nil when none.
    public var faceKey: String? = nil
    public var askYearly: Double { askMonthly * 12 }
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
    /// The three ways to look for people, with the cost of each (0 where the game charges nothing).
    func hiringSearchOptions() -> [HiringSearchOption] {
        func option(_ m: Hiring.SearchMode, _ title: String, _ note: String) -> HiringSearchOption {
            let n = Hiring.applicantsFound(m)
            return HiringSearchOption(mode: m, title: title, fee: Hiring.searchFee(m), applicantsMin: n.lowerBound, applicantsMax: n.upperBound, note: note)
        }
        return [option(.ads, "Job ad", "Ads reach many people, but skills vary."),
                option(.network, "Network", "People you know of: fewer, by word of mouth."),
                option(.agency, "Agency", "More people, with more of the experienced ones.")]
    }

    /// One applicant as the player sees them for a job at a company; nil if the person is not on the market or has no such job in view.
    func applicant(personID: Int, companyID: Int) -> Applicant? {
        guard let p = state.people[personID], p.employerID == 0 else { return nil }
        let market = marketWage(role: p.role, companyID: companyID)
        let versus = market > 0 ? p.askingMonthlyWage / market - 1 : 0
        let exp = claimedExperienceYears(personID: personID)
        return Applicant(personID: p.id, name: p.name, age: p.age, role: p.role, claimedSkill: p.claimedSkill, claimedExperienceYears: exp, resume: p.str("resume"),
                         askMonthly: p.askingMonthlyWage, marketMonthly: market, askVersusMarket: versus, seems: Self.firstImpression(askVersusMarket: versus, experience: exp),
                         referencesChecked: p.flag("checked"), trialSkill: p.value("trialRes").isNull ? nil : p.num("trialRes"), faceKey: p.faceKey)
    }

    /// The Hiring screen for a role at a company: the going pay, the ways to search and the people found (`personIDs`, as the search returned them).
    func hiringBoard(companyID: Int, role: String, personIDs: [Int]) -> HiringBoard {
        HiringBoard(companyID: companyID, role: role, roleName: data.catalog.tables.roles[role]?.name ?? role, marketMonthly: marketWage(role: role, companyID: companyID),
                    searches: hiringSearchOptions(), applicants: personIDs.compactMap { applicant(personID: $0, companyID: companyID) })
    }

    /// Eager (asks less than the market, or is new to the work), Proud (asks well above it), Steady otherwise.
    private static func firstImpression(askVersusMarket v: Double, experience: Double?) -> String {
        if v >= 0.10 { return "Proud" }
        if v <= -0.05 || (experience ?? 0) <= 1 { return "Eager" }
        return "Steady"
    }
}
