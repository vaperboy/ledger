import SwiftUI
import GameCore
import Businesses
import Simulation

struct DataAnalystCard: View {
    @EnvironmentObject var store: GameStore
    @State private var candidates: [Person] = []
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine {
            CardSection("Data analyst") {
                VStack(alignment: .leading, spacing: 8) {
                    if e.hasDataAnalyst {
                        Text("Hired").textStyle(.caption)
                        HStack {
                            Button("Report on all companies") {
                                let r = store.act { $0.orderAnalystReport(companyID: nil) }
                                if case .refused(let why)? = r { store.show(why, tone: "warn") } else { store.show("Report sent to your inbox."); Haptics.success() }
                            }.buttonStyle(QuietButtonStyle(tint: Theme.gold))
                            Button("Let them go") {
                                pending = PendingAction(title: "Let your data analyst go?", message: "Market shares and forecasts go back to guesses until you hire another. Their desk in the main office is freed.", button: "Let go", destructive: true) {
                                    if store.act({ $0.fireDataAnalyst() }) == true { Haptics.warning(); store.show("Your data analyst has left.", tone: "n") }
                                    else { store.show("You have no data analyst.", tone: "warn") }
                                }
                            }.buttonStyle(QuietButtonStyle(tint: Theme.loss))
                        }
                    } else {
                        Text("Not hired: shares are your guess").textStyle(.caption)
                        if candidates.isEmpty {
                            Button("Find a data analyst") { candidates = store.act { $0.dataAnalystCandidates() } ?? [] }.buttonStyle(QuietButtonStyle(tint: Theme.gold))
                        }
                        if !candidates.isEmpty {
                            CandidateHireList(people: candidates, emptyText: "") { p in
                                let request = HireRequest(post: .analyst, companyID: nil, personID: p.id, roleTitle: "Data analyst", onHired: { candidates = [] })
                                CandidateHireRow(person: p, currency: e.homeCurrency, subtitle: CandidateClaims.line(e, p), market: e.goingRate(for: .analyst), request: request)
                            }
                        }
                    }
                }
            }
            .confirmAction($pending)
        }
    }
}
