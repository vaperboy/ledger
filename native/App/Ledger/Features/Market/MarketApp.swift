import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The Market app (Phone): the one place for your markets, your rivals, everything you invest and the world beyond. Five parts under
/// the header: Overview, Companies, Rivals, Invest, World. A link from elsewhere names a company (its market page opens) or a part.
struct MarketApp: View {
    @EnvironmentObject var store: GameStore
    @State private var tab: MarketUI.Tab = .overview
    @State private var route: MarketRoute?

    var body: some View {
        Group {
            if store.engine != nil {
                VStack(spacing: 0) {
                    SegmentedPill(items: MarketUI.Tab.allCases, title: { (t: MarketUI.Tab) -> String in t.rawValue }, selection: $tab,
                                  identifier: { (t: MarketUI.Tab) -> String in "market-tab-\(t.rawValue)" })
                        .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.xs).padding(.bottom, Theme.Space.s)
                        .frame(maxWidth: 760).frame(maxWidth: .infinity)
                    SegmentPager(items: MarketUI.Tab.allCases, selection: $tab) { (t: MarketUI.Tab) in page(t) }
                }
                .accessibilityIdentifier("market-app")
            } else {
                Color.clear
            }
        }
        .appScreen(title: "Market", subtitle: PhoneApp.market.subtitle)
        .navigationDestination(item: $route) { (r: MarketRoute) in MarketDestination(route: r) }
        .onAppear { take() }
        .onChange(of: store.appRequest) { _, _ in take() }
    }

    @ViewBuilder private func page(_ t: MarketUI.Tab) -> some View {
        let open: (MarketRoute) -> Void = { (r: MarketRoute) in route = r }
        switch t {
        case .overview: MarketOverviewPage(open: open, show: { (x: MarketUI.Tab) in tab = x })
        case .companies: MarketCompaniesPage(open: open)
        case .rivals: MarketRivalsPage(open: open)
        case .invest: MarketInvestPage(open: open)
        case .world: MarketWorldPage(open: open)
        }
    }

    /// A link names a part, or a company whose market page opens over Companies; a company that is gone falls back to the Overview.
    private func take() {
        let news: Bool = store.marketNewsPending
        store.marketNewsPending = false
        if let t = store.takeMarketTabRequest() { tab = t; return }
        guard let id = store.takeMarketRequest() else {
            if news { tab = .overview }
            return
        }
        guard id != 0, store.engine?.state.company(id) != nil else { tab = .overview; return }
        tab = .companies
        Task { @MainActor in route = .company(id) }
    }
}

// MARK: Pages inside the app

/// Every page the Market app pushes over itself.
enum MarketRoute: Hashable, Identifiable {
    case company(Int)
    case rival(companyID: Int, rivalID: Int)
    case group(String)
    case position(String)
    case buy(assetID: String?, owner: MarketUI.Owner?)
    case sell(String)
    case country(String)
    case rankings
    case records
    case aroundYou
    case fundManager
    case dataAnalyst

    var id: String {
        switch self {
        case .company(let id): return "company.\(id)"
        case .rival(let c, let r): return "rival.\(c).\(r)"
        case .group(let id): return "group.\(id)"
        case .position(let id): return "position.\(id)"
        case .buy(let a, let o): return "buy.\(a ?? "").\(o?.key ?? "")"
        case .sell(let id): return "sell.\(id)"
        case .country(let c): return "country.\(c)"
        case .rankings: return "rankings"
        case .records: return "records"
        case .aroundYou: return "around"
        case .fundManager: return "fundManager"
        case .dataAnalyst: return "dataAnalyst"
        }
    }
}

/// The screen for a `MarketRoute`. Pushed pages that push further pages host their own destination with this same table.
struct MarketDestination: View {
    var route: MarketRoute

    var body: some View {
        Group {
            switch route {
            case .company(let id): CompanyInMarketPage(companyID: id)
            case .rival(let c, let r): RivalProfilePage(companyID: c, rivalID: r)
            case .group(let id): RivalGroupProfileView(groupID: id)
            case .position(let id): PositionPage(positionID: id)
            case .buy(let a, let o): MarketTradeFlow(side: .buy, assetID: a, owner: o, positionID: nil)
            case .sell(let id): MarketTradeFlow(side: .sell, assetID: nil, owner: nil, positionID: id)
            case .country(let c): CountryPage(countryCode: c)
            case .rankings: MarketRankingsPage()
            case .records: WorldRecordsView().appScreen(title: "Records", subtitle: "Market \u{00B7} World")
            case .aroundYou: WorldAroundView().appScreen(title: "People and reputation", subtitle: "Market \u{00B7} World")
            case .fundManager:
                ScrollScreen(spacing: Theme.Space.l, top: Theme.Space.s) { FundManagerPage() }
                    .appScreen(title: "Fund manager", subtitle: "Market \u{00B7} Invest")
            case .dataAnalyst:
                ScrollScreen(spacing: Theme.Space.l, top: Theme.Space.s) { DataAnalystCard() }
                    .appScreen(title: "Data analyst", subtitle: "Market \u{00B7} Companies")
            }
        }
        .id(route)
    }
}

