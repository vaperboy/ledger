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
    @State private var compareID: Int?
    @State private var offerFor: RivalKey?

    struct RivalKey: Identifiable, Hashable { var rivalID: Int; var id: Int { rivalID } }

    var body: some View {
        Group {
            if let e = store.engine, let co = e.state.company(companyID) {
                let line: MarketUI.CompanyLine = MarketData.companyLine(e, co)
                let rows: [MarketUI.CompareRow] = MarketData.compareRows(e, co)
                ScrollScreen(spacing: Theme.Space.m, top: Theme.Space.s) {
                    hero(e, line)
                    field(e, co, rows)
                    compare(rows)
                    wins(e, co)
                    priceTrend(e)
                    research(e, co)
                    news(e)
                }
                .appScreen(title: co.name, subtitle: "\(line.trade) \u{00B7} \(line.city)") { menu(e, co, line) }
                .navigationDestination(item: $next) { (r: MarketRoute) in MarketDestination(route: r) }
                .centerSheet(item: $offerFor, title: "Make an offer", category: .medium, tone: .investment) { (k: RivalKey) in
                    RivalOfferSheet(companyID: companyID, rivalID: k.rivalID)
                }
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

    private func field(_ e: GameEngine, _ co: Company, _ rows: [MarketUI.CompareRow]) -> some View {
        let cur: Currency = e.currency(for: co)
        return VStack(alignment: .leading, spacing: 0) {
            MarketLabel(title: "Against the field")
            if rows.count <= 1 {
                EmptyState(glyph: Glyph.market, title: "No rivals here yet", centered: false).padding(.top, Theme.Space.s)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { (pair: (offset: Int, element: MarketUI.CompareRow)) in
                if pair.offset > 0 { Hairline() }
                fieldRow(e, co, pair.element, cur)
            }
        }
    }

    private func fieldRow(_ e: GameEngine, _ co: Company, _ r: MarketUI.CompareRow, _ cur: Currency) -> some View {
        let rating: String = r.rating.map { (x: Double) -> String in String(format: "\u{2605} %.1f", x) } ?? ""
        let note: String = [r.mine ? "" : r.priceText, rating].filter { (s: String) -> Bool in !s.isEmpty }.joined(separator: " \u{00B7} ")
        let sub: String = r.mine ? "You" : ([r.sizeWord, r.forSale ? "for sale" : r.moneyWord].joined(separator: " \u{00B7} "))
        return HStack(spacing: Theme.Space.s) {
            Button {
                Haptics.tap()
                if let rid = r.rivalID { next = .rival(companyID: companyID, rivalID: rid) }
            } label: {
                HStack(spacing: Theme.Space.m) {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(r.name.tidyText).textStyle(.headline, tint: r.mine ? P.accent : nil).lineLimit(1)
                        Text(sub.tidyText).textStyle(.caption, tint: r.forSale ? P.accent : nil).lineLimit(1)
                    }
                    Spacer(minLength: Theme.Space.s)
                    VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                        Text(r.shareText.tidyText).textStyle(.headline, numeric: true).lineLimit(1).minimumScaleFactor(0.7)
                        if !note.isEmpty { Text(note).textStyle(.caption, tint: P.inkFaint, numeric: true).lineLimit(1) }
                    }
                }
                .padding(.vertical, Theme.Space.m)
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(AcctPressStyle())
            .disabled(r.mine)
            .accessibilityIdentifier(r.mine ? "market-field-you" : "market-field-\(r.rivalID ?? 0)")
            if let rid = r.rivalID {
                Button("Buy") { Haptics.tap(); offerFor = RivalKey(rivalID: rid) }
                    .buttonStyle(TertiaryButtonStyle(size: .compact))
                    .accessibilityLabel("Buy \(r.name)")
                    .accessibilityIdentifier("market-buy-rival-\(rid)")
            }
        }
        .newMarker(.market, r.rivalID.map { (rid: Int) -> String in "r\(companyID).\(rid)" } ?? "", style: .dot, alignment: .topLeading)
    }

    @ViewBuilder private func compare(_ rows: [MarketUI.CompareRow]) -> some View {
        let rivals: [MarketUI.CompareRow] = rows.filter { (r: MarketUI.CompareRow) -> Bool in !r.mine }
        if let me = rows.first(where: { (r: MarketUI.CompareRow) -> Bool in r.mine }), !rivals.isEmpty {
            let them: MarketUI.CompareRow = rivals.first(where: { (r: MarketUI.CompareRow) -> Bool in r.rivalID == compareID }) ?? rivals[0]
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Compare with").textStyle(.label, tint: P.inkFaint)
                    Spacer(minLength: Theme.Space.s)
                    Menu {
                        ForEach(rivals) { (r: MarketUI.CompareRow) in
                            Button(r.name) { Haptics.choose(); compareID = r.rivalID }
                        }
                    } label: {
                        HStack(spacing: Theme.Space.xs) {
                            Text(them.name.tidyText).textStyle(.body, tint: P.accent, weight: .medium).lineLimit(1)
                            LedgerGlyph(glyph: Glyph.chevronDown, size: 12, tint: P.accent)
                        }
                        .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("market-compare-with")
                }
                FigureRow(items: [
                    KeyFigures.Item(label: "Share", value: me.shareText, sub: "them " + them.shareText),
                    KeyFigures.Item(label: "Their price", value: them.priceText, sub: "against yours"),
                    KeyFigures.Item(label: "Rating", value: me.rating.map { (x: Double) -> String in String(format: "%.1f", x) } ?? "\u{2013}",
                                    sub: "them " + (them.rating.map { (x: Double) -> String in String(format: "%.1f", x) } ?? "\u{2013}")),
                ], combineCells: true)
            }
            .padding(.top, Theme.Space.l)
        }
    }

    private func wins(_ e: GameEngine, _ co: Company) -> some View {
        let lines: [String] = MarketData.whatWins(e, co)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            MarketLabel(title: "What wins customers")
            ForEach(Array(lines.enumerated()), id: \.offset) { (pair: (offset: Int, element: String)) in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Circle().fill(P.accent).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { (d: ViewDimensions) -> CGFloat in d[.bottom] + 4 }
                    Text(pair.element).textStyle(.body, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
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

    @ViewBuilder private func news(_ e: GameEngine) -> some View {
        let events: [MarketEvent] = MarketEventRows.relevant(e, companyID: companyID, limit: 6)
        if !events.isEmpty {
            MarketLabel(title: "Latest here")
            MarketEventRows(events: events, showsTitle: false)
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
