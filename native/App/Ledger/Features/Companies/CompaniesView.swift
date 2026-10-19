import SwiftUI
import GameCore
import Simulation

struct CompaniesView: View {
    @EnvironmentObject var store: GameStore
    @State private var path: [Int] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let e = store.engine {
                    let cos = e.state.companies.filter { $0.type != "hold" }
                    ScrollView {
                        LazyVStack(spacing: Theme.Space.m) {
                            if cos.isEmpty {
                                Card {
                                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                                        Text("No companies yet").font(.heading)
                                        Text("Pick a trade, see the full start-up cost, then decide.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                                        Button("Choose a trade") { store.go(.newCompany) }.buttonStyle(GoldButtonStyle())
                                    }
                                }
                            }
                            ForEach(cos) { co in
                                NavigationLink(value: co.id) { CompanyRow(engine: e, company: co) }.buttonStyle(.plain)
                            }
                        }
                        .padding(Theme.Space.l)
                        .frame(maxWidth: 760).frame(maxWidth: .infinity)
                    }
                }
            }
            .ledgerBackground()
            .navigationTitle("Companies")
            .navigationDestination(for: Int.self) { id in CompanyDetailView(companyID: id) }
            .toolbar { ToolbarItem(placement: .primaryAction) { Button { store.go(.newCompany) } label: { Image(systemName: "plus") } } }
            .onAppear { openRequested() }
            .onChange(of: store.openCompanyID) { _, _ in openRequested() }
        }
    }

    private func openRequested() {
        if let id = store.openCompanyID { path = [id]; store.openCompanyID = nil }
    }
}

struct StatusChip: View {
    var company: Company
    var body: some View {
        switch company.status {
        case .setup: Chip(text: "Setting up", tint: Theme.caution)
        case .open: Chip(text: company.cash < 0 ? "Out of cash" : "Open", tint: company.cash < 0 ? Theme.loss : Theme.gain)
        case .closed: Chip(text: "Closed", tint: Theme.ivoryMuted)
        case .sold: Chip(text: "Sold", tint: Theme.ivoryMuted)
        case .bust: Chip(text: "Bankrupt", tint: Theme.loss)
        default: Chip(text: company.status.rawValue.capitalized)
        }
    }
}

struct CompanyRow: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    var body: some View {
        let month = Books.profit(company.books.month)
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .center, spacing: Theme.Space.m) {
                    IconBadge(symbol: "building.2.fill", tint: company.cash < 0 ? Theme.loss : Theme.gold, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(company.name).font(.heading).foregroundStyle(Theme.ivory)
                        Text("\(engine.tradeName(company)) · \(engine.cityName(company))").font(.caption).foregroundStyle(Theme.ivoryMuted)
                    }
                    Spacer()
                    StatusChip(company: company)
                }
                MiniBars(values: engine.monthlyProfitSeries(company)).frame(height: 30)
                HStack {
                    Stat(label: "Cash", value: store.short(company.cash, in: company), tint: company.cash < 0 ? Theme.loss : Theme.ivory)
                    Spacer()
                    Stat(label: "Last week", value: store.short(company.lastWeekRevenue, in: company))
                    Spacer()
                    Stat(label: "Month so far", value: (month >= 0 ? "+" : "−") + store.short(abs(month), in: company), tint: Theme.change(month))
                }
            }
        }
    }
}
