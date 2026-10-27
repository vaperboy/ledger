import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The contract a worker is offered, as the player has set it: full time, part time, seasonal or with their own car; for a seller the pay plan
/// (salary, salary and commission, commission only) and the commission share; and the length of the contract (permanent or a fixed term).
/// `HireTermsEditor` edits it; the Negotiation screen sends it with every offer. The engine decides what each choice means (`GameEngine.hire(terms:)`).
struct HireTermsDraft: Equatable {
    enum Kind: String, Hashable { case full = "Full time", part = "Part time, 20 h", seasonal = "Seasonal", ownCar = "Own car" }
    /// The pay plan of a full-time seller (the data decides which jobs sell on commission in this trade).
    enum Plan: String, Hashable, CaseIterable {
        case salary = "Salary", mix = "Salary and commission", com = "Commission only"
        var id: String? { self == .salary ? nil : self == .mix ? "mix" : "com" }
    }

    var kind = Kind.full
    var plan = Plan.salary
    var rate = 0.0
    /// 0 = permanent (an open-ended contract), else a fixed term in weeks.
    var term = 0

    func terms(busyMonths: [Int]) -> Hiring.Terms {
        let months: [Int] = busyMonths.isEmpty ? [6, 7, 8] : busyMonths
        let planID: String? = plan.id
        let share: Double = planID == nil ? 0 : rate
        switch kind {
        case .full: return Hiring.Terms(payPlan: planID, commissionRate: share, fixedTermWeeks: term)
        case .part: return Hiring.Terms(hours: 20)
        case .seasonal: return Hiring.Terms(hours: 25, seasonMonths: months)
        case .ownCar: return Hiring.Terms(ownCar: true, payPlan: planID, commissionRate: share, fixedTermWeeks: term)
        }
    }

    /// Commission only has no base wage: the cost of the hire is the sales share, which the engine cannot price in advance.
    var isCommissionOnly: Bool { plan == .com && (kind == .full || kind == .ownCar) }

    /// One line for the confirmation: what is being offered besides the pay.
    var summary: String {
        var parts: [String] = [kind.rawValue.lowercased()]
        if kind == .full || kind == .ownCar {
            if plan != .salary { parts.append(plan.rawValue.lowercased()) }
            parts.append(term == 0 ? "permanent contract" : "fixed term of \(term) weeks")
        }
        return parts.joined(separator: ", ")
    }
}

/// The terms of a worker hire (part time, seasonal, own car, commission, fixed term or permanent), in the new look: used under "Contract terms" on the
/// Negotiation screen. No game rule lives here; the engine answers an offer with these terms.
struct HireTermsEditor: View {
    var engine: GameEngine
    var company: Company
    var role: String
    @Binding var draft: HireTermsDraft

    private var kinds: [HireTermsDraft.Kind] {
        engine.offersOwnCar(companyID: company.id, role: role) ? [.full, .part, .seasonal, .ownCar] : [.full, .part, .seasonal]
    }
    private var sells: Bool { PayPlans.eligible(role: role, trade: company.type, salesRoles: engine.salesRoles) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SegmentedChoice(items: kinds, title: { $0.rawValue }, selection: $draft.kind)
            if draft.kind == .full || draft.kind == .ownCar { contract }
        }
    }

    @ViewBuilder private var contract: some View {
        VStack(alignment: .leading, spacing: 6) {
            if sells {
                SegmentedChoice(items: HireTermsDraft.Plan.allCases, title: { $0.rawValue }, selection: $draft.plan)
                if draft.plan != .salary {
                    Text("Commission").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                    WrapRow {
                        ForEach([0.0] + PayPlans.rateSteps, id: \.self) { r in
                            let on: Bool = abs(draft.rate - r) < 0.0001
                            Button(r == 0 ? "Usual" : "\(Int((r * 100).rounded()))%") { draft.rate = r }
                                .buttonStyle(QuietButtonStyle(tint: on ? Theme.gold : Theme.ivoryMuted))
                        }
                    }
                    let planNote: String = draft.plan == .com
                        ? "No base pay at all: what you offer is the pay they expect to earn. Commission is paid on the sales credited to them. Someone who wants security may refuse."
                        : "What you offer is the base salary; commission on their sales comes on top."
                    Text(planNote).font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Contract").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            WrapRow {
                Button("Permanent") { draft.term = 0 }.buttonStyle(QuietButtonStyle(tint: draft.term == 0 ? Theme.gold : Theme.ivoryMuted))
                ForEach(FixedTerm.termChoices, id: \.self) { w in
                    Button("\(w) wk") { draft.term = w }.buttonStyle(QuietButtonStyle(tint: draft.term == w ? Theme.gold : Theme.ivoryMuted))
                }
            }
            if draft.term > 0 {
                Text("Fixed term: it ends on its date unless you renew it. What ending it costs follows the country's labour rules.")
                    .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
