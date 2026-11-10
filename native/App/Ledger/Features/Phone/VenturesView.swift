import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Events
import Simulation

/// What the venture portfolio is worth and how it stands, read once from the engine so the header and the sections agree.
/// Your share of your own startups, stakes in other founders' startups, funds and group stakes; `gain` is the value (plus fund payouts)
/// against everything put in.
struct VenturesFigures {
    var cur: Currency
    var founded: [Startups.Founded]
    var stakes: [Startups.Stake]
    var funds: [PrivateEquity.Fund]
    var total: Double = 0
    var invested: Double = 0
    var gain: Double = 0
    var offers: Int = 0
    var shortRunway: Int = 0
    var toCall: Double = 0
    var pitches: Int = 0
    var fundOffers: Int = 0
    var bigOffer: BigMeeting.Offer?
    var groupCount: Int = 0

    init(_ e: GameEngine) {
        cur = e.homeCurrency
        let all: [Startups.Founded] = e.foundedStartups
        founded = all.filter { (f: Startups.Founded) -> Bool in f.live }
        stakes = e.startupStakes.filter { (s: Startups.Stake) -> Bool in s.live }
        funds = e.privateEquityFunds.filter { (f: PrivateEquity.Fund) -> Bool in f.live }
        let big: [BigMeeting.Stake] = e.bigMeetingStakes
        let groups: [GroupDeals.Stake] = e.groupStakes
        let own: Double = founded.reduce(0) { (a: Double, f: Startups.Founded) -> Double in a + f.valuation * f.ownership / 100 }
        let held: Double = stakes.reduce(0) { (a: Double, s: Startups.Stake) -> Double in a + s.value }
        let fundValue: Double = funds.reduce(0) { (a: Double, f: PrivateEquity.Fund) -> Double in a + f.nav }
        let bigValue: Double = big.reduce(0) { (a: Double, s: BigMeeting.Stake) -> Double in a + s.value }
        let groupValue: Double = groups.reduce(0) { (a: Double, s: GroupDeals.Stake) -> Double in a + s.value }
        total = own + held + fundValue + bigValue + groupValue
        let ownIn: Double = founded.reduce(0) { (a: Double, f: Startups.Founded) -> Double in a + f.invested }
        let stakeIn: Double = stakes.reduce(0) { (a: Double, s: Startups.Stake) -> Double in a + s.invested }
        let fundIn: Double = funds.reduce(0) { (a: Double, f: PrivateEquity.Fund) -> Double in a + f.paidIn }
        let fundOut: Double = funds.reduce(0) { (a: Double, f: PrivateEquity.Fund) -> Double in a + f.distributed }
        let groupIn: Double = groups.reduce(0) { (a: Double, s: GroupDeals.Stake) -> Double in a + s.cost }
        invested = ownIn + stakeIn + fundIn + groupIn + bigValue
        gain = total + fundOut - invested
        offers = founded.reduce(0) { (a: Int, f: Startups.Founded) -> Int in a + f.offers.count }
        shortRunway = founded.filter { (f: Startups.Founded) -> Bool in f.runwayWeeks < 8 }.count
        toCall = funds.reduce(0) { (a: Double, f: PrivateEquity.Fund) -> Double in a + f.toBeCalled }
        pitches = e.startupPitchesOnOffer.count
        fundOffers = e.privateEquityOffersOnTable.count
        bigOffer = e.bigMeetingOffer
        groupCount = big.count + groups.count
    }

    var isEmpty: Bool { founded.isEmpty && stakes.isEmpty && funds.isEmpty && groupCount == 0 }

    /// "2 startups of your own · 1 stake · 1 fund": what the total is made of.
    var parts: String {
        var out: [String] = []
        if !founded.isEmpty { out.append(founded.count == 1 ? "1 startup of your own" : "\(founded.count) startups of your own") }
        if !stakes.isEmpty { out.append(stakes.count == 1 ? "1 stake" : "\(stakes.count) stakes") }
        if !funds.isEmpty { out.append(funds.count == 1 ? "1 fund" : "\(funds.count) funds") }
        if groupCount > 0 { out.append(groupCount == 1 ? "1 group stake" : "\(groupCount) group stakes") }
        return out.joined(separator: " \u{00B7} ")
    }

    /// "+1.2M (+8%) on 15M put in", or empty when nothing has gone in.
    var changeLine: String {
        guard invested > 0 else { return "" }
        let pct: Int = Int(saturating: (gain / invested * 100).rounded())
        return (gain >= 0 ? "+" : "\u{2212}") + cur.tidyShort(abs(gain)) + " (" + (pct >= 0 ? "+" : "\u{2212}") + "\(abs(pct))%) on \(cur.tidyShort(invested)) put in"
    }

    /// What needs a look, most pressing first.
    var notes: [(text: String, tone: AcctPill.Tone)] {
        var out: [(text: String, tone: AcctPill.Tone)] = []
        if shortRunway > 0 { out.append((shortRunway == 1 ? "1 startup has under 8 weeks of runway" : "\(shortRunway) startups have under 8 weeks of runway", .bad)) }
        if offers > 0 { out.append((offers == 1 ? "1 funding offer is waiting for you" : "\(offers) funding offers are waiting for you", .good)) }
        if let o = bigOffer { out.append(("\(o.pct)% of \(o.target) is on offer", .good)) }
        if toCall > 0 { out.append(("\(cur.tidyShort(toCall)) still to be called by your funds", .warn)) }
        return out
    }
}

