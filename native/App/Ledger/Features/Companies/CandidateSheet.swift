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

    enum Kind: String, Hashable {
        case full = "Full time", part = "Part time, 20 h", seasonal = "Seasonal", ownCar = "Own car"
    }

    private var kinds: [Kind] { engine.offersOwnCar(companyID: company.id, role: person.role) ? [.full, .part, .seasonal, .ownCar] : [.full, .part, .seasonal] }

    private var terms: Hiring.Terms {
        switch kind {
        case .full: return Hiring.Terms()
        case .part: return Hiring.Terms(hours: 20)
        case .seasonal: return Hiring.Terms(hours: 25, seasonMonths: busy)
        case .ownCar: return Hiring.Terms(ownCar: true)
        }
    }

    private var busy: [Int] { let m = engine.busyMonths(companyID: company.id); return m.isEmpty ? [6, 7, 8] : m }

    var body: some View {
        let cur = engine.currency(for: company)
        let tried = !person.value("trialRes").isNull
        let market = engine.marketWage(role: person.role, companyID: company.id)
        CandidateHireRow(person: person, currency: cur,
                         subtitle: "Says \(StaffProfile.band(person.claimedSkill).lowercased()) (\(Int(person.claimedSkill.rounded()))) · age \(person.age)",
                         market: market, factors: [0.9, 1.0, 1.15, 1.3], offer: { wage in hire(wage) }) {
            VStack(alignment: .leading, spacing: 6) {
                SectionTabs(items: kinds, title: { $0.rawValue }, selection: $kind)
                if tried {
                    Text("After a trial week their work looked like skill \(Int(person.num("trialRes").rounded())), give or take a few points.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted)
                } else {
                    Button("Paid trial week · \(cur.tidyShort(market / 4))") { trial() }.buttonStyle(QuietButtonStyle())
                }
            }
        }
    }

    private func trial() {
        if let seen = store.act({ $0.startTrialWeek(personID: person.id, companyID: company.id) }) ?? nil {
            Haptics.success(); store.show("After a week their work looks like \(Int(seen)) skill.", tone: "n")
        } else { Haptics.warning(); store.show("Could not arrange a trial week: the company needs the cash.", tone: "warn") }
    }

    private func hire(_ wage: Double) -> HireFeedback {
        let t = terms, pid = person.id, cid = company.id
        let result: Hiring.HireResult? = store.act { $0.hire(personID: pid, companyID: cid, monthlyWage: wage, terms: t) }
        let fb = HireFeedback.from(result, name: person.name)
        store.show(fb.text, tone: fb.isHired ? "good" : "warn")
        return fb
    }
}
