import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses

// The two-page hiring negotiation.
//  PAGE 1, contract terms: `hireDraftOptions` says what can be chosen for this post (contract type, working percentage, seasonal or temporary duration,
//  benefits, vehicle, promises, career and responsibility expectations); the draft itself is `Hiring.Terms`. `hireTermsProblem` says in words why a draft
//  cannot be agreed.
//  PAGE 2, salary talk: `hireSalaryTalk` returns your offer, their ask (nil until the candidate has actually named one: after `hearTheirAsk` or after a
//  counter-offer), the market pay (the option is labelled "Offer market pay"), the actual hourly wage and the total annual employer cost of the offer.
//  Every figure is computed by the same code that books the hire (`EmployerCosts.hire`), so what is shown is what is applied.
//  `hireOffer` is the one action: it routes to the existing hire door of the post (all of them answer through `Hiring.answer`).

public struct HireOption: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
}

public struct HireDraftOptions: Equatable, Sendable {
    public var post: HirePost
    /// Which parts of page 1 apply to this post: "contractType", "percent", "duration", "benefits", "vehicle", "promises", "expectations".
    public var fields: [String]
    public var contractKinds: [HireOption]
    /// The usual working percentages (20, 50, 80, 100) and the range the engine accepts.
    public var percents: [Double]
    public var percentRange: ClosedRange<Double>
    /// The most hours a week this person can work, when something limits it (said, not silently applied).
    public var hoursLimit: Double?
    public var temporaryWeekChoices: [Int]
    public var temporaryWeekRange: ClosedRange<Int>
    public var seasons: [HireOption]
    public var busyMonths: [Int]
    public var payBases: [HireOption]
    public var bonusPlans: [HireOption]
    public var expenses: [HireOption]
    /// Perks the company already gives to people in this job (read-only here).
    public var companyPerks: [String]
    public var canUseOwnCar: Bool
    public var promiseKinds: [HireOption]
    public var expectations: [HireOption]
}

public struct HireSalaryTalk: Equatable, Sendable {
    public var post: HirePost
    public var personID: Int
    public var name: String
    /// Your offer, as a monthly wage for a full week (the unit every hire is offered in), lifted to the minimum wage where that applies.
    public var yourOffer: Double
    public var liftedToMinimum: Bool
    /// What they ask, in the same unit; nil until they have named it (after `hearTheirAsk`, or in a counter-offer).
    public var theirAsk: Double?
    /// The going rate for the post, same unit. The page's button is labelled `marketPayLabel`.
    public var marketPay: Double
    public var marketPayLabel: String
    /// The wage that will be booked per month for the contracted hours, and per hour.
    public var appliedMonthlyWage: Double
    public var hourlyWage: Double
    public var workingPercent: Double
    public var hoursPerWeek: Double
    public var monthlyEmployerCost: Double
    public var annualEmployerCost: Double
    /// The full breakdown for your offer, and for their ask when they have named one.
    public var employerCost: EmployerCost.Breakdown
    public var askEmployerCost: EmployerCost.Breakdown?
    public var marketHourlyWage: Double
    public var marketEmployerCost: EmployerCost.Breakdown
    /// "Offer what they ask" may be shown.
    public var canOfferTheirAsk: Bool
    /// Why their ask is a little higher or lower for this company and this package. Words, never figures.
    public var reasons: [String]
    /// Offers answered so far, and how they feel about the talk in words.
    public var rounds: Int
    public var mood: String
    /// Why the terms cannot be agreed, if they cannot.
    public var termsProblem: String?
}

public enum HireOutcome: Equatable, Sendable {
    case hired
    /// They name their own figure (a full-week monthly wage). `isFinal`: the next offer that falls short ends the talk.
    case countered(amount: Double, isFinal: Bool)
    case refused
    case walkedAway
    case taken
    /// They will not take the job on these terms (or the terms cannot be agreed): the reason, in words.
    case termsRefused(String)
    case blocked(String)
}

public extension GameEngine {
    internal struct PostContext {
        var employer: Int, rank: String, about: Double
        var currency: Currency, country: Country
        var company: Company?
    }

