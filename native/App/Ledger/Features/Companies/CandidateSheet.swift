import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// A worker candidate in the shared hiring list: the shared `CandidateHireRow` (name, going rate, offers, answer) with the worker-only controls
/// in its `extra` slot: the terms (full time, part time, seasonal, own car) and a paid trial week. The engine call is `GameEngine.hire(terms:)`.
/// Worker candidates carry no reference-check mechanic in the engine, so none is offered here.
struct WorkerHireRow: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    var person: Person
    @State private var kind = Kind.full
    @State private var plan = Plan.salary
    @State private var rate = 0.0
    @State private var term = 0

    enum Kind: String, Hashable {
        case full = "Full time", part = "Part time, 20 h", seasonal = "Seasonal", ownCar = "Own car"
    }

    /// The pay plan of a full-time seller (the data decides which jobs sell on commission in this trade).
    enum Plan: String, Hashable, CaseIterable {
        case salary = "Salary", mix = "Salary and commission", com = "Commission only"
        var id: String? { self == .salary ? nil : self == .mix ? "mix" : "com" }
    }
    private var sells: Bool { PayPlans.eligible(role: person.role, trade: company.type, salesRoles: engine.salesRoles) }

    private var kinds: [Kind] { engine.offersOwnCar(companyID: company.id, role: person.role) ? [.full, .part, .seasonal, .ownCar] : [.full, .part, .seasonal] }

    private var terms: Hiring.Terms {
        switch kind {
        case .full: return Hiring.Terms(payPlan: plan.id, commissionRate: plan.id == nil ? 0 : rate, fixedTermWeeks: term)
        case .part: return Hiring.Terms(hours: 20)
        case .seasonal: return Hiring.Terms(hours: 25, seasonMonths: busy)
        case .ownCar: return Hiring.Terms(ownCar: true, payPlan: plan.id, commissionRate: plan.id == nil ? 0 : rate, fixedTermWeeks: term)
        }
    }

    private var busy: [Int] { let m = engine.busyMonths(companyID: company.id); return m.isEmpty ? [6, 7, 8] : m }

    var body: some View {
        let cur = engine.currency(for: company)
        let tried = !person.value("trialRes").isNull
        let market = engine.marketWage(role: person.role, companyID: company.id)
        let claims = engine.claimedExperienceYears(personID: person.id).map { " · Claims \(Int($0.rounded())) \(Int($0.rounded()) == 1 ? "year" : "years")" } ?? ""
        CandidateHireRow(person: person, currency: cur,
                         subtitle: "Says \(StaffProfile.band(person.claimedSkill).lowercased()) (\(Int(person.claimedSkill.rounded()))) · age \(person.age)" + claims,
                         market: market, factors: [0.9, 1.0, 1.15, 1.3], offer: { wage in hire(wage) }) {
            VStack(alignment: .leading, spacing: 6) {
                SegmentedChoice(items: kinds, title: { $0.rawValue }, selection: $kind)
                if kind == .full || kind == .ownCar { contractTerms(cur) }
                if tried {
                    Text("After a trial week their work looked like skill \(Int(person.num("trialRes").rounded())), give or take a few points.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted)
                } else {
                    Button("Paid trial week · \(cur.tidyShort(market / 4))") { trial() }.buttonStyle(QuietButtonStyle())
                }
            }
        }
    }

    /// Pay plan (for jobs that sell) and contract term: part of the offer.
    @ViewBuilder private func contractTerms(_ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if sells {
                SegmentedChoice(items: Plan.allCases, title: { $0.rawValue }, selection: $plan)
                if plan != .salary {
                    Text("Commission").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                    WrapRow {
                        ForEach([0.0] + PayPlans.rateSteps, id: \.self) { r in
                            Button(r == 0 ? "Usual" : "\(Int((r * 100).rounded()))%") { rate = r }.buttonStyle(QuietButtonStyle(tint: abs(rate - r) < 0.0001 ? Theme.gold : Theme.ivoryMuted))
                        }
                    }
                    Text(plan == .com ? "No base pay at all: what you offer is the pay they expect to earn. Commission is paid on the sales credited to them. Someone who wants security may refuse."
                         : "What you offer is the base salary; commission on their sales comes on top.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Contract").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            WrapRow {
                Button("Permanent") { term = 0 }.buttonStyle(QuietButtonStyle(tint: term == 0 ? Theme.gold : Theme.ivoryMuted))
                ForEach(FixedTerm.termChoices, id: \.self) { w in
                    Button("\(w) wk") { term = w }.buttonStyle(QuietButtonStyle(tint: term == w ? Theme.gold : Theme.ivoryMuted))
                }
            }
            if term > 0 { Text("Fixed term: it ends on its date unless you renew it. What ending it costs follows the country's labour rules.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func trial() {
        if let seen = store.act({ $0.startTrialWeek(personID: person.id, companyID: company.id) }) ?? nil {
            Haptics.success(); store.show("After a week their work looks like \(Int(seen)) skill.", tone: "n")
        } else { Haptics.warning(); store.show("Could not arrange a trial week: the company needs \(store.short(engine.marketWage(role: person.role, companyID: company.id) / 4, in: company)) in cash.", tone: "warn") }
    }

    private func hire(_ wage: Double) -> HireFeedback {
        let t = terms, pid = person.id, cid = company.id
        let result: Hiring.HireResult? = store.act { $0.hire(personID: pid, companyID: cid, monthlyWage: wage, terms: t) }
        let fb = HireFeedback.from(result, name: person.name)
        if !fb.isHired { Haptics.warning() }
        store.show(fb.text, tone: fb.isHired ? "good" : "warn")
        return fb
    }
}
