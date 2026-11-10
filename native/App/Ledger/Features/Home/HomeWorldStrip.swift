import SwiftUI
import GameCore
import Events
import Businesses
import Simulation

struct HomeWorldStrip: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online

    private enum Target { case world, market, auctions, ventures }

    private struct Item: Identifiable {
        var id: String
        var glyph: String
        var text: String
        var tag: String
        var tint: Color
        var target: Target
    }

    @State private var items: [Item] = []
    @State private var loaded = false
    private let session = StoreSession.shared

    private var tick: Int {
        guard let e = store.engine else { return 0 }
        return e.state.week * 7 + e.state.day
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.s) {
                Text("World").textStyle(.label, tint: Theme.inkFaint)
                Circle().fill(Theme.gain).frame(width: 6, height: 6).accessibilityHidden(true)
                Text("Live").textStyle(.caption, tint: Theme.inkFaint)
                Spacer(minLength: Theme.Space.s)
                Button { Haptics.tap(); store.openApp(.news, request: .newsPlayers) } label: {
                    HStack(spacing: Theme.Space.xxs) {
                        Text("All").textStyle(.caption, tint: Theme.inkSoft)
                        LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
                    }
                    .frame(minHeight: 28).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Open the player news")
            }
            if items.isEmpty {
                quiet
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.s) {
                        ForEach(items) { (it: Item) in chip(it) }
                    }
                    .padding(.vertical, 2)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
        }
        .accessibilityIdentifier("home-world")
        .task(id: "\(tick)-\(online.isSignedIn)") { await load() }
    }

    private var quiet: some View {
        Button { Haptics.tap(); store.openApp(.news, request: .newsPlayers) } label: {
            HStack(spacing: Theme.Space.s) {
                LedgerGlyph(glyph: Glyph.world, size: Theme.Icon.small, tint: Theme.inkFaint)
                Text(loaded ? "Quiet for now. Other players' news, auctions and offers show here." : "Looking around")
                    .textStyle(.caption, tint: Theme.inkSoft).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder private func chip(_ it: Item) -> some View {
        switch it.target {
        case .world:
            Button { Haptics.tap(); store.openApp(.news, request: .newsPlayers) } label: { chipBody(it) }.buttonStyle(PressableStyle())
        case .market:
            Button { Haptics.tap(); store.openMarket() } label: { chipBody(it) }.buttonStyle(PressableStyle())
        case .auctions:
            Button { Haptics.tap(); store.openApp(.auctions) } label: { chipBody(it) }.buttonStyle(PressableStyle())
        case .ventures:
            Button { Haptics.tap(); store.openVentures() } label: { chipBody(it) }.buttonStyle(PressableStyle())
        }
    }

    private func chipBody(_ it: Item) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            LedgerGlyph(glyph: it.glyph, size: Theme.Icon.small, tint: it.tint).padding(.top, 2)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(it.text).textStyle(.caption, tint: Theme.ink).lineLimit(2).multilineTextAlignment(.leading)
                Text(it.tag).textStyle(.caption, tint: Theme.inkFaint).lineLimit(1)
            }
        }
        .frame(width: 210, alignment: .leading)
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
        .glassSurface()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        let events: [PlayerEvent] = await NewsFeedStore.shared.service.events(now: Date())
        await session.refreshAuctions()
        guard let e = store.engine else { return }
        items = build(e, events)
        loaded = true
    }

    private func build(_ e: GameEngine, _ events: [PlayerEvent]) -> [Item] {
        var offers: [Item] = []
        let f: VenturesFigures = VenturesFigures(e)
        let waiting: Int = f.offers + f.pitches + f.fundOffers + (f.bigOffer != nil ? 1 : 0)
        if waiting > 0 {
            offers.append(Item(id: "offers", glyph: Glyph.ventures, text: waiting == 1 ? "A new offer is waiting for you." : "\(waiting) new offers are waiting for you.",
                               tag: "Ventures", tint: Theme.accent, target: .ventures))
        }
        var auctions: [Item] = []
        if let snap = session.auctions {
            let soon = snap.auctions.filter { (a: Auction) -> Bool in a.isLive(at: snap.now) && a.secondsLeft(at: snap.now) < 86_400 }
                .sorted { (a: Auction, b: Auction) -> Bool in a.secondsLeft(at: snap.now) < b.secondsLeft(at: snap.now) }
            for a in soon.prefix(1) {
                let name: String = ArtifactCatalog.def(a.item.defID)?.name ?? "A piece"
                let mine: Bool = a.seller == GoldVault.meID || a.leader == GoldVault.meID
                auctions.append(Item(id: "auc.\(a.id)", glyph: Glyph.market, text: "\(mine ? "Your auction for" : "An auction for") \(name) ends in \(Self.left(a.secondsLeft(at: snap.now))).",
                                     tag: "Auctions · now at \(a.currentPrice) gold", tint: Theme.warn, target: .auctions))
            }
        }
        let market: [Item] = e.marketEvents(limit: 2).map { (m: MarketEvent) -> Item in
            Item(id: "mk.\(m.id)", glyph: Glyph.market, text: m.title.tidyMoney, tag: "Market", tint: m.tone == "good" ? Theme.gain : (m.tone == "bad" ? Theme.loss : Theme.inkSoft), target: .market)
        }
        var people: [Item] = []
        for ev in events {
            let friend: Bool = NewsFeedStore.shared.service.isFriend(ev.playerID)
            guard let text = PlayerNewsRules.sentence(ev, namesVisible: friend) else { continue }
            people.append(Item(id: ev.id, glyph: friend ? Glyph.people : Glyph.news, text: text, tag: (friend ? "Friend" : "Player") + " · " + Self.ago(day: ev.day), tint: Theme.accent, target: .world))
            if people.count == 3 { break }
        }
        return offers + auctions + Array(market.prefix(1)) + Array(people.prefix(1)) + Array(market.dropFirst()) + Array(people.dropFirst())
    }

    private static var today: Int { Int(Date().timeIntervalSince1970 / 86_400) }

    private static func ago(day: Int) -> String {
        let d: Int = max(0, today - day)
        if d == 0 { return "today" }
        if d == 1 { return "yesterday" }
        return "\(d) days ago"
    }

    private static func left(_ seconds: Double) -> String {
        let m: Int = Int(seconds / 60)
        if m < 60 { return "\(max(1, m)) minutes" }
        let h: Int = m / 60
        return h == 1 ? "1 hour" : "\(h) hours"
    }
}
