import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The pages of the Country app. Each page draws its own header and palette; Back from a page returns to the overview.
enum CountrySection: Hashable {
    case overview, donate, election, president, record, shadow
}

/// Country: the state's treasury, rates, president, printed money and prices, and the doors to donating, the election, the president's desk,
/// the record of convictions and the dark side of business.
struct CountryApp: View {
    @EnvironmentObject var store: GameStore
    @State private var page: CountrySection = .overview

    var body: some View {
        Group {
            if let e = store.engine {
                if let r = e.countryRead() {
                    pageView(e, r)
                } else {
                    Text("Opening the state's books").textStyle(.body)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .outsideScreen(.civic)
                }
            }
        }
        .task { store.ensureCountry() }
        .accessibilityIdentifier("country-app")
    }

    @ViewBuilder private func pageView(_ e: GameEngine, _ r: CountryRead) -> some View {
        let home: () -> Void = { page = .overview }
        switch page {
        case .overview: CountryOverview(e: e, r: r) { (p: CountrySection) in page = p }
        case .donate: DonateScreen(e: e, r: r, back: home)
        case .election: ElectionScreen(e: e, r: r, back: home)
        case .president: PresidentScreen(e: e, r: r, back: home)
        case .record: RecordScreen(e: e, r: r, back: home)
        case .shadow: ShadowScreen(e: e, back: home)
        }
    }
}

/// The overview: brass on night blue. The treasury as the one big figure, the two tax rates as dials, the president, the public record
/// of printed money with the price level it feeds, and the latest government news.
struct CountryOverview: View {
    var e: GameEngine
    var r: CountryRead
    var open: (CountrySection) -> Void
    @EnvironmentObject var store: GameStore
    @State private var showAllMints = false
    private let P: OutsidePalette = .civic

    var body: some View {
        CivicPage(spacing: 20) {
            CivicHeader(title: r.name, subtitle: "The state, its money and its president")
            hero
            tiles
            rates
            presidentCard
            supplyCard
            priceCard
            flowsCard
            newsCard
        }
        .outsideScreen(.civic)
        .accessibilityIdentifier("country-overview")
    }

    // MARK: Treasury

