import Foundation
import GameCore
import Countries
import Finance
import Businesses

// Hiring rebuild, the public API for the screens: workplaces, promises per worker, job ads, the agency, the role catalog, duties, the one-page terms
// summary and the worker profile. Rules: Businesses/HiringRebuild.swift and HiringAds.swift.

public struct TermsCounterOption: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// A full-week monthly wage, in the unit every offer is made in.
    public var monthlyWage: Double
    public var annualEmployerCost: Double
}

/// The 'talking terms' and salary discussion on one page.
public struct TermsSummary: Equatable, Sendable {
    public var personID: Int
    public var name: String
    public var role: String
    /// What they ask (named by them, or the figure they would open with). A full-week monthly wage.
    public var salaryAsk: Double
    public var marketPay: Double
    public var yourOffer: Double
    public var hoursPerWeek: Double
    public var workingPercent: Double
    /// "Permanent, full time", "Part time", "Seasonal", "Fixed term of N weeks".
    public var contractType: String
    public var isPermanent: Bool
    public var promisesAsked: [String]
    public var startWeek: Int
    public var startDate: GameCalendar.Date
    /// The counter-offers the engine will answer: their ask, the going rate, the middle, and yours.
    public var counterOptions: [TermsCounterOption]
    public var reasons: [String]
    public var rounds: Int
    public var talkMood: String
    public var termsProblem: String?
}

public extension GameEngine {
    // MARK: Workplaces

    /// How many people can work at the company's premises, how many do, and how many places are free (nil = no limit).
    func workplaces(companyID: Int) -> WorkplaceInfo? { state.company(companyID).map { Workplaces.info($0, data: data) } }

    /// Why one more person cannot be hired at this company right now (nil when there is room). Hiring beyond capacity is refused with this reason.
    func hireBlock(companyID: Int) -> String? { state.company(companyID).flatMap { Workplaces.hireBlock($0, data: data) } }

