import SwiftUI
import GameCore
import Businesses
import Simulation

struct CompetitionApp: View {
    @EnvironmentObject var store: GameStore
    enum Tab: String, CaseIterable, Hashable { case rivals = "Rivals", reviews = "Reviews", field = "Against the field" }
    @State private var tab: Tab = .rivals
    @State private var route: MarketRoute?

    var body: some View {
        Group {
            if store.engine != nil {
                VStack(spacing: 0) {
                    SegmentedPill(items: Tab.allCases, title: { (t: Tab) -> String in t.rawValue }, selection: $tab,
                                  identifier: { (t: Tab) -> String in "competition-tab-\(t.rawValue)" })
                        .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.xs)
                        .frame(maxWidth: 760).frame(maxWidth: .infinity)
                    switch tab {
                    case .rivals: CompetitionRivalsTab(open: { (r: MarketRoute) in route = r })
                    case .reviews: CompetitionReviews()
                    case .field: CompetitionField(open: { (r: MarketRoute) in route = r })
                    }
                }
            } else {
                Color.clear
            }
        }
        .appScreen(title: "Competition", subtitle: PhoneApp.competition.subtitle)
        .navigationDestination(item: $route) { (r: MarketRoute) in MarketDestination(route: r) }
        .accessibilityIdentifier("competition-app")
    }

    static func reviewCompanies(_ e: GameEngine) -> [Company] {
        e.state.companies.filter { (co: Company) -> Bool in
            guard co.status == .open, let family = e.tradeInfo(companyID: co.id)?.family else { return false }
            return !["fin", "energy", "hold", "club"].contains(family)
        }
    }

    static func lineKey(_ e: GameEngine, _ co: Company, _ l: ReviewLine) -> String {
        "v\(co.id).\(e.state.week - l.weeksAgo).\(l.stars).\(l.who)"
    }
}

struct CompetitionField: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var open: (MarketRoute) -> Void
    @State private var companyID = 0
    @State private var compareID: Int?
    @State private var offerFor: RivalKey?

    struct RivalKey: Identifiable, Hashable { var rivalID: Int; var id: Int { rivalID } }

    var body: some View {
        if let e = store.engine {
            let companies: [Company] = e.state.companies.filter { (co: Company) -> Bool in co.status == .open && co.type != "hold" }
            if let co = companies.first(where: { (c: Company) -> Bool in c.id == companyID }) ?? companies.first {
                let rows: [MarketUI.CompareRow] = MarketData.compareRows(e, co)
                ScrollScreen(spacing: Theme.Space.m, top: Theme.Space.s) {
                    if companies.count > 1 { selector(companies, co) }
                    field(e, co, rows)
                    compare(rows)
                    wins(e, co)
                }
                .centerSheet(item: $offerFor, title: "Make an offer", category: .medium, tone: .investment) { (k: RivalKey) in
                    RivalOfferSheet(companyID: co.id, rivalID: k.rivalID)
                }
                .accessibilityIdentifier("competition-field")
            } else {
                EmptyState(glyph: Glyph.market, title: "No company open", message: "Open a company to see how it stands against the field.")
                    .padding(.horizontal, Theme.Space.page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private func selector(_ companies: [Company], _ chosen: Company) -> some View {
        Menu {
            ForEach(companies) { (co: Company) in
                Button {
                    companyID = co.id
                    compareID = nil
                    Haptics.choose()
                } label: {
                    if co.id == chosen.id { Label(co.name, systemImage: "checkmark") } else { Text(co.name) }
                }
            }
        } label: {
            BusinessPickerLabel(caption: "Business", title: chosen.name)
        }
        .accessibilityLabel("Business: \(chosen.name)")
        .accessibilityIdentifier("competition-field-picker")
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
                fieldRow(co, pair.element, cur)
            }
        }
    }

    private func fieldRow(_ co: Company, _ r: MarketUI.CompareRow, _ cur: Currency) -> some View {
        let rating: String = r.rating.map { (x: Double) -> String in String(format: "\u{2605} %.1f", x) } ?? ""
        let note: String = [r.mine ? "" : r.priceText, rating].filter { (s: String) -> Bool in !s.isEmpty }.joined(separator: " \u{00B7} ")
        let sub: String = r.mine ? "You" : ([r.sizeWord, r.forSale ? "for sale" : r.moneyWord].joined(separator: " \u{00B7} "))
        return HStack(spacing: Theme.Space.s) {
            Button {
                Haptics.tap()
                if let rid = r.rivalID { open(.rival(companyID: co.id, rivalID: rid)) }
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
            .accessibilityIdentifier(r.mine ? "competition-field-you" : "competition-field-\(r.rivalID ?? 0)")
            if let rid = r.rivalID {
                Button("Buy") { Haptics.tap(); offerFor = RivalKey(rivalID: rid) }
                    .buttonStyle(TertiaryButtonStyle(size: .compact))
                    .accessibilityLabel("Buy \(r.name)")
                    .accessibilityIdentifier("competition-buy-rival-\(rid)")
            }
        }
        .newMarker(.competition, r.rivalID.map { (rid: Int) -> String in "r\(co.id).\(rid)" } ?? "", style: .dot, alignment: .topLeading)
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
                    .accessibilityIdentifier("competition-compare-with")
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
}
