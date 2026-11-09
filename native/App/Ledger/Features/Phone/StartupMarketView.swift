import SwiftUI
import GameCore
import Countries
import Businesses
import Events
import Simulation

/// The small orange fire of a startup that many players invested in within a short time. Static on purpose: it only says "more people see this",
/// it adds no money and no value.
struct ViralFlame: View {
    var body: some View {
        Image(systemName: "flame.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.orange)
            .accessibilityLabel("Going viral")
    }
}

/// Words and figures every startup screen shares.
enum StartupText {
    static func stageName(_ st: CrowdStartup) -> String {
        switch st.status {
        case .failed: return "Failed"
        case .closed: return "Closed"
        default:
            if let s = st.openStage { return "Raising: " + CrowdStartupRules.stageNames[s].lowercased() }
            return "Fully funded"
        }
    }

    /// How far the open stage is filled, in words (the bar shows the same).
    static func raiseWords(_ st: CrowdStartup) -> String {
        guard let s = st.openStage else { return st.status == .failed || st.status == .closed ? "No longer raising" : "All three stages are funded" }
        let f: Double = fraction(st)
        switch f {
        case ..<0.02: return "Nobody has invested in this stage yet"
        case ..<0.35: return "A small part of this stage is funded"
        case ..<0.65: return "About half of this stage is funded"
        case ..<0.98: return "Most of this stage is funded"
        default: return "This stage is full (\(CrowdStartupRules.stageNames[s].lowercased()))"
        }
    }

    static func fraction(_ st: CrowdStartup) -> Double {
        guard let s = st.openStage else { return 1 }
        let t: Double = CrowdStartupRules.stageTarget(st.plan, stage: s)
        return t > 0 ? min(1, st.raised(stage: s) / t) : 0
    }

    static func health(_ st: CrowdStartup) -> (String, AcctPill.Tone) {
        switch st.status {
        case .failed: return ("Failed", .bad)
        case .closed: return ("Closed", .neutral)
        default:
            switch st.milestones {
            case 0: return ("Not open yet", .neutral)
            case 1: return ("Open", .neutral)
            case 2: return ("Selling", .good)
            default: return ("Profitable", .good)
            }
        }
    }

    static func lockWords(_ weeks: Int) -> String { "\(weeks) game weeks" }
}

/// The popups of the startup screens: one at a time.
enum StartupSheet: Identifiable, Equatable {
    case found, invest(String), buy(String), sell(String)
    var id: String {
        switch self {
        case .found: return "found"
        case .invest(let s): return "invest-" + s
        case .buy(let s): return "buy-" + s
        case .sell(let s): return "sell-" + s
        }
    }
}

/// The entry in the venture portfolio: opens the market.
struct StartupMarketEntry: View {
    @ObservedObject private var market = StartupMarketStore.shared

    var body: some View {
        let list: [CrowdStartup] = market.service.startups()
        let mine: Int = market.service.myHoldings().count
        return LedgerSection("Startup market") {
            NavigationLink {
                StartupMarketView().environment(\.outsidePalette, OutsidePalette.game)
            } label: {
                LedgerRow(leading: .glyph(Glyph.ventures), title: "Startups funded by players",
                          subtitle: mine > 0 ? "You hold shares in \(mine) of them" : "Browse, invest, or open one and let other players fund it",
                          value: list.isEmpty ? "" : "\(list.filter { $0.openStage != nil }.count) raising", chevron: true, identifier: "startup-market-entry")
            }
            .buttonStyle(AcctPressStyle())
        }
    }
}

/// Browse the startups other players are raising money for. Filters: trade, stage, going viral. A row opens the startup's page.
struct StartupMarketView: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var market = StartupMarketStore.shared
    @State private var trade = "All trades"
    @State private var stage = -1
    @State private var viralOnly = false
    @State private var sheet: StartupSheet?

