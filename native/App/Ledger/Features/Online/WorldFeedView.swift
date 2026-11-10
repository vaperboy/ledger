import SwiftUI
import GameCore
import Events
import Businesses
import Simulation

struct WorldFeedView: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @ObservedObject private var feed: NewsFeedStore = NewsFeedStore.shared
    @State private var events: [PlayerEvent] = []
    @State private var overview: FriendsOverview?
    @State private var loaded = false
    @State private var venturePicker = false
    @State private var ventureCompany: Int?
    @State private var ventureOpen = false

    private let session = StoreSession.shared

    private struct Item: Identifiable {
        var id: String
        var glyph: String
        var title: String
        var note: String
        var sort: Double
    }

    var body: some View {
        PhonePageScroll(spacing: Theme.Space.l) {
            needsYou
            worldGroup
            friendsGroup
            togetherGroup
            if !OnlineConfig.useServer {
                Text("This build uses a stand-in server, so other players are samples. Real events appear here once the live server is on.")
                    .textStyle(.caption).fixedSize(horizontal: false, vertical: true).padding(.horizontal, Theme.Space.m)
            }
            if !online.isSignedIn { AccountSettingsGroup() }
        }
        .appScreen(title: "World", subtitle: "What is happening around you")
        .task(id: online.isSignedIn) { await load() }
        .centerSheet(isPresented: $venturePicker, title: "Start a company together") { ventureChoices }
        .centerSheet(isPresented: $ventureOpen, title: "Invite a friend", size: .tall) {
            JVInviteSheet(companyID: ventureCompany ?? 0).environmentObject(store).environment(online)
        }
    }

    private var needsItems: [Item] {
        var out: [Item] = []
        if let o = overview, !o.incoming.isEmpty {
            let n: Int = o.incoming.count
            out.append(Item(id: "req", glyph: Glyph.people, title: n == 1 ? "1 friend request" : "\(n) friend requests", note: "Open Friends to answer.", sort: 0))
        }
        if let snap = session.auctions {
            for a in snap.auctions where a.isLive(at: snap.now) && a.secondsLeft(at: snap.now) < 86_400 && (a.seller == GoldVault.meID || a.leader == GoldVault.meID) {
                let name: String = ArtifactCatalog.def(a.item.defID)?.name ?? "A piece"
                let left: String = Self.left(a.secondsLeft(at: snap.now))
                let line: String = a.seller == GoldVault.meID ? "Your auction for \(name) ends in \(left)." : "You lead the auction for \(name), ending in \(left)."
                out.append(Item(id: "auc.\(a.id)", glyph: Glyph.market, title: line, note: "Now at \(a.currentPrice) gold.", sort: 1 + a.secondsLeft(at: snap.now)))
            }
        }
        return Array(out.sorted { $0.sort < $1.sort }.prefix(3))
    }

    @ViewBuilder private var needsYou: some View {
        let list: [Item] = needsItems
        if !list.isEmpty {
            OnlineGroup(title: "Worth a look") {
                ForEach(Array(list.enumerated()), id: \.element.id) { (i: Int, it: Item) in
                    if i > 0 { Hairline() }
                    OnlineLine(glyph: it.glyph, title: it.title, note: it.note)
                }
            }
        }
    }

    private var feedItems: [Item] {
        var out: [Item] = []
        for e in events {
            guard let text = PlayerNewsRules.sentence(e, namesVisible: feed.service.isFriend(e.playerID)) else { continue }
            out.append(Item(id: e.id, glyph: Glyph.news, title: text, note: Self.ago(day: e.day), sort: Double(e.day)))
        }
        for a in online.friendActivity.activity {
            out.append(Item(id: "fa." + a.id, glyph: Glyph.people, title: a.sentence, note: Self.ago(seen: a.at), sort: a.at / 86_400))
        }
        for (i, n) in session.notes.enumerated() {
            out.append(Item(id: "note.\(i)", glyph: Glyph.market, title: n, note: "Auctions", sort: Double(Self.today) + 0.5))
        }
        if let e = store.engine {
            for t in TrophyList.unlocked(e).prefix(2) {
                guard let w = t.reachedWeek else { continue }
                out.append(Item(id: "tr.\(t.id)", glyph: Glyph.achievements, title: "You earned a trophy: \(t.name).", note: GameCalendar.dateString(week: w), sort: Double(Self.today) - 1))
            }
        }
        return Array(out.sorted { $0.sort > $1.sort }.prefix(12))
    }

    private var worldGroup: some View {
        let list: [Item] = feedItems
        return OnlineGroup(title: "Around the world", footer: worldFooter) {
            if list.isEmpty {
                Text(loaded ? "Nothing yet. When other players open branches, join clubs or finish seasons, and when your friends play, it shows up here. Nothing on this page is invented." : "Loading")
                    .textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true).padding(.vertical, Theme.Space.m)
            } else {
                ForEach(Array(list.enumerated()), id: \.element.id) { (i: Int, it: Item) in
                    if i > 0 { Hairline() }
                    OnlineLine(glyph: it.glyph, title: it.title, note: it.note)
                }
            }
        }
    }

    private var worldFooter: String {
        let base: String = "Only public events, and friends' events as their privacy allows."
        guard let p = online.pulse else { return base }
        return "\(p.online) of \(p.players) players are online now. " + base
    }

    private func lastSeen(_ p: PlayerProfile) -> String {
        if let presence = online.friendActivity.presence.first(where: { (x: FriendPresence) -> Bool in x.playerID == p.id }) {
            if presence.online { return "Online now" }
            if let t = presence.lastSeen { return "Last active " + Self.ago(seen: t).lowercased() }
        }
        guard let d = events.filter({ $0.playerID == p.id }).map({ $0.day }).max() else { return "No activity yet" }
        return "Last active " + Self.ago(day: d).lowercased()
    }

    private var inviteText: String {
        let code: String = online.profile?.code ?? ""
        return code.isEmpty ? "Come and play Ledger with me." : InviteLink.message(code: code)
    }

    private var friendsGroup: some View {
        let friends: [PlayerProfile] = overview?.friends ?? []
        return OnlineGroup(title: "Friends", footer: online.isSignedIn ? "" : "Link an account to add friends.") {
            if friends.isEmpty {
                Text(online.isSignedIn ? "No friends yet. Invite one below and their activity will show here." : "Friends and their activity show here once you link an account.")
                    .textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true).padding(.vertical, Theme.Space.m)
            } else {
                ForEach(Array(friends.enumerated()), id: \.element.id) { (i: Int, p: PlayerProfile) in
                    if i > 0 { Hairline() }
                    NavigationLink { PlayerProfileView(playerID: p.id) } label: {
                        HStack(spacing: Theme.Space.m) {
                            PlayerAvatar(player: p, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.displayName).textStyle(.headline).lineLimit(1)
                                Text(lastSeen(p)).textStyle(.caption).lineLimit(1)
                            }
                            Spacer(minLength: Theme.Space.s)
                            LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
                        }
                        .padding(.vertical, Theme.Space.s).frame(minHeight: 56).contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            Hairline()
            ShareLink(item: inviteText) {
                OnlineLine(glyph: Glyph.share, title: "Invite a friend", note: "Send your code with the share sheet", chevron: true)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("world-invite")
            Hairline()
            NavigationLink { FriendsApp() } label: {
                OnlineLine(glyph: Glyph.people, title: "Open Friends", note: "Search, requests and your code", chevron: true)
            }
            .buttonStyle(PressableStyle())
        }
    }

    private var eligible: [Company] {
        guard let e = store.engine else { return [] }
        return e.state.companies.filter { e.jvCanStart(companyID: $0.id) }
    }

    private var togetherGroup: some View {
        OnlineGroup(title: "Together", footer: "Each friend gets a private price of their own, and big decisions go to a vote by shares.") {
            Button { Haptics.tap(); venturePicker = true } label: {
                OnlineLine(glyph: Glyph.group, title: "Start a company together", note: "Own one of your companies with friends", chevron: true)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("world-together")
        }
    }

    @ViewBuilder private var ventureChoices: some View {
        let list: [Company] = eligible
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if list.isEmpty {
                Text("Open a company first. Then you can bring friends in as partners from its Partners section.").popupText(.body)
            } else {
                Text("Pick the company to share").popupText(.caption)
                ForEach(list, id: \.id) { (c: Company) in
                    ChoiceCard(title: c.name, selected: false) {
                        ventureCompany = c.id
                        venturePicker = false
                        StorePurchase.afterPopup { ventureOpen = true }
                    }
                }
            }
        }
    }

    private func load() async {
        events = await feed.service.events(now: Date())
        if online.isSignedIn {
            overview = try? await online.service.friends()
            await online.syncWorld(store: store)
        } else { overview = nil }
        await session.refreshAuctions()
        loaded = true
    }

    private static var today: Int { Int(Date().timeIntervalSince1970 / 86_400) }

    private static func ago(day: Int) -> String {
        let d: Int = max(0, today - day)
        if d == 0 { return "Today" }
        if d == 1 { return "Yesterday" }
        return "\(d) days ago"
    }

    private static func ago(seen: Double) -> String {
        let s: Double = max(0, Date().timeIntervalSince1970 - seen)
        if s < 3_600 { return "\(max(1, Int(s / 60))) min ago" }
        if s < 86_400 { let h: Int = Int(s / 3_600); return h == 1 ? "1 hour ago" : "\(h) hours ago" }
        let d: Int = Int(s / 86_400)
        return d == 1 ? "Yesterday" : "\(d) days ago"
    }

    private static func left(_ seconds: Double) -> String {
        let m: Int = Int(seconds / 60)
        if m < 60 { return "\(max(1, m)) minutes" }
        let h: Int = m / 60
        return h == 1 ? "1 hour" : "\(h) hours"
    }
}