/// The fund manager desk, read from the engine as it is.
private struct FundManagerPage: View {
    @EnvironmentObject var store: GameStore
    var body: some View {
        if let e = store.engine { FundManagerCard(engine: e) }
    }
}

// MARK: Shared pieces of the Market screens

/// The one big figure a Market screen opens with: a small label, the figure in large serif, one context line and, with history, a line.
struct MarketHero: View {
    var label: String
    var value: String
    var context: String = ""
    var contextTint: Color? = nil
    var series: [Double] = []
    var seriesTint: Color? = nil
    var identifier: String = ""
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 40
    @Environment(\.outsidePalette) private var P

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(label.tidyText).textStyle(.label, tint: P.inkFaint)
            Text(value.tidyText)
                .font(.system(size: size, weight: .medium, design: .serif)).monospacedDigit()
                .foregroundStyle(P.ink)
                .lineLimit(1).minimumScaleFactor(0.5)
                .accessibilityIdentifier(identifier.isEmpty ? "market-hero" : identifier)
            if !context.isEmpty {
                Text(context.tidyText).textStyle(.body, tint: contextTint ?? P.inkSoft, numeric: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if series.count >= 2 {
                Sparkline(values: series, tint: seriesTint ?? P.accent, filled: true)
                    .frame(height: 48)
                    .padding(.top, Theme.Space.s)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A caps label above a group, with an optional quiet note on the right.
struct MarketLabel: View {
    var title: String
    var note: String = ""
    @Environment(\.outsidePalette) private var P

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(title.tidyText).textStyle(.label, tint: P.inkFaint)
            Spacer(minLength: Theme.Space.s)
            if !note.isEmpty { Text(note.tidyText).textStyle(.caption, tint: P.inkFaint).lineLimit(1) }
        }
        .padding(.top, Theme.Space.l)
    }
}

/// Signed figures in one wording across the app.
enum MarketFormat {
    /// "+4.2%" / "−1.0%".
    static func percent(_ share: Double, decimals: Int = 1) -> String {
        let v: Double = share * 100
        let body: String = String(format: "%.\(decimals)f%%", abs(v))
        return (v >= 0 ? "+" : "\u{2212}") + body
    }

    /// "+£2.4k" / "−£300".
    static func money(_ v: Double, _ cur: Currency) -> String {
        (v >= 0 ? "+" : "\u{2212}") + cur.tidyShort(abs(v))
    }

    /// "+1.2 pts".
    static func points(_ v: Double) -> String {
        (v >= 0 ? "+" : "\u{2212}") + String(format: "%.1f pts", abs(v))
    }
}

/// A row in the house style with a thin bar under its text: how big a part of the whole it is (a position of the portfolio).
struct MarketBarRow: View {
    var glyph: String
    var title: String
    var subtitle: String
    var value: String
    var valueNote: String = ""
    var valueNoteTint: Color? = nil
    var fraction: Double? = nil
    var identifier: String = ""
    var action: () -> Void
    @Environment(\.outsidePalette) private var P

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: Theme.Space.m) {
                LedgerGlyph(glyph: glyph, size: Theme.Icon.large, tint: P.inkSoft)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(title.tidyText).textStyle(.headline).lineLimit(1)
                    Text(subtitle.tidyText).textStyle(.caption).lineLimit(1)
                    if let f = fraction {
                        ProgressLine(fraction: f, tint: P.accent.opacity(0.7), height: 2).padding(.top, Theme.Space.xxs)
                    }
                }
                Spacer(minLength: Theme.Space.s)
                VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                    Text(value.tidyText).textStyle(.headline, numeric: true).lineLimit(1).minimumScaleFactor(0.7)
                    if !valueNote.isEmpty {
                        Text(valueNote.tidyText).textStyle(.caption, tint: valueNoteTint ?? P.inkFaint, numeric: true).lineLimit(1)
                    }
                }
                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint)
            }
            .padding(.vertical, Theme.Space.m)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(AcctPressStyle())
        .modifier(OptionalIdentifier(identifier: identifier))
    }
}

/// A tappable tile for something that needs attention (an opportunity, a threat): raised surface, glyph, two lines.
struct MarketSignalTile: View {
    var signal: MarketUI.Signal
    var action: () -> Void
    @Environment(\.outsidePalette) private var P

    var body: some View {
        let tint: Color = signal.tone == "bad" ? P.loss : (signal.tone == "gold" ? P.accent : P.inkSoft)
        let opens: Bool = signal.target != MarketUI.Signal.Target.nothing
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                LedgerGlyph(glyph: signal.glyph, size: Theme.Icon.medium, tint: tint)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(signal.title.tidyText).textStyle(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(signal.detail.tidyText).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if opens { LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint) }
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(P.surfaceRaised))
            .elevation(.raised)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(PressableStyle())
        .disabled(!opens)
        .accessibilityIdentifier("market-signal-\(signal.id)")
    }
}