    private var hero: some View {
        let supply: GovMoneySupply = r.gov.supply
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                GlyphView(glyph: Glyph.civicDome, size: 18, weight: 1.6, tint: P.accent)
                Text("The treasury").textStyle(.label)
                Spacer(minLength: 0)
                Text(CivicWords.date(r.week)).textStyle(.caption, tint: P.inkFaint)
            }
            Text(r.cur.tidyDisplay(r.gov.treasury.balance))
                .font(.system(size: 40, weight: .medium, design: .serif).monospacedDigit())
                .foregroundStyle(P.ink).lineLimit(1).minimumScaleFactor(0.5)
            Rectangle().fill(P.accent.opacity(0.5)).frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                stat("In circulation", r.cur.tidyShort(supply.total))
                stat("Printed so far", supply.mints.isEmpty ? "None" : CivicWords.pct1((supply.total - supply.base) / supply.base))
                stat("Price level", String(format: "%.3f", e.state.economy.inflationIndex))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [P.card, P.cardDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(P.accent.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(P.inkFaint)
            Text(value).font(.system(size: 16, weight: .medium, design: .serif).monospacedDigit()).foregroundStyle(P.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Doors

    private var tiles: some View {
        let cols: [GridItem] = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            tile(Glyph.coinStack, "Donate", "A gift to the treasury. It buys nothing.", .donate)
            tile(Glyph.ballotBox, "Election", electionLine, .election)
            tile(Glyph.podium, "President's desk", deskLine, .president)
            tile(Glyph.gavel, "Record", "Convictions and the public watchlist.", .record)
        }
    }

    private func tile(_ glyph: String, _ title: String, _ line: String, _ target: CountrySection) -> some View {
        CivicTile(glyph: glyph, title: title, line: line, fill: P.card, edge: P.line, tint: P.accent, ink: P.ink, soft: P.inkSoft) { open(target) }
    }

    private var electionLine: String {
        guard let el = r.gov.election, el.status != .closed else { return r.gov.office == nil ? "No vote under way." : "Next vote when the term ends." }
        switch el.status {
        case .nomination: return "Nominations are open."
        case .voting: return "Voting is open."
        default: return "Counted. An administrator confirms."
        }
    }

    private var deskLine: String { r.isPresident ? "You hold the office." : "Rates and price support." }

    // MARK: Rates

    private var rates: some View {
        let pol: GovPolicy = r.gov.policy
        let tr: ClosedRange<Double> = GovPolicy.transferRange
        let gr: ClosedRange<Double> = GovPolicy.gainsRange
        let tf: Double = (pol.transferTax - tr.lowerBound) / (tr.upperBound - tr.lowerBound)
        let gf: Double = (pol.gainsTax - gr.lowerBound) / (gr.upperBound - gr.lowerBound)
        return section("Tax rates") {
            HStack(alignment: .top, spacing: 8) {
                CivicDial(fraction: tf, center: CivicWords.pct1(pol.transferTax), label: "Transfer tax", note: "on money moved",
                          tint: P.accent, track: P.line, ink: P.ink, soft: P.inkSoft)
                CivicDial(fraction: gf, center: CivicWords.pct1(pol.gainsTax), label: "Gains tax", note: "on profit made",
                          tint: P.accent2, track: P.line, ink: P.ink, soft: P.inkSoft)
            }
            Text(rateNote(pol)).textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func rateNote(_ pol: GovPolicy) -> String {
        let base: String = "A rate moves one point at a time, and not more often than every \(GovPolicy.changeGapWeeks) weeks."
        guard let last = pol.lastChangeWeek else { return base }
        let left: Int = GovPolicy.changeGapWeeks - (r.week - last)
        return left > 0 ? base + " Next change possible in \(CivicWords.weeks(left))." : base
    }

    // MARK: President

    private var presidentCard: some View {
        section("President") {
            if let o = r.gov.office {
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        Circle().fill(P.accent.opacity(0.18))
                        Text(initials(o.name)).font(.system(size: 20, weight: .medium, design: .serif)).foregroundStyle(P.accent)
                    }
                    .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(r.shown(o.name, account: o.holder)).font(.system(size: 19, weight: .medium, design: .serif)).foregroundStyle(P.ink)
                        Text("In office until \(CivicWords.date(o.termEnd)), \(CivicWords.weeks(max(0, o.termEnd - r.week))) left")
                            .textStyle(.caption)
                    }
                    Spacer(minLength: 0)
                }
                if !o.promises.isEmpty {
                    Rectangle().fill(P.hairline).frame(height: 1)
                    ForEach(Array(o.promises.enumerated()), id: \.offset) { (_: Int, p: CampaignPromise) in
                        HStack(spacing: 10) {
                            GlyphView(glyph: p.kept ? Glyph.check : Glyph.ring, size: 16, weight: 1.8, tint: p.kept ? P.gain : P.inkFaint)
                            Text(CivicWords.promise(p, trades: tradeName)).textStyle(.body)
                            Spacer(minLength: 6)
                            Text(p.kept ? "Kept" : "Open").textStyle(.caption, tint: p.kept ? P.gain : P.inkFaint)
                        }
                    }
                }
            } else {
                HStack(spacing: 12) {
                    GlyphView(glyph: Glyph.person, size: 26, weight: 1.4, tint: P.inkFaint)
                    Text(vacantLine).textStyle(.body).fixedSize(horizontal: false, vertical: true)
                }
                Button("Go to the election") { open(.election) }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var vacantLine: String {
        guard let el = r.gov.election, el.status != .closed else { return "The office is vacant. A new vote opens soon." }
        return "The office is vacant. The election is under way."
    }

    private func initials(_ name: String) -> String {
        let parts: [Substring] = name.split(separator: " ")
        let s: String = parts.prefix(2).compactMap { (p: Substring) -> String? in p.first.map { String($0) } }.joined()
        return s.isEmpty ? "?" : s.uppercased()
    }

    private func tradeName(_ id: String) -> String { e.data.catalog.trades[id]?.name ?? id }

    // MARK: Printed money

    private var supplyCard: some View {
        let mints: [GovMint] = Array(r.gov.supply.mints.reversed())
        let shown: [GovMint] = showAllMints ? mints : Array(mints.prefix(4))
        return section("Money printed", trailing: mints.count > 4 ? (showAllMints ? "Show fewer" : "Show all \(mints.count)") : "", onTrailing: { showAllMints.toggle() }) {
            if mints.isEmpty {
                Text("Nothing has been printed. The supply is as it began.").textStyle(.body)
            } else {
                ForEach(shown) { (m: GovMint) in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.reason).textStyle(.body).fixedSize(horizontal: false, vertical: true)
                            Text(CivicWords.date(m.week)).textStyle(.caption, tint: P.inkFaint)
                        }
                        Spacer(minLength: 8)
                        Text("+" + r.cur.tidyShort(m.amount)).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(P.caution)
                    }
                    if m.id != shown.last?.id { Rectangle().fill(P.hairline).frame(height: 1) }
                }
            }
            Text("Every printing is public and stays on this record for good. One printing is at most 5% of the supply, and 15% in 12 weeks.")
                .textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Price index

    private var priceCard: some View {
        let from: Int = max(1, r.week - 25)
        let series: [Double] = r.week >= from ? (from...max(from, r.week)).map { (w: Int) -> Double in GovInflation.index(r.gov.supply, atWeek: w) } : [1]
        let extra: Double = (series.last ?? 1) - 1
        return section("Prices") {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Added by printing").textStyle(.caption, tint: P.inkFaint)
                    Text((extra >= 0 ? "+" : "") + CivicWords.pct1(extra))
                        .font(.system(size: 30, weight: .medium, design: .serif).monospacedDigit()).foregroundStyle(extra > 0.0005 ? P.caution : P.ink)
                }
                CivicSpark(values: series.count > 1 ? series : [1, 1], tint: P.accent).frame(height: 54)
            }
            Text("Printing lifts prices \(GovInflation.lagWeeks) weeks later, over \(GovInflation.spread) weeks. Nothing brings prices back down.")
                .textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Treasury flows

    private var flowsCard: some View {
        let list: [GovTreasuryEntry] = Array(r.gov.treasury.entries.prefix(5))
        return section("Treasury, latest") {
            if list.isEmpty {
                Text("No money has moved yet.").textStyle(.body)
            } else {
                ForEach(list, id: \.id) { (t: GovTreasuryEntry) in
                    HStack {
                        Text(CivicWords.treasuryKind(t.kind)).textStyle(.body)
                        Spacer(minLength: 8)
                        Text((t.amount >= 0 ? "+" : "") + r.cur.tidyShort(t.amount))
                            .font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(t.amount >= 0 ? P.gain : P.loss)
                    }
                    if t.id != list.last?.id { Rectangle().fill(P.hairline).frame(height: 1) }
                }
            }
            Button { open(.shadow) } label: {
                HStack(spacing: 8) {
                    GlyphView(glyph: Glyph.warning, size: 16, weight: 1.6, tint: P.inkFaint)
                    Text("Off the books").textStyle(.caption, tint: P.inkFaint)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
        }
    }

    // MARK: News

    private var newsCard: some View {
        let list: [GovNews] = Array(r.gov.news.prefix(4))
        return section("From the government", trailing: "Open News", onTrailing: { store.openApp(.news) }) {
            if list.isEmpty {
                Text("Quiet. Announcements appear here and in News.").textStyle(.body)
            } else {
                ForEach(list) { (n: GovNews) in
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(toneColor(n.tone)).frame(width: 8, height: 8).padding(.top, 6).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(n.text).textStyle(.body).fixedSize(horizontal: false, vertical: true)
                            Text(CivicWords.date(n.week)).textStyle(.caption, tint: P.inkFaint)
                        }
                    }
                }
            }
        }
    }

    private func toneColor(_ tone: String) -> Color { tone == "good" ? P.gain : tone == "bad" ? P.loss : P.accent }

    // MARK: Section frame

    private func section<C: View>(_ title: String, trailing: String = "", onTrailing: @escaping () -> Void = {}, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).textStyle(.label)
                Spacer(minLength: 8)
                if !trailing.isEmpty {
                    Button(trailing) { onTrailing() }.buttonStyle(TertiaryButtonStyle(size: .compact))
                }
            }
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(P.card))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(P.line, lineWidth: 1))
        }
    }
}
