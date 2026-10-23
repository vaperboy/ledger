import SwiftUI
import GameCore
import Businesses
import Simulation

/// The Group tab: ownership and structure (what needs you, holdings, chains, franchises, group management, main office, boards) and, as a second section,
/// the group's money (finance, bank, investments, taxes, costs, reports) which is `FinanceView` unchanged.
struct GroupView: View {
    enum Part: String, CaseIterable, Hashable { case structure = "Structure", money = "Money" }
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
            .companyRouteDestinations()
            .phoneToolbar()
            .onAppear { takeMoneyRequest() }
            .onChange(of: store.moneySection) { _, _ in takeMoneyRequest() }
        }
    }

    /// A deep link to a Money section (bank, invest, taxes, reports) switches to Money; `FinanceView` then picks the section.
    private func takeMoneyRequest() {
        if store.moneySection != nil { part = .money }
    }

    /// Decisions first, then the structure (holdings, chains, franchises), then the people and bodies above the companies:
    /// group management, the main office, the boards. Company figures and comparisons stay under Company.
    @ViewBuilder private func structure(_ e: GameEngine) -> some View {
        let live = e.state.companies.filter { $0.type != "hold" && $0.status.isLive }
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                GroupAttention(engine: e)
                GroupStructureOverview(engine: e)
                if live.count >= 2 { ExecutivePosts(engine: e, chainID: nil) }
                else if !live.isEmpty {
                    LedgerSection("Group management") {
                        Text("A managing director for the whole group becomes possible once you own two running companies.").font(.caption).foregroundStyle(Theme.ivoryFaint)
                    }
                }
                if !live.isEmpty { HeadOfficeSection(engine: e) }
                BoardsGroupSection(engine: e) { moneyTo(.invest) }
                if live.contains(where: { $0.status == .open }) {
                    LedgerSection("Market") {
                        NavigationLink(value: CompanyRoute.market) {
                            GroupLinkRow(title: "Market, reviews and rivals", sub: "Rival groups and how your trades compare.")
                        }.buttonStyle(.plain)
                    }
                }
                HostingSection(engine: e)
            }
            .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
            .frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private func moneyTo(_ s: MoneySection) { store.moneySection = s }
}
