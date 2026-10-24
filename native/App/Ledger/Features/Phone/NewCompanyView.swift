import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Simulation

/// Choose a trade, see the whole start-up cost, then decide.
struct NewCompanyView: View {
    @EnvironmentObject var store: GameStore
    @State private var search = ""
    @State private var showEverything = false
    @State private var rows: [TradeAffordability] = []

    var body: some View {
        if let e = store.engine {
            let cur = e.homeCurrency
            let searching = !search.isEmpty
            // Nothing is blocked: by default the list leads with what you can fund now; searching or "Show everything" lists every trade.
            let matching = rows.filter { r in
                guard let t = e.data.catalog[r.tradeID] else { return false }
                return !searching || t.name.localizedCaseInsensitiveContains(search) || t.category.localizedCaseInsensitiveContains(search)
            }
            let list = (showEverything || searching) ? matching : matching.filter { $0.isFunded }
            let hidden = matching.count - list.count
            ScrollView {
                Card {
                    LazyVStack(spacing: Theme.Space.m) {
                        if search.isEmpty {
                            NavigationLink { NewHoldingView() } label: {
                                ListRow(symbol: TradeSymbol.of(family: "hold"), tint: Theme.gold, title: "Holding company", subtitle: "Owns your other companies; dividends into it are taxed far lower", chevron: true).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            NavigationLink { FranchisesView() } label: {
                                ListRow(symbol: "storefront", tint: Theme.gold, title: "Join a franchise", subtitle: "A known brand, their rules and a fee", chevron: true).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if e.state.companies.contains(where: { $0.status == .open && $0.type != "hold" }) {
                                NavigationLink { ExpandAbroadView() } label: {
                                    ListRow(symbol: "globe", tint: Theme.gold, title: "Expand abroad", subtitle: "A subsidiary of one of your companies in another country", chevron: true).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                            NavigationLink { ClubMarketView() } label: {
                                ListRow(symbol: TradeSymbol.of(family: "club"), tint: Theme.gold, title: "Football club", subtitle: "Buy a club in a top league, or found one", chevron: true).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        if !searching {
                            Text("You have \(cur.display(Payments.liquid(e.state))) available (account and savings). Costs are the full start-up estimate; nothing is locked.")
                                .font(.caption).foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, alignment: .leading)
                            Toggle("Show everything", isOn: $showEverything).tint(Theme.gold)
                        }
                        if list.isEmpty && !rows.isEmpty {
                            Text(searching ? "No trade matches that search." : "No trade is fully funded by what you have. Turn on Show everything to see what each one needs.")
                                .font(.caption).foregroundStyle(Theme.ivoryFaint).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(list) { r in
                            if let t = e.data.catalog[r.tradeID] {
                                NavigationLink {
                                    TradeDetailView(tradeID: t.id)
                                } label: {
                                    ListRow(symbol: TradeSymbol.of(family: t.family), tint: r.blocked == nil ? Theme.gold : Theme.ivoryFaint,
                                            title: t.name, subtitle: subtitle(r, t, cur), chevron: true)
                                        .opacity(r.blocked == nil ? 1 : 0.6)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                        if hidden > 0 {
                            Button("\(hidden) more \(hidden == 1 ? "trade needs" : "trades need") more money than you have: show everything") { showEverything = true }
                                .font(.caption).foregroundStyle(Theme.gold)
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("Choose a trade")
            .searchable(text: $search)
            .task(id: e.state.player.cityID + "|\(Int(Payments.liquid(e.state)))") { rows = e.tradeAffordability() }
        }
    }

    /// Cost and shortfall come from the engine's estimate; a ban or "later update" is shown instead of a cost.
    private func subtitle(_ r: TradeAffordability, _ t: Trade, _ cur: Currency) -> String {
        if let why = r.blocked { return why }
        guard let cost = r.cost else { return t.blurb }
        if r.shortfall > 0 { return "\(cur.display(cost)) to start · \(cur.tidyShort(r.shortfall)) short · \(t.blurb)" }
        return "\(cur.display(cost)) to start · \(t.blurb)"
    }
}
