import SwiftUI
import GameCore
import Businesses
import Simulation

/// The Group tab: ownership and structure (holdings, chains and franchises, group management, the market) and, as a second section,
/// the group's money (finance, bank, investments, taxes, costs, reports) which is `FinanceView` unchanged.
struct GroupView: View {
    enum Part: String, CaseIterable, Hashable { case structure = "Holdings", money = "Money" }
    @EnvironmentObject var store: GameStore
    @State private var path: [CompanyRoute] = []
    @State private var part: Part = .structure

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                SectionTabs(items: Part.allCases, title: { $0.rawValue }, selection: $part).padding(.top, Theme.Space.s)
                if part == .money {
                    FinanceView()
                } else if let e = store.engine {
                    structure(e)
                }
            }
            .ledgerBackground()
            .navigationTitle("Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: CompanyRoute.self) { route in
                switch route {
                case .company(let id): CompanyDetailView(companyID: id)
                case .newCompany: NewCompanyView()
                case .market: MarketView()
                }
            }
            .phoneToolbar()
            .onAppear { takeMoneyRequest() }
            .onChange(of: store.moneySection) { _, _ in takeMoneyRequest() }
        }
    }

    /// A deep link to a Money section (bank, invest, taxes, reports) switches to Money; `FinanceView` then picks the section.
    private func takeMoneyRequest() {
        if store.moneySection != nil { part = .money }
    }

    @ViewBuilder private func structure(_ e: GameEngine) -> some View {
        let cos = e.state.companies.filter { $0.type != "hold" && $0.status != .sold }
        let health = cos.map { e.companyHealth($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if !cos.isEmpty {
                    GroupSummary(engine: e, rows: health, staff: cos.reduce(0) { $0 + $1.staff.count })
                }
                if cos.contains(where: { $0.status == .open }) {
                    NavigationLink(value: CompanyRoute.market) {
                        HStack {
                            Text("Market, reviews and rivals").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                        }.padding(.vertical, 6).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                HostingSection(engine: e)
                if cos.filter({ $0.status.isLive }).count >= 2 { ExecutivePosts(engine: e, chainID: nil) }
                if cos.contains(where: { $0.status.isLive }) { HeadOfficeSection(engine: e) }
                if !e.holdingCompanies.isEmpty {
                    LedgerSection("Holding companies") {
                        VStack(spacing: 0) {
                            ForEach(Array(e.holdingCompanies.enumerated()), id: \.element.id) { n, h in
                                if n > 0 { Hairline() }
                                NavigationLink(value: CompanyRoute.company(h.id)) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(h.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).lineLimit(1)
                                            Text("\(e.state.companies.filter { $0.holdingID == h.id && $0.status.isLive }.count) companies under it").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                                        }
                                        Spacer()
                                        Text(store.short(Valuation.companyValue(h, state: e.state, trades: e.data.catalog), in: h)).font(.system(size: 13.5).monospacedDigit())
                                    }.padding(.vertical, 9).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                ChainsGroupSection(engine: e)
                BoardsGroupSection(engine: e) { moneyTo(.invest) }
            }
            .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
            .frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private func moneyTo(_ s: MoneySection) { store.moneySection = s }
}
