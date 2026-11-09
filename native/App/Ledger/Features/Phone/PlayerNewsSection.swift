import SwiftUI
import GameCore
import Businesses
import Simulation

/// The Players part of the News app: what real players did, in short plain sentences made from each event's own facts, with a filter
/// (Everyone, Friends, My trade, My country). Private players never appear; a Friends-level player appears to their friends only, and only
/// friends see a company's name.
struct PlayerNewsSection: View {
    var engine: GameEngine
    @Environment(\.outsidePalette) private var P
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
        }
        .task { await load() }
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

    private func load() async {
        events = await feed.service.events(now: Date())
        loaded = true
    }
}
