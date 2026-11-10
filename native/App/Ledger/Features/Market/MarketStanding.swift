import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct MarketStandingPage: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @State private var part: Part = .worth

    enum Part: String, CaseIterable, Hashable { case worth = "Net worth", boards = "Leaderboards" }

    var body: some View {
        if store.engine != nil {
            VStack(spacing: 0) {
                SegmentedPill(items: Part.allCases, title: { (p: Part) -> String in p.rawValue }, selection: $part,
                              identifier: { (p: Part) -> String in "standing-part-\(p.rawValue)" })
                    .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
                switch part {
                case .worth: MarketWealthPart()
                case .boards: MarketBoardsPart()
                }
            }
        }
    }
}

struct MarketWealthPart: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P

    var body: some View {
        if let e = store.engine {
            let cur: Currency = e.homeCurrency
            let w: WealthStatement = store.memo("mk.wealth") { $0.wealth } ?? e.wealth
            let assets: [WealthLine] = w.lines.filter { (l: WealthLine) -> Bool in l.amount > 0 }
            let takes: [WealthLine] = w.lines.filter { (l: WealthLine) -> Bool in l.amount < 0 }
            let top: Double = max(1, assets.reduce(0) { (a: Double, l: WealthLine) -> Double in a + l.amount })
            ScrollScreen(spacing: Theme.Space.m, top: Theme.Space.s) {
                hero(w, cur)
                if !assets.isEmpty { composition(assets, top, cur) }
                liquid(w)
                MarketLabel(title: "What it is made of")
                VStack(spacing: 0) {
                    ForEach(Array(w.lines.enumerated()), id: \.element.id) { (pair: (offset: Int, element: WealthLine)) in
                        if pair.offset > 0 { Hairline() }
                        line(pair.element, index: pair.offset, assets: assets, top: top, cur)
                    }
                }
                if !takes.isEmpty { Text("Loans and tax come off the total.").textStyle(.caption) }
                if w.discount > 0.5 {
                    ExchangeCard {
                        Text("Why it is not the number on Home").textStyle(.label, tint: P.inkFaint)
                        Text(discountWords(w, cur)).textStyle(.body).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func discountWords(_ w: WealthStatement, _ cur: Currency) -> String {
        let a: String = "The rankings count what you could really get. Companies you run and stakes you hold cannot be sold in a day, so they count for less: "
        let b: String = cur.tidyShort(w.discount) + " less than their paper value. Before that, you are worth " + cur.tidyShort(w.plain.total) + "."
        return a + b
    }

    private func hero(_ w: WealthStatement, _ cur: Currency) -> some View {
        let series: [Double] = store.netWorthSeriesNow(days: 90)
        return MarketHero(label: "Net worth", value: cur.tidyShort(w.total), context: w.summary, series: series,
                          seriesTint: (series.last ?? 0) >= (series.first ?? 0) ? P.gain : P.loss, identifier: "wealth-hero")
    }

    private func composition(_ assets: [WealthLine], _ total: Double, _ cur: Currency) -> some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(assets.enumerated()), id: \.element.id) { (pair: (offset: Int, element: WealthLine)) in
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(swatch(pair.offset))
                        .frame(width: max(4, geo.size.width * CGFloat(pair.element.amount / total) - 2))
                }
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    private func swatch(_ index: Int) -> Color { P.accent.opacity(max(0.22, 1 - 0.17 * Double(index))) }

    private func liquid(_ w: WealthStatement) -> some View {
        ProgressLine(fraction: w.liquidShare, tint: P.gain, label: "Money and shares you could sell this week", value: Currency.percent(w.liquidShare, decimals: 0), height: 6)
    }

    private func line(_ l: WealthLine, index: Int, assets: [WealthLine], top: Double, _ cur: Currency) -> some View {
        let at: Int? = assets.firstIndex { (a: WealthLine) -> Bool in a.id == l.id }
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                if let at { RoundedRectangle(cornerRadius: 2, style: .continuous).fill(swatch(at)).frame(width: 10, height: 10) }
                Text(l.title.tidyText).textStyle(.headline).lineLimit(2)
                Spacer(minLength: Theme.Space.s)
                Text((l.amount < 0 ? "\u{2212}" : "") + cur.tidyShort(abs(l.amount))).textStyle(.headline, tint: l.amount < 0 ? P.loss : nil, numeric: true)
            }
            if !l.words.isEmpty { Text(l.words.tidyText).textStyle(.caption).fixedSize(horizontal: false, vertical: true) }
            if l.amount > 0 { ProgressLine(fraction: l.amount / top, tint: P.accent.opacity(0.7), height: 2) }
        }
        .padding(.vertical, Theme.Space.m)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("wealth-line-\(l.id)")
    }
}

struct MarketBoardsPart: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @Environment(\.outsidePalette) private var P
    @State private var kind: LeaderboardKind = .netWorth
    @State private var others: [LeaderboardSubmission] = []
    @State private var loaded = false

    private static let service: any LeaderboardService = LeaderboardBackend.make()

    var body: some View {
        if let e = store.engine {
            let cur: Currency = e.homeCurrency
            let me: LeaderboardSubmission = e.leaderboardSubmission(playerID: online.profile?.id ?? "me")
            let view: LeaderboardView = Leaderboards.view(kind, me: me, others: others)
            ScrollScreen(spacing: Theme.Space.m, top: Theme.Space.s) {
                SegmentedPill(items: LeaderboardKind.allCases, title: { (k: LeaderboardKind) -> String in k == .netWorth ? "Net worth" : "Trading result" },
                              selection: $kind, identifier: { (k: LeaderboardKind) -> String in "board-kind-\(k.rawValue)" })
                hero(view, cur)
                if loaded {
                    let top: Double = max(1, view.top.map { (x: LeaderboardEntry) -> Double in x.value }.max() ?? 1)
                    MarketLabel(title: "Top \(view.top.count)")
                    rows(view.top, top, cur)
                    if !view.around.isEmpty {
                        MarketLabel(title: "Around you")
                        rows(view.around, top, cur)
                    } else if let y = view.you, y.rank <= view.top.count {
                        Text("You are in the top \(view.top.count).").textStyle(.caption)
                    }
                    Text(kind == .netWorth ? "Net worth is counted as in the breakdown: companies you cannot sell in a day count for less."
                                           : "Trading result is what you made on the exchange: shares sold and shares still held, fees included.")
                        .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                } else {
                    ProgressView().tint(P.inkSoft).frame(maxWidth: .infinity).padding(.top, Theme.Space.xl)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if loaded, let y = view.you { yourRow(y, view, cur) }
            }
            .task(id: e.state.week) { await load(me, e) }
        }
    }

    private func hero(_ v: LeaderboardView, _ cur: Currency) -> some View {
        let value: String = v.you.map { (y: LeaderboardEntry) -> String in "#\(y.rank)" } ?? "Not placed"
        var context: String = ""
        if let y = v.you { context = (kind == .netWorth ? cur.tidyShort(y.value) : MarketFormat.money(y.value, cur)) + " \u{00B7} \(v.count) players" }
        return MarketHero(label: kind == .netWorth ? "Your place by net worth" : "Your place by trading result", value: loaded ? value : "\u{2026}", context: loaded ? context : "",
                          identifier: "board-hero")
    }

    private func rows(_ list: [LeaderboardEntry], _ top: Double, _ cur: Currency) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { (pair: (offset: Int, element: LeaderboardEntry)) in
                if pair.offset > 0 { Hairline().padding(.leading, 44) }
                row(pair.element, top, cur)
            }
        }
    }

    private func row(_ x: LeaderboardEntry, _ top: Double, _ cur: Currency) -> some View {
        let text: String = kind == .netWorth ? cur.tidyShort(x.value) : MarketFormat.money(x.value, cur)
        return HStack(spacing: Theme.Space.m) {
            Text("\(x.rank)").textStyle(.figure, tint: x.isYou ? P.accent : P.inkSoft, numeric: true).frame(width: 36, alignment: .leading)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(x.isYou ? "You" : x.name).textStyle(.headline, tint: x.isYou ? P.accent : nil).lineLimit(1)
                    Spacer(minLength: Theme.Space.s)
                    Text(text).textStyle(.headline, tint: kind == .tradingResult ? P.change(x.value) : nil, numeric: true).lineLimit(1).minimumScaleFactor(0.7)
                }
                ProgressLine(fraction: max(0, min(1, x.value / top)), tint: x.isYou ? P.accent : P.inkFaint.opacity(0.6), height: 3)
            }
        }
        .padding(.vertical, Theme.Space.m)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(x.isYou ? "board-you" : "board-row-\(x.rank)")
    }

    private func yourRow(_ y: LeaderboardEntry, _ v: LeaderboardView, _ cur: Currency) -> some View {
        let text: String = kind == .netWorth ? cur.tidyShort(y.value) : MarketFormat.money(y.value, cur)
        return HStack(spacing: Theme.Space.m) {
            Text("\(y.rank)").textStyle(.figure, tint: P.accent, numeric: true)
            Text("You").textStyle(.headline, tint: P.accent)
            Spacer(minLength: Theme.Space.s)
            Text(text).textStyle(.headline, numeric: true)
        }
        .padding(.horizontal, Theme.Space.page).padding(.vertical, Theme.Space.m)
        .frame(maxWidth: .infinity)
        .background(P.surfaceRaised.opacity(0.98))
        .overlay(alignment: .top) { Hairline() }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("board-your-row")
    }

    private func load(_ me: LeaderboardSubmission, _ e: GameEngine) async {
        await Self.service.publish(me)
        let real: [LeaderboardSubmission] = await Self.service.submissions().filter { (s: LeaderboardSubmission) -> Bool in s.playerID != me.playerID }
        let scale: Double = max(100_000, e.richListStanding.hundredth)
        let rivals: [LeaderboardSubmission] = BoardRivals.fill(template: me, real: real, scale: scale, week: e.state.week, seed: e.state.seed, taken: [me.name])
        others = real + rivals
        loaded = true
    }
}
