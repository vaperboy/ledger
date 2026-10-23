import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// One person looking for work: what the CV says, what the engine lets you find out (a paid trial week), and the ways to hire them.
/// Worker candidates carry no reference-check mechanic in the engine, so none is offered here.
struct CandidateSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var engine: GameEngine
    var company: Company
    var personID: Int
    var onHired: () -> Void
    @State private var offer = 1.0

    var body: some View {
        let live = store.engine ?? engine
        let cur = live.currency(for: company)
        NavigationStack {
            ScrollView {
                if let p = live.state.people[personID] {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        Text(p.name).font(.serifTitle(24)).foregroundStyle(Theme.ivory)
                        KeyFigures(items: [
                            .init(label: "Says", value: StaffProfile.band(p.claimedSkill), sub: "skill \(Int(p.claimedSkill.rounded()))"),
                            .init(label: "Age", value: "\(p.age)"),
                            .init(label: "Asks", value: cur.tidyShort(p.askingMonthlyWage), sub: "a month"),
                        ])
                        if !p.value("trialRes").isNull {
                            Text("After a trial week their work looked like skill \(Int(p.num("trialRes").rounded())), give or take a few points.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                        } else {
                            Text("The CV is what they claim. A paid trial week (\(cur.tidyShort(p.askingMonthlyWage / 4))) shows roughly how good they really are.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                            Button("Paid trial week") { trial() }.buttonStyle(QuietButtonStyle())
                        }
                        LedgerSection("Offer") {
                            VStack(alignment: .leading, spacing: Theme.Space.s) {
                                SectionTabs(items: [0.9, 1.0, 1.1], title: { $0 == 1.0 ? "Their ask" : $0 < 1 ? "10% under" : "10% over" }, selection: $offer).padding(.horizontal, -Theme.Space.margin)
                                Text("Offering \(cur.display(p.askingMonthlyWage * offer)) a month. Below their ask they may refuse; the minimum wage applies whatever you offer.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                                Button("Hire full time") { hire(p, Hiring.Terms()) }.buttonStyle(GoldButtonStyle())
                                HStack {
                                    Button("Part time, 20 h") { hire(p, Hiring.Terms(hours: 20)) }.buttonStyle(QuietButtonStyle())
                                    Button("Seasonal") { hire(p, Hiring.Terms(hours: 25, seasonMonths: busy(live))) }.buttonStyle(QuietButtonStyle())
                                }
                                if p.role == "estate" { Button("Full time, own car") { hire(p, Hiring.Terms(ownCar: true)) }.buttonStyle(QuietButtonStyle()) }
                            }
                        }
                    }
                    .padding(Theme.Space.margin)
                } else {
                    Text("They took another job.").foregroundStyle(Theme.ivoryMuted).padding(Theme.Space.margin)
                }
            }
            .ledgerBackground()
            .navigationTitle("Candidate").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func busy(_ e: GameEngine) -> [Int] { let m = e.busyMonths(companyID: company.id); return m.isEmpty ? [6, 7, 8] : m }

    private func trial() {
        if let seen = store.act({ $0.startTrialWeek(personID: personID, companyID: company.id) }) ?? nil {
            Haptics.success(); store.show("After a week their work looks like \(Int(seen)) skill.", tone: "n")
        } else { Haptics.warning(); store.show("Could not arrange a trial week: the company needs the cash.", tone: "warn") }
    }

    private func hire(_ p: Person, _ t: Hiring.Terms) {
        switch store.act({ $0.hire(personID: p.id, companyID: company.id, monthlyWage: p.askingMonthlyWage * offer, terms: t) }) {
        case .ok?: Haptics.success(); store.show("\(p.name) has joined.", tone: "good"); onHired(); dismiss()
        case .taken?: store.show("They took another job.", tone: "warn"); onHired(); dismiss()
        default: Haptics.warning(); store.show("\(p.name) turned that offer down. Try a higher one.", tone: "warn")
        }
    }
}