    var body: some View {
        let today: Int = store.engine.map { StartupMarketStore.today($0) } ?? 0
        let all: [CrowdStartup] = market.service.startups().filter { $0.status == .raising || $0.status == .live }
        let trades: [String] = ["All trades"] + Array(Set(all.map { $0.trade })).sorted()
        let shown: [CrowdStartup] = all.filter { (s: CrowdStartup) -> Bool in
            (trade == "All trades" || s.trade == trade) && (stage < 0 || s.openStage == stage) && (!viralOnly || s.viral(today: today))
        }.sorted { (a: CrowdStartup, b: CrowdStartup) -> Bool in
            let va: Bool = a.viral(today: today), vb: Bool = b.viral(today: today)
            return va != vb ? va : a.createdDay > b.createdDay
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                header
                filters(trades)
                if shown.isEmpty {
                    EmptyState(glyph: Glyph.ventures, title: "No startup matches", message: "Change a filter, or come back when players have opened more.", centered: false)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { (n: Int, s: CrowdStartup) in
                            if n > 0 { Hairline() }
                            row(s, today: today)
                        }
                    }
                }
                holdings
            }
            .padding(.horizontal, Theme.Space.page).padding(.vertical, Theme.Space.m)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Startup market")
        .navigationBarTitleDisplayMode(.inline)
        .task { market.sync(store) }
        .centerSheet(item: $sheet, title: "", category: .medium, tone: .investment) { (s: StartupSheet) in
            switch s {
            case .found: FoundCrowdStartupSheet()
            case .invest(let id): InvestStartupSheet(startupID: id)
            case .buy(let id): BuySharesSheet(offerID: id)
            case .sell(let id): SellSharesSheet(startupID: id)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Startups funded by players").textStyle(.title).accessibilityAddTraits(.isHeader)
            Text("Players open a startup and other players put money in, in three stages. The money waits in escrow and goes to the startup when it reaches a milestone. Most startups fail.")
                .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
            Button("Open a startup") { sheet = .found }.buttonStyle(PrimaryButtonStyle(size: .compact))
                .accessibilityIdentifier("startup-market-found")
        }
    }

    private func filters(_ trades: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Picker("Trade", selection: $trade) { ForEach(trades, id: \.self) { (t: String) in Text(t).tag(t) } }.pickerStyle(.menu)
                Spacer(minLength: 0)
                Toggle(isOn: $viralOnly) {
                    HStack(spacing: Theme.Space.xxs) { ViralFlame(); Text("Viral").textStyle(.caption) }
                }
                .toggleStyle(.button)
            }
            SegmentedPill(items: [-1, 0, 1, 2], title: { (s: Int) -> String in s < 0 ? "Any stage" : CrowdStartupRules.stageNames[s] }, selection: $stage)
        }
        .padding(Theme.Space.s)
        .glassSurface()
    }

    @ViewBuilder private func row(_ s: CrowdStartup, today: Int) -> some View {
        if let e = store.engine { rowContent(s, today: today, cur: e.homeCurrency) }
    }

    private func rowContent(_ s: CrowdStartup, today: Int, cur: Currency) -> some View {
        let health = StartupText.health(s)
        return NavigationLink {
            StartupPageView(startupID: s.id).environment(\.outsidePalette, OutsidePalette.game)
        } label: {
            LedgerRow(leading: .thumb(ThumbSpec(kind: .trade, key: s.trade, glyph: Glyph.ventures, initials: s.name, shape: .square)),
                      title: s.name,
                      subtitle: "\(s.trade) \u{00B7} \(s.founderName) \u{00B7} \(CrowdStartupRules.recordWords(exits: s.founderExits, fails: s.founderFails))",
                      value: cur.tidyShort(s.plan.cost), valueNote: StartupText.stageName(s),
                      pill: health.0, pillTone: health.1, chevron: true, identifier: "startup-row-\(s.id)")
        }
        .buttonStyle(AcctPressStyle())
        .overlay(alignment: .topTrailing) { if s.viral(today: today) { ViralFlame().padding(.top, 6).padding(.trailing, 2) } }
    }

    @ViewBuilder private var holdings: some View {
        let mine: [CrowdHolding] = market.service.myHoldings()
        if !mine.isEmpty, let e = store.engine {
            LedgerSection("Your shares") {
                ForEach(Array(mine.enumerated()), id: \.element.id) { (n: Int, h: CrowdHolding) in
                    if n > 0 { Hairline() }
                    if let s = market.service.startup(h.startupID) {
                        let value: Double = CrowdStartupRules.fairPrice(s, percent: h.percent)
                        NavigationLink {
                            StartupPageView(startupID: s.id).environment(\.outsidePalette, OutsidePalette.game)
                        } label: {
                            LedgerRow(title: s.name, subtitle: String(format: "%.1f%% of the startup", h.percent), gain: s.status == .failed ? -h.paid : value - h.paid,
                                      gainFormat: { (v: Double) -> String in e.homeCurrency.tidyShort(abs(v)) }, chevron: true)
                        }
                        .buttonStyle(AcctPressStyle())
                    }
                }
            }
        }
    }
}