    internal func postContext(_ post: HirePost, companyID: Int?, chainID: Int? = nil) -> PostContext? {
        let w = World(state: state, data: data)
        switch post {
        case .worker, .manager, .assistant, .team:
            guard let id = companyID, let co = state.company(id) else { return nil }
            let rank: String, about: Double
            switch post {
            case .worker: rank = "worker"; about = 100
            case .manager: rank = "manager"; about = 500
            case .assistant: rank = "assistant"; about = 500
            case .team(let key): rank = ManagerModel.teamRank(key); about = 500
            default: rank = "worker"; about = 100
            }
            return PostContext(employer: id, rank: rank, about: about, currency: w.currency(co), country: w.country(co), company: co)
        case .executive(let level):
            return PostContext(employer: chainID ?? 0, rank: ManagerModel.execRank(level), about: 500, currency: ManagerModel.playerCurrency(state, data),
                               country: w.countries[state.homeCountryCode]!, company: nil)
        case .office:
            return PostContext(employer: -3, rank: "headOffice", about: 100, currency: ManagerModel.playerCurrency(state, data), country: w.countries[state.homeCountryCode]!, company: nil)
        case .analyst:
            return PostContext(employer: -3, rank: "analyst", about: 100, currency: ManagerModel.playerCurrency(state, data), country: w.countries[state.homeCountryCode]!, company: nil)
        }
    }

    /// The factor the answer uses for this person, post and draft: the pay-basis value over the company-and-package reading of the ask.
    internal func hireTalkFactor(_ post: HirePost, person n: Person, terms: Hiring.Terms, ctx: PostContext) -> Double {
        if case .worker = post { return Hiring.talkFactor(person: n, terms: terms, company: ctx.company, state: state, data: data) }
        return 1 / Hiring.askReading(person: n, terms: terms, company: ctx.company, state: state, data: data).factor
    }

    /// The employer cost of an offer at the post, in the unit of a full week offered.
    internal func hireCostBreakdown(_ post: HirePost, companyID: Int?, personID: Int, offer: Double, terms: Hiring.Terms, ctx: PostContext) -> EmployerCost.Breakdown? {
        if case .worker = post, let id = companyID { return EmployerCosts.hire(companyID: id, personID: personID, offered: offer, terms: terms, state: state, data: data) }
        let wage = ctx.company.map { max(offer, World(state: state, data: data).minimumWage($0)) } ?? offer
        return EmployerCost.monthly(wage: wage, country: ctx.country)
    }

    private func fields(for post: HirePost) -> [String] {
        switch post {
        case .worker: return ["contractType", "percent", "duration", "benefits", "vehicle", "promises", "expectations"]
        case .manager, .assistant, .team: return ["benefits", "promises", "expectations"]
        case .executive, .office, .analyst: return ["promises", "expectations"]
        }
    }

