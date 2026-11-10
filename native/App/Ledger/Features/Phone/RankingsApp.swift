import SwiftUI
import GameCore
import Events
import Businesses
import Simulation

struct RankingsApp: View {
    @EnvironmentObject var store: GameStore
    enum Tab: String, CaseIterable, Hashable { case boards = "Leaderboards", fame = "Hall of Fame" }
    @State private var tab: Tab = .boards

    var body: some View {
        Group {
            if store.engine != nil {
                VStack(spacing: 0) {
                    SegmentedPill(items: Tab.allCases, title: { (t: Tab) -> String in t.rawValue }, selection: $tab,
                                  identifier: { (t: Tab) -> String in "rankings-tab-\(t.rawValue)" })
                        .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.xs)
                        .frame(maxWidth: 760).frame(maxWidth: .infinity)
                    switch tab {
                    case .boards: RankingsBoards()
                    case .fame: HallOfFameView()
                    }
                }
            } else {
                Color.clear
            }
        }
        .appScreen(title: "Rankings", subtitle: PhoneApp.rankings.subtitle)
        .accessibilityIdentifier("rankings-app")
    }
}

struct RankingsBoards: View {
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
                    Text(kind == .netWorth ? "Net worth counts companies you cannot sell in a day for less."
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
