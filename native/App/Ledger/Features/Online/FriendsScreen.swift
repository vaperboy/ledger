import SwiftUI
import GameCore
import Businesses
import Simulation

struct FriendsScreen: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @State private var overview: FriendsOverview?
    @State private var query = ""
    @State private var results: [PlayerProfile] = []
    @State private var searching = false
    @State private var failure: String?
    @State private var pending: PendingAction?
    @State private var giftOpen = false
    @State private var giftFriend: PlayerProfile?

    var body: some View {
        PhonePageScroll(spacing: Theme.Space.l) {
            if online.isSignedIn && !online.awaitingAdultConfirmation { signedIn } else { AccountSettingsGroup() }
        }
        .confirmAction($pending)
        .appScreen(title: "Friends", subtitle: "Requests, search and your friends")
        .centerSheet(isPresented: $giftOpen, title: "Send a gift", size: .tall) {
            if let f = giftFriend { GiftChoices(friend: f) { (item: ArtifactItem) in sendGift(item, to: f) } }
        }
        .task(id: online.isSignedIn) { await reload() }
        .task(id: query) { await search() }
    }

    @ViewBuilder private var signedIn: some View {
        OfflineNote()
        searchGroup
        if let o = overview {
            if !o.incoming.isEmpty { incomingGroup(o.incoming) }
            if !o.outgoing.isEmpty { outgoingGroup(o.outgoing) }
            friendsGroup(o.friends)
            FriendPlayGroups(friends: o.friends)
        } else if let failure {
            OnlineListState(phase: .failed(failure)) { self.failure = nil; Task { await reload() } }
        } else {
            OnlineWaiting { Task { await reload() } }
        }
        if overview != nil, let failure { Text(failure).textStyle(.caption, tint: Theme.loss).frame(maxWidth: .infinity) }
    }

    private var searchGroup: some View {
        OnlineGroup(title: "Find a player", footer: "Type a name, or paste a profile code like K7M-4PQ2.") {
            HStack(spacing: Theme.Space.s) {
                LedgerGlyph(glyph: Glyph.person, size: Theme.Icon.small, tint: Theme.inkFaint)
                TextField("Name or profile code", text: $query)
                    .textFieldStyle(.plain).textStyle(.headline, weight: .regular)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("friends-search")
                if searching { ProgressView() }
            }
            .frame(minHeight: 48)
            if !query.trimmingCharacters(in: .whitespaces).isEmpty && !searching {
                Hairline()
                if results.isEmpty {
                    Text("Nobody found.").textStyle(.body, tint: Theme.inkSoft).frame(minHeight: 48, alignment: .leading)
                } else {
                    ForEach(Array(results.enumerated()), id: \.element.id) { (i: Int, p: PlayerProfile) in
                        if i > 0 { Hairline() }
                        resultRow(p)
                    }
                }
            }
            if let mine = online.profile {
                Hairline()
                HStack {
                    Text("Your code").textStyle(.caption)
                    Text(mine.code).textStyle(.headline, numeric: true)
                    Spacer()
                    ShareLink(item: InviteLink.message(code: mine.code)) { Text("Share").textStyle(.body, tint: Theme.accent) }
                }
                .frame(minHeight: 48)
            }
        }
    }

    private func resultRow(_ p: PlayerProfile) -> some View {
        NavigationLink { PlayerProfileView(playerID: p.id) } label: {
            PlayerRow(player: p) { relationTag(p) }
        }
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder private func relationTag(_ p: PlayerProfile) -> some View {
        switch p.relation {
        case .none:
            Button("Add") { askAdd(p) }
                .buttonStyle(SecondaryButtonStyle(size: .compact))
        case .friend: Text("Friend").textStyle(.caption, tint: Theme.gain)
        case .requestSent: Text("Requested").textStyle(.caption)
        case .requestReceived: Text("Wants to be friends").textStyle(.caption, tint: Theme.accent)
        case .blocked, .you: EmptyView()
        }
    }

    private func incomingGroup(_ list: [FriendRequest]) -> some View {
        OnlineGroup(title: "Requests") {
            ForEach(Array(list.enumerated()), id: \.element.id) { (i: Int, r: FriendRequest) in
                if i > 0 { Hairline() }
                VStack(spacing: 0) {
                    NavigationLink { PlayerProfileView(playerID: r.player.id) } label: { PlayerRow(player: r.player) { EmptyView() } }
                        .buttonStyle(PressableStyle())
                    HStack(spacing: Theme.Space.s) {
                        Button("Accept") {
                            pending = PendingAction.online(title: "Accept \(r.player.displayName)?",
                                                           effect: "you become friends and each of you can see the other's companies as your privacy settings allow.",
                                                           button: "Accept", tone: .success, icon: "person.fill.checkmark") { act { try await online.service.acceptFriendRequest(from: r.player.id) } }
                        }
                            .buttonStyle(PrimaryButtonStyle(size: .compact))
                        Button("Decline") {
                            pending = PendingAction.online(title: "Decline \(r.player.displayName)?",
                                                           effect: "the request is removed and they are not told. They can send another one later.",
                                                           button: "Decline", tone: .neutral, icon: "person.fill.xmark") { act { try await online.service.declineFriendRequest(from: r.player.id) } }
                        }
                            .buttonStyle(SecondaryButtonStyle(size: .compact))
                        Spacer()
                    }
                    .padding(.bottom, Theme.Space.s)
                }
            }
        }
    }

    private func outgoingGroup(_ list: [FriendRequest]) -> some View {
        OnlineGroup(title: "Sent", footer: "Waiting for an answer.") {
            ForEach(Array(list.enumerated()), id: \.element.id) { (i: Int, r: FriendRequest) in
                if i > 0 { Hairline() }
                PlayerRow(player: r.player) {
                    Button("Cancel") {
                        pending = PendingAction.online(title: "Cancel the request?",
                                                       effect: "your request to \(r.player.displayName) is withdrawn. You can send it again later.",
                                                       button: "Cancel request", tone: .neutral, icon: "xmark.circle") { act { try await online.service.cancelFriendRequest(to: r.player.id) } }
                    }
                        .buttonStyle(TertiaryButtonStyle(tint: Theme.inkSoft))
                }
            }
        }
    }

    private func friendsGroup(_ list: [PlayerProfile]) -> some View {
        OnlineGroup(title: "Friends", footer: list.isEmpty ? "" : "Tap a friend to see their companies.") {
            if list.isEmpty {
                Text("No friends yet. Search above to add one.").textStyle(.body, tint: Theme.inkSoft).frame(minHeight: 56, alignment: .leading)
            } else {
                ForEach(Array(list.enumerated()), id: \.element.id) { (i: Int, p: PlayerProfile) in
                    if i > 0 { Hairline() }
                    HStack(spacing: Theme.Space.s) {
                        NavigationLink { PlayerProfileView(playerID: p.id) } label: {
                            PlayerRow(player: p) {
                                Text(companyLine(p)).textStyle(.caption)
                                LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint)
                            }
                        }
                        .buttonStyle(PressableStyle())
                        Button("Gift") { Haptics.tap(); giftFriend = p; giftOpen = true }
                            .buttonStyle(SecondaryButtonStyle(size: .compact))
                            .disabled(!FriendPlayModel.shared.canGift)
                            .accessibilityIdentifier("friends-gift-\(p.id)")
                    }
                }
            }
        }
    }

    private func sendGift(_ item: ArtifactItem, to friend: PlayerProfile) {
        giftOpen = false
        Task { @MainActor in failure = await GiftSender.send(item, to: friend, online: online, store: store) }
    }

    private func companyLine(_ p: PlayerProfile) -> String {
        guard let n = p.companyCount else { return "" }
        return n == 1 ? "1 company" : "\(n) companies"
    }

    private func reload() async {
        guard online.isSignedIn else { overview = nil; return }
        do { overview = try await online.service.friends(); failure = nil } catch { failure = OnlineWords.friendly(error) }
    }

    private func search() async {
        let q: String = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard online.isSignedIn, !q.isEmpty else { results = []; searching = false; return }
        searching = true
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        do { results = try await online.service.searchPlayers(query: q); failure = nil } catch { if !Task.isCancelled { failure = OnlineWords.friendly(error) } }
        if !Task.isCancelled { searching = false }
    }

    private func askAdd(_ p: PlayerProfile) {
        pending = PendingAction.online(title: "Add \(p.displayName)?",
                                       effect: "a friend request is sent to \(p.displayName). If they accept, you become friends and can see each other's companies as your privacy settings allow.",
                                       button: "Send request", tone: .info, icon: "person.fill.badge.plus") { act { try await online.service.sendFriendRequest(to: p.id) } }
    }

    private func act(_ call: @escaping () async throws -> Void) {
        Task {
            do { try await call(); failure = nil } catch { failure = OnlineWords.friendly(error) }
            await reload()
            await search()
        }
    }
}