    /// PAGE 1: what can be chosen for this post and person.
    func hireDraftOptions(post: HirePost, companyID: Int?, personID: Int) -> HireDraftOptions? {
        guard let ctx = postContext(post, companyID: companyID), state.people[personID] != nil else { return nil }
        let co = ctx.company
        let isWorker: Bool = { if case .worker = post { return true }; return false }()
        let kinds = isWorker
            ? [HireOption(id: "permanent", title: "Permanent", detail: "No end date."),
               HireOption(id: "seasonal", title: "Seasonal", detail: "Works the busy months and is off, unpaid, the rest of the year; it can end with the season."),
               HireOption(id: "temporary", title: "Temporary", detail: "Ends on a date unless you renew it; the country's notice rules for the end of a term apply.")]
            : [HireOption(id: "permanent", title: "Permanent", detail: "No end date.")]
        let bases = isWorker
            ? [HireOption(id: "hour", title: "Hourly wage", detail: "Paid for the contracted hours."), HireOption(id: "fix", title: "Fixed monthly salary", detail: "The same each month.")]
            : [HireOption(id: "fix", title: "Fixed monthly salary", detail: "The same each month.")]
        let plans = isWorker ? WorkerBonus.levels.filter { !$0.isNone }.map { HireOption(id: $0.id, title: $0.name, detail: $0.detail) } : []
        let role = state.people[personID]!.role
        let exps = isWorker ? StaffExpenses.items(forRole: role).map { HireOption(id: $0.id, title: $0.name, detail: $0.detail) } : []
        var perks: [String] = []
        if let co { let g = StaffPerks.group(ofRole: role, isManager: { if case .manager = post { return true }; return false }()); perks = StaffPerks.onPerks(co).filter { StaffPerks.covers(co, $0, group: g) }.map { $0.name } }
        var ownCar = false
        if isWorker, let co, let bd = data.catalog[co.type] { ownCar = PersonalEquipment.canUseOwnCar(role: role, bd, tables: data.catalog.tables) }
        var promiseKinds: [HireOption] = []
        if fields(for: post).contains("promises") {
            let group: Bool = { switch post { case .executive, .office, .analyst: return true; default: return false } }()
            promiseKinds = StaffPromises.Kind.allCases.map { HireOption(id: $0.rawValue, title: $0.title, detail: group ? $0.fulfilledByForGroup : $0.fulfilledBy) }
        }
        let expectations = [HireOption(id: "responsibility", title: "Responsibility", detail: "You expect them to take on responsibility as the business grows."),
                            HireOption(id: "career", title: "A path forward", detail: "You see them growing into a bigger role."),
                            HireOption(id: "training", title: "Learning on the job", detail: "You expect them to train and develop.")]
        return HireDraftOptions(post: post, fields: fields(for: post), contractKinds: kinds, percents: isWorker ? Hiring.standardPercents : [100],
                                percentRange: isWorker ? Hiring.workingPercentRange : 100...100, hoursLimit: isWorker ? Hiring.maxHoursPerWeek(personID: personID) : nil,
                                temporaryWeekChoices: FixedTerm.termChoices, temporaryWeekRange: Hiring.workingFixedTermWeeks,
                                seasons: StaffTalks.seasons.map { HireOption(id: $0.id, title: $0.name, detail: StaffTalks.seasonText($0.months)) },
                                busyMonths: co.map { StaffTalks.busyMonths($0, data: data) } ?? [], payBases: bases, bonusPlans: plans, expenses: exps, companyPerks: perks,
                                canUseOwnCar: ownCar, promiseKinds: promiseKinds, expectations: expectations)
    }

    /// Why the draft cannot be agreed with this person (in words), nil when it can.
    func hireTermsProblem(post: HirePost, companyID: Int?, personID: Int, terms: Hiring.Terms) -> String? {
        guard let n = state.people[personID], let ctx = postContext(post, companyID: companyID) else { return "This candidate is no longer on the market." }
        if case .worker = post { return Hiring.termsProblem(person: n, terms: terms, company: ctx.company, state: state, data: data) }
        if terms.percent != 0 && terms.percent != 100 { return "This post is a full-time post." }
        if terms.fixedTermWeeks != 0 || terms.seasonMonths != nil { return "This post is permanent." }
        return nil
    }

    private func talkMood(_ t: Negotiation.State, rank: String, person n: Person) -> String {
        guard t.round > 0 else { return "Waiting to hear your offer." }
        let left = Negotiation.patience(rank: rank, temperament: Hiring.temperament(of: n)) - t.round
        return left >= 2 ? "Still open to talking." : left == 1 ? "Patience is wearing thin." : "This is their last word."
    }