/// One startup: the plan, where it stands, how much is raised (in words and a bar), the founder's record, the escrow milestones and the
/// player's own holding. Investing, buying second-hand and selling open from here.
struct StartupPageView: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var market = StartupMarketStore.shared
    var startupID: String
    @State private var sheet: StartupSheet?

    var body: some View {
        ScrollView {
            if let s = market.service.startup(startupID), let e = store.engine {
                content(s, e)
                    .padding(.horizontal, Theme.Space.page).padding(.vertical, Theme.Space.m)
                    .frame(maxWidth: 640).frame(maxWidth: .infinity)
            } else {
                Text("This startup is gone.").textStyle(.body).padding()
            }
        }
        .scrollIndicators(.hidden)
        .navigationTitle(market.service.startup(startupID)?.name ?? "Startup")
        .navigationBarTitleDisplayMode(.inline)
        .centerSheet(item: $sheet, title: "", category: .medium, tone: .investment) { (s: StartupSheet) in
            switch s {
            case .found: FoundCrowdStartupSheet()
            case .invest(let id): InvestStartupSheet(startupID: id)
            case .buy(let id): BuySharesSheet(offerID: id)
            case .sell(let id): SellSharesSheet(startupID: id)
            }
        }
    }

    @ViewBuilder private func content(_ s: CrowdStartup, _ e: GameEngine) -> some View {
        let cur: Currency = e.homeCurrency
        let today: Int = StartupMarketStore.today(e)
        let mine: Bool = s.founderID == CrowdStartups.me
        let hold: CrowdHolding? = market.service.myHoldings().first { $0.startupID == s.id }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(spacing: Theme.Space.xs) {
                    Text(s.name).textStyle(.title).accessibilityAddTraits(.isHeader)
                    if s.viral(today: today) { ViralFlame() }
                }
                Text("\(s.trade) \u{00B7} \(StartupText.stageName(s))").textStyle(.caption, tint: Theme.inkFaint)
                if !s.pitch.isEmpty { Text(s.pitch).textStyle(.body).fixedSize(horizontal: false, vertical: true) }
            }
            CardSection("The plan") {
                PlanRows(startup: s, cur: cur)
            }
            CardSection("Raised so far") {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(StartupText.raiseWords(s)).textStyle(.body)
                    ProgressLine(fraction: StartupText.fraction(s), tint: Theme.accent)
                    Text(s.escrowHeld > 0 ? "\(cur.tidyShort(s.escrowHeld)) is waiting in escrow." : "Nothing is waiting in escrow.").textStyle(.caption, tint: Theme.inkFaint)
                    if s.viral(today: today) {
                        HStack(spacing: Theme.Space.xxs) { ViralFlame(); Text("Many players invested in a short time. More people see it; that is all it changes.").textStyle(.caption, tint: Theme.inkFaint) }
                    }
                }
            }
            CardSection("The founder") {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(s.founderName).textStyle(.body)
                    Text(CrowdStartupRules.recordWords(exits: s.founderExits, fails: s.founderFails)).textStyle(.caption, tint: Theme.inkFaint)
                    Text("Puts in \(cur.tidyShort(s.plan.founderPutIn)) of their own money").textStyle(.caption, tint: Theme.inkFaint)
                }
            }
            CardSection("Escrow milestones") { milestones(s, cur) }
            if let h = hold { holding(s, h, cur, today) }
            actions(s, mine: mine, held: hold != nil, today: today, e)
        }
    }

    private func milestones(_ s: CrowdStartup, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(0..<3, id: \.self) { (i: Int) in
                let done: Bool = s.milestones > i
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? Theme.gain : Theme.inkFaint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(CrowdStartupRules.milestoneNames[i]).textStyle(.body)
                        Text("Releases \(cur.tidyShort(CrowdStartupRules.stageTarget(s.plan, stage: i))) \u{00B7} \(cur.tidyShort(s.raised(stage: i))) in so far")
                            .textStyle(.caption, tint: Theme.inkFaint)
                    }
                }
            }
            Text("If a stage does not reach its milestone in \(CrowdStartupRules.stageDeadlineWeeks) weeks, or the startup fails first, the money in escrow goes back to the investors.")
                .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func holding(_ s: CrowdStartup, _ h: CrowdHolding, _ cur: Currency, _ today: Int) -> some View {
        let value: Double = s.status == .failed ? 0 : CrowdStartupRules.fairPrice(s, percent: h.percent)
        let locked: Bool = today < h.lockedUntil()
        let inEscrow: Double = s.investments.filter { $0.investorID == CrowdStartups.me && !$0.released && !$0.refunded }.reduce(0) { $0 + $1.amount }
        return CardSection("Your holding") {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                LedgerRow(title: String(format: "%.1f%% of %@", h.percent, s.name), subtitle: "Paid \(cur.tidyShort(h.paid))", gain: value - h.paid,
                          gainFormat: { (v: Double) -> String in cur.tidyShort(abs(v)) })
                Text("Worth about \(cur.tidyShort(value)) by assets and recent profit.").textStyle(.caption, tint: Theme.inkFaint)
                if inEscrow > 0 { Text("\(cur.tidyShort(inEscrow)) of it is still in escrow.").textStyle(.caption, tint: Theme.inkFaint) }
                Text(locked ? "Locked: you can resell in \(max(1, (h.lockedUntil() - today + 6) / 7)) game weeks." : "The lock-up is over; you can resell.").textStyle(.caption, tint: locked ? Theme.warn : Theme.inkFaint)
            }
        }
        .glassSurface()
    }

    @ViewBuilder private func actions(_ s: CrowdStartup, mine: Bool, held: Bool, today: Int, _ e: GameEngine) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if mine {
                Text("This is your startup. You cannot invest in it, and nobody linked to you can either.").textStyle(.caption, tint: Theme.inkFaint)
            } else {
                Button("Invest") { sheet = .invest(s.id) }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .disabled(s.openStage == nil).accessibilityIdentifier("startup-invest")
            }
            if held { Button("Sell shares") { sheet = .sell(s.id) }.buttonStyle(SmallOutlineButtonStyle()).accessibilityIdentifier("startup-sell") }
            let offers: [StartupShareOffer] = mine ? [] : market.service.offers(startupID: s.id)
            if !offers.isEmpty {
                Text("Shares for sale by other players").capsLabel(Theme.inkFaint).padding(.top, Theme.Space.s)
                ForEach(offers) { (o: StartupShareOffer) in
                    LedgerRow(title: String(format: "%.1f%% from %@", o.percent, o.sellerName), subtitle: "Price \(e.homeCurrency.tidyShort(o.price))",
                              pill: "Buy", pillTone: .good, chevron: true) { sheet = .buy(o.id) }
                }
            }
        }
    }
}

/// Plan cost, the founder's part, what investors are asked for, and what the price is built from.
struct PlanRows: View {
    var startup: CrowdStartup
    var cur: Currency

    var body: some View {
        let p: CrowdStartupRules.Plan = startup.plan
        VStack(alignment: .leading, spacing: PopupSpace.row) {
            PopupRow(label: "Plan cost", value: cur.tidyShort(p.cost))
            PopupRow(label: "The founder puts in", value: cur.tidyShort(p.founderPutIn))
            PopupRow(label: "Investors are asked for", value: cur.tidyShort(p.investorTarget))
            if let s = startup.openStage {
                PopupRow(label: "Stage \(s + 1): \(CrowdStartupRules.stageNames[s].lowercased())", value: cur.tidyShort(CrowdStartupRules.stageTarget(p, stage: s)))
                PopupRow(label: "Price of 1% now", value: cur.tidyShort(CrowdStartupRules.pricePerPercent(p, stage: s)))
            }
            Text("The price is set by a fixed rule: the plan cost times a multiple that grows with each stage. The founder cannot change it.").popupText(.caption)
        }
    }
}
