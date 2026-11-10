import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct MarketCompaniesPage: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var open: (MarketRoute) -> Void

    var body: some View {
        if let e = store.engine {
            let lines: [MarketUI.CompanyLine] = store.memo("mk.lines") { MarketData.companyLines($0) } ?? []
            ScrollScreen(spacing: Theme.Space.m, top: Theme.Space.s) {
                hero(lines)
                if lines.isEmpty {
                    EmptyState(glyph: Glyph.market, title: "No market yet")
                } else {
                    MarketLabel(title: "Your companies")
                    VStack(spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { (pair: (offset: Int, element: MarketUI.CompanyLine)) in
                            if pair.offset > 0 { Hairline() }
                            row(pair.element)
                        }
                    }
                }
                MarketLabel(title: "Analyst")
                LedgerRow(leading: .glyph(Glyph.person), leadingTint: P.inkSoft, title: "Data analyst",
                          value: e.hasDataAnalyst ? "Hired" : "Hire", identifier: "market-data-analyst", action: { open(.dataAnalyst) })
            }
        }
    }

    private func hero(_ lines: [MarketUI.CompanyLine]) -> some View {
        let leading: Int = lines.filter { (l: MarketUI.CompanyLine) -> Bool in l.rank == 1 }.count
        let measured: Int = lines.filter { (l: MarketUI.CompanyLine) -> Bool in l.level != .feeling }.count
        let value: String = lines.isEmpty ? "None" : (measured > 0 ? "Leading \(leading) of \(lines.count)" : lines.count.countText("market"))
        let context: String = measured == 0 ? "Share unknown" : "\(measured) of \(lines.count) measured"
        return MarketHero(label: "Your markets", value: value, context: lines.isEmpty ? "" : context, identifier: "market-companies-hero")
    }

    private func row(_ l: MarketUI.CompanyLine) -> some View {
        let rank: String = l.rank.map { (r: Int) -> String in "#\(r) of \(l.players)" } ?? "\(l.players) in the market"
        var notes: [String] = []
        if let g = l.priceGap { notes.append(abs(g) < 0.03 ? "price as market" : "price " + MarketFormat.percent(g, decimals: 0)) }
        if let r = l.ratingGap { notes.append(String(format: "\u{2605} %+.1f", r)) }
        let arrow: String = l.trend.map { (t: Double) -> String in t > 0.05 ? "\u{2191} " : (t < -0.05 ? "\u{2193} " : "") } ?? ""
        let tint: Color? = l.trend.map { (t: Double) -> Color in P.change(t) }
        return LedgerRow(leading: .thumb(ThumbSpec(kind: .trade, key: store.engine?.state.company(l.id)?.type ?? "", glyph: Glyph.home)),
                         title: l.name, subtitle: "\(l.trade) \u{00B7} \(l.city) \u{00B7} \(rank)", value: arrow + l.shareText, valueTint: tint,
                         valueNote: notes.joined(separator: " \u{00B7} "), lineLimit: 1, identifier: "market-company-\(l.id)",
                         action: { open(.company(l.id)) })
    }
}

struct CompanyInMarketPage: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var companyID: Int
    @State private var next: MarketRoute?

    var body: some View {
        Group {
            if let e = store.engine, let co = e.state.company(companyID) {
                let line: MarketUI.CompanyLine = MarketData.companyLine(e, co)
                ScrollScreen(spacing: Theme.Space.m, top: Theme.Space.s) {
                    hero(e, line)
                    priceTrend(e)
                    exchangeLink(e, co)
                    research(e, co)
                }
                .appScreen(title: co.name, subtitle: "\(line.trade) \u{00B7} \(line.city)") { menu(e, co, line) }
                .navigationDestination(item: $next) { (r: MarketRoute) in MarketDestination(route: r) }
            } else {
                EmptyState(glyph: Glyph.home, title: "This company is no longer open").ledgerBackground()
            }
        }
    }

    private func hero(_ e: GameEngine, _ l: MarketUI.CompanyLine) -> some View {
        let series: [Double] = MarketData.shareHistory(e, companyID: companyID)
        var parts: [String] = []
        if let t = l.trend { parts.append(MarketFormat.points(t) + " last month") }
        if let r = l.rank { parts.append("#\(r) of \(l.players)") }
        let tint: Color? = l.trend.map { (t: Double) -> Color in P.change(t) }
        return MarketHero(label: "Your share", value: l.shareText, context: parts.joined(separator: " \u{00B7} "), contextTint: tint,
                          series: series, identifier: "market-company-hero")
    }

    @ViewBuilder private func priceTrend(_ e: GameEngine) -> some View {
        let trend: MarketTrend = e.marketTrend(companyID: companyID)
        if trend.points.count >= 2 {
            let change: Double = trend.priceIndexChangeThisMonth
            let steady: Bool = abs(change) < 0.0005
            let text: String = steady ? "Prices are steady this month" : "Prices \(change > 0 ? "up" : "down") \(String(format: "%.1f%%", abs(change) * 100)) this month"
            MarketLabel(title: "Market prices")
            HStack(spacing: Theme.Space.m) {
                Text(text).textStyle(.headline, tint: steady ? nil : P.change(change)).lineLimit(2)
                Spacer(minLength: Theme.Space.s)
                Sparkline(values: trend.points, tint: steady ? P.inkSoft : P.change(change), filled: false)
                    .frame(width: 96, height: 30)
                    .accessibilityHidden(true)
            }
        }
    }

    private func research(_ e: GameEngine, _ co: Company) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MarketLabel(title: "Market research")
            ResearchRow(engine: e, company: co)
        }
    }

    @ViewBuilder private func exchangeLink(_ e: GameEngine, _ co: Company) -> some View {
        if store.levelOpen(.exchange) {
            MarketLabel(title: "Prices for \(e.tradeName(co).lowercased())")
            LedgerRow(leading: .glyph(Glyph.stats), leadingTint: P.inkSoft, title: "Raw materials and energy",
                      subtitle: "Traded on the Exchange", chevron: true, identifier: "market-company-exchange", action: { next = .exchange })
        }
    }

    @ViewBuilder private func menu(_ e: GameEngine, _ co: Company, _ l: MarketUI.CompanyLine) -> some View {
        if l.level == .marketAnalyst, let key = l.marketKey {
            Menu {
                Button("Ask your analyst for a report") {
                    let r = store.act { $0.orderMarketReport(marketKey: key) }
                    if case .refused(let why)? = r { store.show(why, tone: "warn") } else { Haptics.success(); store.show("Report sent to your inbox.", tone: "good") }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(P.ink).frame(width: 44, height: 44)
            }
            .accessibilityLabel("More")
            .accessibilityIdentifier("market-company-more")
        }
    }
}