    /// PAGE 2: the salary talk as it stands. `offer` is your draft figure (a full-week monthly wage); without one the market pay is shown as your offer.
    func hireSalaryTalk(post: HirePost, companyID: Int?, chainID: Int? = nil, personID: Int, terms: Hiring.Terms, offer: Double? = nil) -> HireSalaryTalk? {
        guard let n = state.people[personID], n.employerID == 0, let ctx = postContext(post, companyID: companyID, chainID: chainID) else { return nil }
        let market = goingRate(for: post, companyID: companyID)
        let talk = Negotiation.State.resume(n, party: ctx.employer, week: state.week)
        let sig = Hiring.termsSignature(terms)
        let f = hireTalkFactor(post, person: n, terms: terms, ctx: ctx)
        let standing = talk.terms == sig || talk.terms == 0
        var ask: Double? = nil
        if standing && talk.counter > 0 { ask = talk.counter }
        else if talk.asked || (talk.round > 0 && talk.counter > 0) { ask = Self.rounded(Hiring.position(for: n, factor: f).opening, ctx.currency, ctx.about) }
        let yours = offer ?? (talk.lastOffer > 0 ? talk.lastOffer : market)
        guard let mine = hireCostBreakdown(post, companyID: companyID, personID: personID, offer: yours, terms: terms, ctx: ctx),
              let atMarket = hireCostBreakdown(post, companyID: companyID, personID: personID, offer: market, terms: terms, ctx: ctx) else { return nil }
        let minimum = ctx.company.map { World(state: state, data: data).minimumWage($0) } ?? 0
        let hourFactor = StaffModel.fullWeekHours * 52 / 12
        let rank = ctx.rank
        return HireSalaryTalk(post: post, personID: personID, name: n.name, yourOffer: max(yours, minimum), liftedToMinimum: yours < minimum, theirAsk: ask, marketPay: market,
                              marketPayLabel: "Offer market pay", appliedMonthlyWage: mine.grossMonthlyWage, hourlyWage: mine.grossHourlyWage, workingPercent: mine.workingPercentage * 100,
                              hoursPerWeek: mine.contractedHoursPerWeek, monthlyEmployerCost: mine.totalMonthly, annualEmployerCost: mine.totalAnnual, employerCost: mine,
                              askEmployerCost: ask.flatMap { hireCostBreakdown(post, companyID: companyID, personID: personID, offer: $0, terms: terms, ctx: ctx) },
                              marketHourlyWage: market / hourFactor, marketEmployerCost: atMarket, canOfferTheirAsk: ask != nil,
                              reasons: Hiring.askReading(person: n, terms: terms, company: ctx.company, state: state, data: data).reasons, rounds: talk.round,
                              mood: talkMood(talk, rank: rank, person: n), termsProblem: hireTermsProblem(post: post, companyID: companyID, personID: personID, terms: terms))
    }

    internal static func rounded(_ v: Double, _ cur: Currency, _ about: Double) -> Double {
        let step = cur.stepSize(about: about)
        return step > 0 ? (v / step).rounded(.up) * step : v
    }

    /// The candidate opens the talk by naming what they expect, before any offer from you. Returns the figure (a full-week monthly wage). The talk keeps it
    /// (`theirAsk` is then non-nil); asking again returns the same figure for the same terms.
    @discardableResult
    mutating func hearTheirAsk(post: HirePost, companyID: Int?, chainID: Int? = nil, personID: Int, terms: Hiring.Terms = Hiring.Terms()) -> Double? {
        guard let n = state.people[personID], n.employerID == 0, let ctx = postContext(post, companyID: companyID, chainID: chainID) else { return nil }
        let f = hireTalkFactor(post, person: n, terms: terms, ctx: ctx)
        let amount = Self.rounded(Hiring.position(for: n, factor: f).opening, ctx.currency, ctx.about)
        let sig = Hiring.termsSignature(terms)
        update { s, _, _ in
            guard var p = s.people[personID] else { return }
            var t = Negotiation.State.resume(p, party: ctx.employer, week: s.week)
            t.asked = true; t.counter = amount; t.week = s.week; t.terms = sig
            t.store(in: &p)
            s.people[personID] = p
        }
        return amount
    }