/// The popups of the venture portfolio. One popup at a time, opened from a row.
enum VentureSheet: Identifiable, Equatable {
    case found, launch(Int), back(Int), sellStake(Int), fund(String), sellFund(Int), groupBuy(String)
    var id: String {
        switch self {
        case .found: return "found"
        case .launch(let n): return "launch-\(n)"
        case .back(let n): return "back-\(n)"
        case .sellStake(let n): return "sell-\(n)"
        case .fund(let s): return "fund-\(s)"
        case .sellFund(let n): return "sellfund-\(n)"
        case .groupBuy(let s): return "group-\(s)"
        }
    }
}

/// The one home of the venture portfolio (Ventures > Portfolio, and the standalone phone app): a portfolio header, then your startups, the
/// startups and funds you back, group stakes and software, each with one row per holding and its main action. Founding, backing, committing
/// and selling run in popups with the price or cost shown first.
/// Logic: `Startups`, `PrivateEquity`, `BigMeeting`, `GroupDeals`, `SoftwareProducts`.
struct VenturesHome: View {
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @State private var sheet: VentureSheet?
    @State private var pending: PendingAction?
    /// The row that is open (its actions showing): one at a time across the whole page.
    @State private var open: String?

    var body: some View {
        if let e = store.engine {
            let fig = VenturesFigures(e)
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                VenturesHeader(figures: fig, found: found).coachAnchor(.venturesHeader)
                if fig.isEmpty {
                    EmptyState(glyph: Glyph.ventures, title: "No ventures yet",
                               message: "Found a startup and build it, back a founder with a stake, or commit to a fund. Whatever you hold shows here with its value and what to do next.",
                               actionTitle: "Found a startup", action: found)
                } else {
                    VenturesStartupsSection(engine: e, open: $open, sheet: $sheet, pending: $pending)
                }
                if !fig.isEmpty || fig.pitches > 0 {
                    VenturesBackingSection(engine: e, open: $open, sheet: $sheet, pending: $pending).coachTopStrip(.venturesBacking, height: 56)
                }
                if !fig.isEmpty || fig.fundOffers > 0 {
                    VenturesFundsSection(engine: e, open: $open, sheet: $sheet, pending: $pending)
                }
                if fig.groupCount > 0 || fig.bigOffer != nil || !e.rivalGroupsAround().isEmpty {
                    VenturesGroupsSection(engine: e, open: $open, sheet: $sheet, pending: $pending)
                }
                StartupMarketEntry()
                VenturesSoftwareSection(engine: e)
            }
            .confirmAction($pending)
            .centerSheet(item: $sheet, title: "", category: .medium, tone: .investment) { (s: VentureSheet) in sheetContent(s) }
        }
    }

    private func found() { ent.run(.ventures, "Found a startup") { sheet = .found } }

    @ViewBuilder private func sheetContent(_ s: VentureSheet) -> some View {
        switch s {
        case .found: FoundStartupSheet()
        case .launch(let id):
            if let e = store.engine, let f = e.foundedStartups.first(where: { (x: Startups.Founded) -> Bool in x.id == id }) { StartupLaunchSheet(engine: e, f: f) }
        case .back(let id): BackStartupSheet(pitchID: id)
        case .sellStake(let id): SellStakeSheet(stakeID: id)
        case .fund(let id): FundCommitSheet(offerID: id)
        case .sellFund(let id): FundSellSheet(fundID: id)
        case .groupBuy(let id): GroupStakeSheet(groupID: id)
        }
    }
}

/// Header of the portfolio: its value as the one big figure, the change against what went in, what the total is made of, the things that
/// need a look, and the main action.
struct VenturesHeader: View {
    var figures: VenturesFigures
    var found: () -> Void
    @Environment(\.outsidePalette) private var P
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 40

    var body: some View {
        let f: VenturesFigures = figures
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Venture portfolio").capsLabel(P.inkFaint)
            Text(f.total > 0 ? f.cur.tidyShort(f.total) : "Nothing yet")
                .font(.system(size: heroSize, weight: .medium, design: .serif).monospacedDigit())
                .foregroundStyle(P.ink)
                .lineLimit(2).minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            if !f.changeLine.isEmpty {
                Text(f.changeLine).textStyle(.body, tint: P.change(f.gain), numeric: true)
            }
            if !f.parts.isEmpty {
                Text(f.parts).textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(f.notes.enumerated()), id: \.offset) { item in
                AcctPill(text: item.element.text, tone: item.element.tone)
            }
            HStack(spacing: Theme.Space.s) {
                Button("Found a startup", action: found).buttonStyle(PrimaryButtonStyle(size: .compact))
                    .coachAnchor(.venturesFound)
                    .accessibilityIdentifier("ventures-found")
                ProMark(feature: .ventures)
            }
            .padding(.top, Theme.Space.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
