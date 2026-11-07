import SwiftUI
import GameCore
import Finance
import Countries
import Businesses
import Simulation

/// One open post on an entity's Management tab. It says what the post is, who hires into it (the boss above, with the authority the owner gave
/// them: `HierarchyHiring`) and gives the owner their own way in: pay for a search and talk terms with a candidate in the one two-page hiring flow.
/// The owner can always hire into any post, whatever the boss above is doing; the boss's own hires and requests reach the Inbox.
struct OpenPostRow: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var engine: GameEngine
    var vacancy: TeamOverview.Vacancy
    var first: Bool
    @State private var candidates: [Int] = []
    @State private var pending: PendingAction?

    var body: some View {
        let cur: Currency = engine.homeCurrency
        let route: VacancyRoute? = engine.vacancyRoute(vacancy)
        let hirerLine: String = engine.vacancyHirerLine(vacancy)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            header
            if !hirerLine.isEmpty {
                Text(hirerLine.tidyText).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            }
            if let route {
                actions(route, cur)
            }
        }
        .padding(.vertical, Theme.Space.m)
        .overlay(alignment: .top) { if !first { Hairline() } }
        .confirmAction($pending)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(vacancy.title.tidyText).textStyle(.headline).lineLimit(1)
                Text(vacancy.detail.tidyText).textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.s)
            AcctPill(text: vacancy.needed ? "Needed now" : "Open", tone: vacancy.needed ? .bad : .neutral)
        }
    }

    @ViewBuilder private func actions(_ route: VacancyRoute, _ cur: Currency) -> some View {
        let fee: String = cur.tidyShort(route.searchFee)
        let people: [Person] = candidates.compactMap { (id: Int) -> Person? in engine.state.people[id] }.filter { (p: Person) -> Bool in p.employerID == 0 }
        if candidates.isEmpty {
            Button((vacancy.hirerName == nil ? "Find candidates" : "Search yourself") + " · \(fee)…") { Haptics.tap(); askToSearch(route, cur) }
                .buttonStyle(TertiaryButtonStyle(size: .compact)).padding(.leading, -Theme.Space.s)
        } else {
            CandidateHireList(people: people, emptyText: "Everyone on the list has taken another job. Search again.") { (p: Person) in
                let request = HireRequest(post: route.post, companyID: route.companyID, chainID: route.chainID, city: route.city, personID: p.id, roleTitle: route.roleTitle,
                                          onHired: { candidates = [] })
                CandidateHireRow(person: p, currency: cur, subtitle: CandidateClaims.line(engine, p),
                                 market: engine.goingRate(for: route.post, companyID: route.companyID), request: request)
            }
        }
    }

    private func askToSearch(_ route: VacancyRoute, _ cur: Currency) {
        let fee: String = cur.tidyShort(route.searchFee)
        let v: TeamOverview.Vacancy = vacancy
        pending = PendingAction(title: "Start the search?", message: "Candidates for the post of \(route.roleTitle.lowercased()). The list stays until someone is hired.",
                                button: "Pay \(fee) and search", amount: route.searchFee, currency: cur, risk: "None may suit, and the fee is not refunded.", tone: .info, icon: "magnifyingglass") {
            if let list = store.act({ $0.searchVacancy(v) }) ?? nil, !list.isEmpty {
                candidates = list.map { (p: Person) -> Int in p.id }
                Haptics.success()
                store.show("\(list.count) \(list.count == 1 ? "candidate" : "candidates") found. Search paid: \(fee).", tone: "good")
            } else {
                Haptics.warning()
                store.show("The search found no one, or the cash is not there for \(fee).", tone: "warn")
            }
        }
    }
}