    /// Make the offer: the one action of page 2. Routes to the hire door of the post; all of them answer through `Hiring.answer`.
    @discardableResult
    mutating func hireOffer(post: HirePost, companyID: Int?, chainID: Int? = nil, city: String? = nil, personID: Int, monthlyWage: Double, terms: Hiring.Terms = Hiring.Terms(),
                            profitBonus: Double = 0) -> HireOutcome {
        guard let n0 = state.people[personID], let ctx = postContext(post, companyID: companyID, chainID: chainID) else { return .refused }
        if n0.employerID != 0 { return .taken }
        if case .worker = post, let id = companyID, let co = state.company(id), let why = Workplaces.hireBlock(co, data: data) { return .termsRefused(why) }
        if let why = hireTermsProblem(post: post, companyID: companyID, personID: personID, terms: terms) { return .termsRefused(why) }
        let tf = hireTalkFactor(post, person: n0, terms: terms, ctx: ctx)
        let sig = Hiring.termsSignature(terms)
        var outcome = HireOutcome.refused
        update { s, d, _ in
            func done(_ okay: Bool) -> Bool { okay }
            func counter(_ c: Negotiation.Counter) -> HireOutcome { .countered(amount: c.amount, isFinal: c.isFinal) }
            if case .worker = post {
                guard let id = companyID else { return }
                switch Hiring.hire(personID, into: id, monthlyWage: monthlyWage, state: &s, data: d, terms: terms) {
                case .ok: outcome = .hired
                case .taken: outcome = .taken
                case .refused: outcome = .refused
                case .countered(let c): outcome = counter(c)
                case .walkedAway: outcome = .walkedAway
                case .planRefused: outcome = .termsRefused("\((n0.name.split(separator: " ").first.map(String.init) ?? n0.name)) will not take the job on these terms.")
                }
            } else {
                // The post's own door, with the company-and-package reading of the ask carried on the person for the duration of the call.
                if var p = s.people[personID] { p.set("tf", tf); s.people[personID] = p }
                switch post {
                case .manager:
                    switch ManagerModel.hire(&s, personID: personID, companyID: companyID ?? 0, monthlyWage: monthlyWage, profitBonus: profitBonus, data: d) {
                    case .ok: outcome = .hired
                    case .taken: outcome = .taken
                    case .refused: outcome = .refused
                    case .needsPremises: outcome = .blocked("This business needs premises before it can have a manager.")
                    case .countered(let c): outcome = counter(c)
                    case .walkedAway: outcome = .walkedAway
                    }
                case .assistant, .team, .executive:
                    let r: ManagerModel.OfferResult
                    switch post {
                    case .assistant: r = ManagerModel.hireAssistant(&s, personID: personID, companyID: companyID ?? 0, monthlyWage: monthlyWage, data: d)
                    case .team(let key): r = ManagerModel.hireTeam(&s, companyID: companyID ?? 0, key: key, personID: personID, monthlyWage: monthlyWage, data: d)
                    case .executive(let level): r = ManagerModel.hireExecutive(&s, level: level, personID: personID, monthlyWage: monthlyWage, chainID: chainID, city: city, data: d)
                    default: r = .refused
                    }
                    switch r {
                    case .ok: outcome = .hired
                    case .refused: outcome = .refused
                    case .taken: outcome = .taken
                    case .countered(let c): outcome = counter(c)
                    case .walkedAway: outcome = .walkedAway
                    }
                case .office(let role):
                    switch Headquarters.hire(&s, role: role, personID: personID, monthlyWage: monthlyWage, data: d) {
                    case .ok: outcome = .hired
                    case .refuse: outcome = .refused
                    case .taken: outcome = .taken
                    case .blocked: outcome = .blocked("The main office has no room for this post.")
                    case .countered(let c): outcome = counter(c)
                    case .walkedAway: outcome = .walkedAway
                    }
                case .analyst:
                    switch MarketMap.hireDataAnalyst(&s, personID: personID, monthlyWage: monthlyWage, data: d) {
                    case .ok: outcome = .hired
                    case .refused: outcome = .refused
                    case .taken: outcome = .taken
                    case .countered(let c): outcome = counter(c)
                    case .walkedAway: outcome = .walkedAway
                    default: outcome = .blocked("The head office already has a data analyst.")
                    }
                default: break
                }
                if var p = s.people[personID] { p.raw.removeValue(forKey: "tf"); s.people[personID] = p }
            }
            guard var p = s.people[personID] else { return }
            switch outcome {
            case .hired:
                if !terms.expectations.isEmpty { p.set("xp", .array(terms.expectations.map { .string($0) })); s.people[personID] = p }
                if case .worker = post {} else {
                    for dr in terms.promises { StaffPromises.make(&s, companyID: companyID ?? 0, personID: personID, draft: dr) }
                }
            case .countered:
                // the standing figure belongs to these terms
                var t = Negotiation.State.resume(p, party: ctx.employer, week: s.week)
                t.terms = sig; t.store(in: &p); s.people[personID] = p
            default: break
            }
        }
        return outcome
    }
}
