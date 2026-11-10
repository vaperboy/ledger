import Foundation
import GameCore
import Countries
import Finance
import Businesses

public struct TermsCounterOption: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var monthlyWage: Double
    public var annualEmployerCost: Double
}

public struct TermsSummary: Equatable, Sendable {
    public var personID: Int
    public var name: String
    public var role: String
    public var salaryAsk: Double
    public var marketPay: Double
    public var yourOffer: Double
    public var hoursPerWeek: Double
    public var workingPercent: Double
    public var contractType: String
    public var isPermanent: Bool
    public var promisesAsked: [String]
    public var startWeek: Int
    public var startDate: GameCalendar.Date
    public var counterOptions: [TermsCounterOption]
    public var reasons: [String]
    public var rounds: Int
    public var talkMood: String
    public var termsProblem: String?
}

public extension GameEngine {

    func workplaces(companyID: Int) -> WorkplaceInfo? { state.company(companyID).map { Workplaces.info($0, data: data) } }

    func hireBlock(companyID: Int, role: String? = nil) -> String? { state.company(companyID).flatMap { Workplaces.hireBlock($0, role: role, data: data) } }

    func roomListing(companyID: Int) -> CompanySetup.Listing? { Workplaces.roomListing(state, companyID: companyID, data: data) }

    @discardableResult
    mutating func moveForRoom(companyID: Int) -> CompanySetup.PremisesResult {
        guard let l = roomListing(companyID: companyID) else { return .bad }
        return takePremises(companyID: companyID, listing: l)
    }

    func officeCapacity(forListing listing: CompanySetup.Listing, companyID: Int) -> Int? {
        guard let co = state.company(companyID), let bd = data.catalog[co.type] else { return nil }
        let kind = PremisesExtras.isHomeTrade(bd) ? PremisesExtras.placeKind(bd) : (bd.premisesKind ?? "none")
        return Workplaces.places(kind: kind, squareMetres: listing.squareMetres)
    }

    func promises(of employeeID: Int, companyID: Int) -> [WorkerPromise] { PromiseReminders.promises(state, personID: employeeID, companyID: companyID) }

    @discardableResult
    mutating func keepPromise(employeeID: Int, promiseID: Int) -> PromiseReminders.Outcome {
        var r = PromiseReminders.Outcome.notPossible("")
        update { s, d, _ in r = PromiseReminders.keepNow(&s, personID: employeeID, promiseID: promiseID, data: d) }
        return r
    }

    @discardableResult
    mutating func askToWait(employeeID: Int, promiseID: Int) -> PromiseReminders.Outcome {
        var r = PromiseReminders.Outcome.notPossible("")
        update { s, d, _ in r = PromiseReminders.askToWait(&s, personID: employeeID, promiseID: promiseID, data: d) }
        return r
    }

    func jobAdForm(companyID: Int) -> (companyName: String, orgNumber: String)? { JobAds.form(state, companyID: companyID) }

    func jobAdFee(companyID: Int, role: String) -> Double { JobAds.fee(state, companyID: companyID, role: role, data: data) }

    func recommendedRoles(companyID: Int) -> [RoleOption] { state.company(companyID).map { RoleEffects.catalog(for: $0, data: data) } ?? [] }

    @discardableResult
    mutating func postJobAd(companyID: Int, role: String) -> JobAds.PostResult {
        var r = JobAds.PostResult.notPossible("")
        update { s, d, _ in r = JobAds.post(&s, companyID: companyID, role: role, data: d) }
        return r
    }

    func applicants(companyID: Int) -> [Applicant] {
        JobAds.applicantIDs(state, companyID: companyID).compactMap { applicant(personID: $0, companyID: companyID) }
    }

    func agencyFee(companyID: Int, role: String) -> Double { Agency.fee(state, companyID: companyID, role: role, data: data) }

    @discardableResult
    mutating func engageAgency(companyID: Int, role: String) -> Agency.EngageResult {
        var r = Agency.EngageResult.notPossible("")
        update { s, d, _ in r = Agency.engage(&s, companyID: companyID, role: role, data: d) }
        return r
    }

    @discardableResult
    mutating func setDuty(companyID: Int, employeeID: Int, duty: String?) -> Bool {
        var ok = false
        update { s, d, _ in ok = RoleEffects.setDuty(&s, companyID: companyID, employeeID: employeeID, duty: duty, data: d) }
        return ok
    }

    func workerProfile(companyID: Int, employeeID: Int) -> WorkerProfile? { WorkerProfiles.profile(state, companyID: companyID, employeeID: employeeID, data: data) }

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
