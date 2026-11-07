import SwiftUI
import GameCore
import Businesses
import Simulation

/// The Market app (Phone). One shared app for every business: the business selector is at the top, and a link from a company opens the
/// app with that company already chosen (`GameStore.openMarket(companyID:)`). "All markets" shows the group view (your share of each
/// market, your weight in the economy, the groups around you); a company shows where it stands and its named rivals. The share graph
/// is only drawn when an analyst measures the market (`MarketMap.Knowledge.Level.canDrawShareGraph`); otherwise the share is words.
/// Pricing is not here: it is a row under Sales.
struct MarketApp: View {
    @EnvironmentObject var store: GameStore
    /// The business shown; 0 = all markets.
    @State private var companyID = 0
    @State private var part: MarketPart = .overview

    var body: some View {
        Group {
            if let e = store.engine {
                page(e)
            } else {
                Color.clear
            }
        }
        .appScreen(title: "Market", subtitle: PhoneApp.market.subtitle)
        .onAppear { take() }
        .onChange(of: store.appRequest) { _, _ in take() }
    }

    private func page(_ e: GameEngine) -> some View {
        let companies: [Company] = Self.companies(e)
        let chosen: Company? = companies.first { $0.id == companyID }
        let header = VStack(alignment: .leading, spacing: Theme.Space.m) {
            selector(companies, chosen)
            SegmentedPill(items: MarketPart.allCases, title: { (p: MarketPart) -> String in p.rawValue }, selection: $part, badges: { (p: MarketPart) -> Bool in tabHasNew(e, p) })
        }
        .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.xs).padding(.bottom, Theme.Space.xs)
        .frame(maxWidth: 760).frame(maxWidth: .infinity)
        return VStack(spacing: 0) {
            header
            SegmentPager(items: MarketPart.allCases, selection: $part) { (p: MarketPart) in
                partPage(e, chosen, p)
            }
        }
        .accessibilityIdentifier("market-app")
    }

    /// A segment dot: News holds any new market event; Competitors the new ones about rivals.
    private func tabHasNew(_ e: GameEngine, _ p: MarketPart) -> Bool {
        let fresh: [MarketEvent] = e.marketEvents(limit: 30).filter { (m: MarketEvent) -> Bool in store.isNew(.market, "e\(m.id)") }
        if p == .news { return !fresh.isEmpty }
        if p == .competitors {
            if store.hasNew(.market, prefix: "r") { return true }
            return fresh.contains { (m: MarketEvent) -> Bool in m.kind == .competitorLaunch || m.kind == .competitorLostShare || m.kind == .priceResponse }
        }
        return false
    }

    /// Short segments fit one screen (compacted when needed); the long lists scroll.
    @ViewBuilder private func partPage(_ e: GameEngine, _ chosen: Company?, _ p: MarketPart) -> some View {
        if p == .overview || p == .research || p == .prices {
            FixedScreen(spacing: Theme.Space.m, top: Theme.Space.xs, overflowScrolls: true) { content(e, chosen, p) }
        } else {
            ScrollScreen(spacing: Theme.Space.m, top: Theme.Space.xs) { content(e, chosen, p) }
        }
    }

    /// The businesses that can be looked at: open ones that trade (a holding company has no market).
    static func companies(_ e: GameEngine) -> [Company] {
        e.state.companies.filter { $0.status == .open && $0.type != "hold" }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ chosen: Company?, _ p: MarketPart) -> some View {
        if let co = chosen {
            CompanyMarket(engine: e, company: co, part: p)
        } else {
            MarketView(part: p)
        }
    }

    private func selector(_ companies: [Company], _ chosen: Company?) -> some View {
        let current: String = chosen?.name ?? "All markets"
        return Menu {
            Button {
                companyID = 0
                Haptics.choose()
            } label: {
                if chosen == nil { Label("All markets", systemImage: "checkmark") } else { Text("All markets") }
            }
            ForEach(companies) { (co: Company) in
                Button {
                    companyID = co.id
                    Haptics.choose()
                } label: {
                    if co.id == chosen?.id { Label(co.name, systemImage: "checkmark") } else { Text(co.name) }
                }
            }
        } label: {
            BusinessPickerLabel(caption: "Market for", title: current)
        }
        .accessibilityLabel("Business: \(current)")
        .accessibilityIdentifier("market-business-picker")
    }

    /// A link from a company names the business to show; one that is gone (sold, closed) falls back to all markets.
    private func take() {
        let news: Bool = store.marketNewsPending
        store.marketNewsPending = false
        guard let id = store.takeMarketRequest() else { return }
        companyID = id
        if news { part = .news }
    }
}