    /// The places a rental listing holds ("N office places"), nil when the trade's premises have no limit. Read from the listing's size and the kind of place the trade moves into.
    func officeCapacity(forListing listing: CompanySetup.Listing, companyID: Int) -> Int? {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return nil }
        let kind = PremisesExtras.isHomeTrade(bd) ? PremisesExtras.placeKind(bd) : (bd.premisesKind ?? "none")
        return Workplaces.places(kind: kind, squareMetres: listing.squareMetres)
    }

    // MARK: Promises

    /// What one worker was promised: text, due date, patience left, status. The reminder comes within two weeks of the date (`PromiseReminders`).
    func promises(of employeeID: Int, companyID: Int) -> [WorkerPromise] { PromiseReminders.promises(state, personID: employeeID, companyID: companyID) }

    /// Keep a promise now, without waiting for the inbox question.
    @discardableResult
    mutating func keepPromise(employeeID: Int, promiseID: Int) -> PromiseReminders.Outcome {
        var r = PromiseReminders.Outcome.notPossible("")
        update { s, d, _ in r = PromiseReminders.keepNow(&s, personID: employeeID, promiseID: promiseID, data: d) }
        return r
    }

    /// Ask the worker to wait (twice at most; patience runs out after that).
    @discardableResult
    mutating func askToWait(employeeID: Int, promiseID: Int) -> PromiseReminders.Outcome {
        var r = PromiseReminders.Outcome.notPossible("")
        update { s, d, _ in r = PromiseReminders.askToWait(&s, personID: employeeID, promiseID: promiseID, data: d) }
        return r
    }

    // MARK: Job ads

    /// The name and organisation number the ad runs under.
    func jobAdForm(companyID: Int) -> (companyName: String, orgNumber: String)? { JobAds.form(state, companyID: companyID) }

    /// What a job ad for this role costs this company.
    func jobAdFee(companyID: Int, role: String) -> Double { JobAds.fee(state, companyID: companyID, role: role, data: data) }

    /// The core roles of the trade and the recommended extras, each with what it does when filled.
    func recommendedRoles(companyID: Int) -> [RoleOption] { state.company(companyID).map { RoleEffects.catalog(for: $0, data: data) } ?? [] }

    /// Post an ad for a role (free text or one of `recommendedRoles`). Pays the fee as an expense; applicants arrive over the next four weeks.
    @discardableResult
    mutating func postJobAd(companyID: Int, role: String) -> JobAds.PostResult {
        var r = JobAds.PostResult.notPossible("")
        update { s, d, _ in r = JobAds.post(&s, companyID: companyID, role: role, data: d) }
        return r
    }

    /// The people who have answered the company's ads (and agency searches) so far, as the Hiring screen shows them.
    func applicants(companyID: Int) -> [Applicant] {
        JobAds.applicantIDs(state, companyID: companyID).compactMap { applicant(personID: $0, companyID: companyID) }
    }

    // MARK: Agency

    func agencyFee(companyID: Int, role: String) -> Double { Agency.fee(state, companyID: companyID, role: role, data: data) }

    /// Engage an agency: a large fee now, three suggestions at once (returned as applicants), better-fitted ones over the next weeks, and 8 percent of
    /// the hired person's pay for the first 24 months.
    @discardableResult
    mutating func engageAgency(companyID: Int, role: String) -> Agency.EngageResult {
        var r = Agency.EngageResult.notPossible("")
        update { s, d, _ in r = Agency.engage(&s, companyID: companyID, role: role, data: d) }
        return r
    }

    // MARK: Duty and profile

    /// Give a hired person a duty from the company's role catalog (nil clears it): "seat him in my office while he does marketing".
    @discardableResult
    mutating func setDuty(companyID: Int, employeeID: Int, duty: String?) -> Bool {
        var ok = false
        update { s, d, _ in ok = RoleEffects.setDuty(&s, companyID: companyID, employeeID: employeeID, duty: duty, data: d) }
        return ok
    }

    func workerProfile(companyID: Int, employeeID: Int) -> WorkerProfile? { WorkerProfiles.profile(state, companyID: companyID, employeeID: employeeID, data: data) }

    // MARK: Terms on one page

    /// Everything the terms-and-salary page shows for a candidate and a draft, in one read. Wraps `hireSalaryTalk` and the draft options; changes nothing.
    func termsSummary(companyID: Int, candidateID: Int, terms: Hiring.Terms = Hiring.Terms(), offer: Double? = nil) -> TermsSummary? {
        guard let n = state.people[candidateID], n.employerID == 0, let ctx = postContext(.worker(role: n.role), companyID: companyID),
              let talk = hireSalaryTalk(post: .worker(role: n.role), companyID: companyID, personID: candidateID, terms: terms, offer: offer) else { return nil }
        let f = hireTalkFactor(.worker(role: n.role), person: n, terms: terms, ctx: ctx)
        let ask = talk.theirAsk ?? Self.rounded(Hiring.position(for: n, factor: f).opening, ctx.currency, ctx.about)
        let middle = Self.rounded((ask + talk.marketPay) / 2, ctx.currency, ctx.about)
        func option(_ id: String, _ title: String, _ wage: Double) -> TermsCounterOption {
            TermsCounterOption(id: id, title: title, monthlyWage: wage,
                               annualEmployerCost: hireCostBreakdown(.worker(role: n.role), companyID: companyID, personID: candidateID, offer: wage, terms: terms, ctx: ctx)?.totalAnnual ?? 0)
        }
        var opts = [option("ask", "Offer what they ask", ask), option("market", talk.marketPayLabel, talk.marketPay), option("middle", "Meet in the middle", middle)]
        if offer != nil { opts.append(option("yours", "Keep my offer", talk.yourOffer)) }
        let type: String = terms.fixedTermWeeks > 0 ? "Fixed term of \(terms.fixedTermWeeks) weeks" : terms.seasonMonths != nil ? "Seasonal" : terms.isPartTime ? "Part time" : "Permanent, full time"
        let asked = terms.promises.map { d in "\(d.kind.title) within \(d.dueInWeeks) weeks" + (d.detail.isEmpty ? "" : " (\(d.detail))") }
        return TermsSummary(personID: candidateID, name: n.name, role: n.role, salaryAsk: ask, marketPay: talk.marketPay, yourOffer: talk.yourOffer, hoursPerWeek: talk.hoursPerWeek,
                            workingPercent: talk.workingPercent, contractType: type, isPermanent: terms.fixedTermWeeks == 0 && terms.seasonMonths == nil, promisesAsked: asked,
                            startWeek: state.week, startDate: GameCalendar.date(week: state.week), counterOptions: opts, reasons: talk.reasons, rounds: talk.rounds,
                            talkMood: talk.mood, termsProblem: talk.termsProblem)
    }
}
