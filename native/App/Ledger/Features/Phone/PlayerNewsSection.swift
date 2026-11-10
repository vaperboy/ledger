import SwiftUI
import GameCore
import Events
import Businesses
import Simulation

struct PlayerNewsSection: View {
    var engine: GameEngine
    @Environment(\.outsidePalette) private var P
    @Environment(OnlineSession.self) private var online
    @EnvironmentObject private var store: GameStore
    @State private var requests = 0
    private let session = StoreSession.shared
    @ObservedObject private var feed: NewsFeedStore = NewsFeedStore.shared
    @State private var events: [PlayerEvent] = []
    @State private var filter: PlayerNewsFilter = .everyone
    @State private var loaded = false

    private var viewerTrades: Set<String> {
        Set(engine.state.companies.filter { $0.status == .open && $0.type != "hold" }.map { engine.tradeName($0) })
    }

    private var rows: [(event: PlayerEvent, text: String)] {
        events.compactMap { (e: PlayerEvent) -> (event: PlayerEvent, text: String)? in
            let friend: Bool = feed.service.isFriend(e.playerID)
            guard PlayerNewsRules.matches(e, filter: filter, viewerIsFriend: friend, viewerTrades: viewerTrades, viewerCountry: engine.state.homeCountryCode),
                  let text = PlayerNewsRules.sentence(e, namesVisible: friend) else { return nil }
            return (e, text)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Source: public events from other players. Nothing here comes from a player who keeps their profile private.")
                .textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true).padding(.bottom, 12)
            worthALook
            filterBar
            let list = rows
            if list.isEmpty {
                Text(loaded ? emptyText : "Loading").textStyle(.body, tint: P.inkSoft)
                    .frame(maxWidth: .infinity).padding(.vertical, 36)
            } else {
                ForEach(Array(list.enumerated()), id: \.element.event.id) { (i: Int, r: (event: PlayerEvent, text: String)) in
                    if i > 0 { Rectangle().fill(P.hairline).frame(height: 1) }
                    row(r.event, r.text)
                }
            }
            if filter == .everyone || filter == .friends { friendActivity }
            footer
        }
        .task(id: online.isSignedIn) { await load() }
        .accessibilityIdentifier("news-players")
    }

    private var emptyText: String {
        switch filter {
        case .everyone: return "No player news yet."
        case .friends: return "Nothing from your friends yet."
        case .myTrade: return "Nothing from your trade yet."
        case .myCountry: return "Nothing from your country yet."
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(PlayerNewsFilter.allCases, id: \.self) { (f: PlayerNewsFilter) in
                    Button { filter = f } label: {
                        Text(f.title).textStyle(.caption, tint: filter == f ? P.accentInk : P.inkSoft, weight: .semibold)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(filter == f ? P.accent : Color.clear))
                            .overlay(Capsule().stroke(filter == f ? Color.clear : P.lineStrong, lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("news-filter-\(f.rawValue)")
                    .accessibilityAddTraits(filter == f ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .padding(.bottom, 8)
    }

    private func row(_ e: PlayerEvent, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(kicker(e.kind).uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(1).foregroundStyle(P.accent)
                Text(OnlineCountry.name(e.countryCode)).textStyle(.caption, tint: P.inkFaint)
                Spacer(minLength: 0)
                Text(age(e.day)).textStyle(.caption, tint: P.inkFaint)
            }
            Text(text).font(.serifTitle(16)).foregroundStyle(P.ink).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func kicker(_ k: PlayerEventKind) -> String {
        switch k {
        case .branchMilestone: return "Growth"
        case .wentViral: return "Startup"
        case .supplierMilestone: return "Supply"
        case .acquisition: return "Deal"
        case .newAssociation: return "Association"
        case .seasonMilestone: return "Season"
        }
    }

    private func age(_ day: Int) -> String {
        let today: Int = Int(Date().timeIntervalSince1970 / 86_400)
        let d: Int = max(0, today - day)
        return d == 0 ? "Today" : d == 1 ? "Yesterday" : "\(d) days ago"
    }

    @ViewBuilder private var worthALook: some View {
        let lines: [String] = alerts
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { (l: String) in
                    Text(l).textStyle(.caption, tint: P.accent, weight: .semibold).fixedSize(horizontal: false, vertical: true)
                }
                if requests > 0 {
                    Button { store.openProfile() } label: { Text("Open your profile to answer").textStyle(.caption, tint: P.accent) }.buttonStyle(PressableStyle())
                }
            }
            .padding(.bottom, 10)
        }
    }

    private var alerts: [String] {
        var out: [String] = []
        if requests > 0 { out.append(requests == 1 ? "1 friend request is waiting." : "\(requests) friend requests are waiting.") }
        if let snap = session.auctions {
            for a in snap.auctions where a.isLive(at: snap.now) && a.secondsLeft(at: snap.now) < 86_400 && (a.seller == GoldVault.meID || a.leader == GoldVault.meID) {
                let name: String = ArtifactCatalog.def(a.item.defID)?.name ?? "A piece"
                out.append(a.seller == GoldVault.meID ? "Your auction for \(name) ends within a day." : "You lead the auction for \(name), ending within a day.")
            }
        }
        return Array(out.prefix(3))
    }

    @ViewBuilder private var friendActivity: some View {
        ForEach(Array(online.friendActivity.activity.prefix(8).enumerated()), id: \.element.id) { (i: Int, a: FriendActivityItem) in
            Rectangle().fill(P.hairline).frame(height: 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("FRIENDS").font(.system(size: 9.5, weight: .semibold)).tracking(1).foregroundStyle(P.accent)
                Text(a.sentence).font(.serifTitle(16)).foregroundStyle(P.ink).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private var footer: some View {
        var text: String = "Only public events, and friends' events as their privacy allows."
        if let p = online.pulse { text = "\(p.online) of \(p.players) players are online now. " + text }
        if !OnlineConfig.useServer { text += " This build uses a stand-in server, so other players are samples." }
        return Text(text).textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
    }

    private func load() async {
        events = await feed.service.events(now: Date())
        if online.isSignedIn {
            requests = (try? await online.service.friends().incoming.count) ?? 0
            await online.syncWorld(store: store)
        } else { requests = 0 }
        await session.refreshAuctions()
        loaded = true
    }
}
