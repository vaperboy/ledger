import SwiftUI

struct PlayerProfileView: View {
    var playerID: String
    var preset: PlayerProfile?
    /// A name already known from a list row. If the profile cannot load, the card is drawn from this and the directory instead.
    var knownName: String? = nil
    @Environment(OnlineSession.self) private var online
    @State private var profile: PlayerProfile?
    @State private var failure: String?
    @State private var loading = false
    @State private var attempt = UUID()
    @State private var busy = false
    @State private var pending: PendingAction?
    @State private var reporting: ReportTarget?
    @State private var reportSent = false

    /// Longest a profile may take to load before the player is offered a retry.
    private static let loadLimit: UInt64 = 12_000_000_000

    init(playerID: String, preset: PlayerProfile? = nil, knownName: String? = nil) {
        self.playerID = playerID
        self.preset = preset
        self.knownName = knownName
        _profile = State(initialValue: preset)
    }

    var body: some View {
        PhonePageScroll(spacing: Theme.Space.l) {
            if profile == nil, let p = fallback {
                header(p)
                loadStatus
            } else if let p = profile {
                header(p)
                if p.relation == .blocked {
                    Text("You blocked this player. They cannot send you requests.").textStyle(.body, tint: Theme.inkSoft).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                } else {
                    detailGroups(p)
                }
                if preset == nil { actions(p) }
            } else if failure != nil {
                loadStatus.padding(.top, Theme.Space.xl)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, Theme.Space.xl)
            }
        }
        .appScreen(title: profile?.displayName ?? fallback?.displayName ?? "Player", subtitle: profile?.subline ?? "")
        .task { if preset == nil { await load() } }
        .confirmAction($pending)
        .centerSheet(item: $reporting, title: "Report player", category: .medium) { (t: ReportTarget) in
            ReportSheet(target: t) { reason, note in
                Task {
                    try? await online.service.report(t.id, reason: reason, note: note)
                    reportSent = true
                }
            }
        }
    }

    /// What is already known about this player, used while the profile loads or when it cannot be loaded.
    private var fallback: PlayerProfile? {
        if let known = OnlineDirectoryCache.players.first(where: { (q: PlayerProfile) -> Bool in q.id == playerID }) { return known }
        guard let name = knownName, !name.isEmpty else { return nil }
        return PlayerProfile(id: playerID, code: "", displayName: name, avatarColour: AvatarCatalog.colour(for: name), countryCode: "", level: nil, badges: [],
                             privacy: .everyone, companyCount: nil, companies: nil, gameWeek: nil, tradesCompleted: nil, relation: .none)
    }

    /// Shown under a card drawn from known data, or alone when there is nothing to draw: loading, or what went wrong with a retry.
    @ViewBuilder private var loadStatus: some View {
        if let failure {
            VStack(spacing: Theme.Space.s) {
                Text(failure).textStyle(.body, tint: Theme.inkSoft).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Button("Try again") { Haptics.tap(); Task { await load() } }
                    .buttonStyle(SecondaryButtonStyle(size: .compact))
                    .accessibilityIdentifier("profile-retry")
            }
            .frame(maxWidth: .infinity)
        } else if loading {
            HStack(spacing: Theme.Space.s) {
                ProgressView()
                Text("Loading the rest of the profile").textStyle(.caption, tint: Theme.inkSoft)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func header(_ p: PlayerProfile) -> some View {
        PlayerCard(data: PlayerCardData(profile: p))
    }

    @ViewBuilder private func detailGroups(_ p: PlayerProfile) -> some View {
        if let list = p.companies, !list.isEmpty {
            OnlineGroup(title: "Companies and how they are doing") {
                OnlineCompanyList(companies: Array(list.prefix(3)))
                if list.count > 3 {
                    Hairline()
                    NavigationLink { FriendCompaniesView(player: p) } label: { OnlineLine(glyph: Glyph.group, title: "All \(list.count) companies", chevron: true) }
                        .buttonStyle(PressableStyle())
                }
            }
        } else if p.privacy != .onlyMe || p.relation == .you {
            Text(hiddenNote(p)).textStyle(.caption, tint: Theme.inkFaint).multilineTextAlignment(.center).frame(maxWidth: .infinity)
        }
    }

    private func hiddenNote(_ p: PlayerProfile) -> String {
        if let list = p.companies, list.isEmpty { return "No companies yet." }
        switch p.privacy {
        case .everyone: return "Friends see which companies this player runs."
        case .friends: return "Only friends see this player's companies."
        case .onlyMe: return "This player keeps their profile private."
        }
    }

    private func actions(_ p: PlayerProfile) -> some View {
        VStack(spacing: Theme.Space.s) {
            switch p.relation {
            case .none:
                Button("Add friend") {
                    pending = PendingAction.online(title: "Add \(p.displayName)?",
                                                   effect: "a friend request is sent to \(p.displayName). If they accept, you become friends and can see each other's companies as your privacy settings allow.",
                                                   button: "Send request", tone: .info, icon: "person.fill.badge.plus") { run { try await online.service.sendFriendRequest(to: p.id) } }
                }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true)).accessibilityIdentifier("profile-add-friend")
                Text("If you add \(p.displayName), they get a request. Once they accept you are friends: friends see the companies you run (as your privacy setting allows) and can be invited into a joint venture. You can remove them any time.")
                    .textStyle(.caption, tint: Theme.inkFaint).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            case .requestSent:
                Text("Friend request sent").textStyle(.body, tint: Theme.inkSoft)
                Button("Cancel request") {
                    pending = PendingAction.online(title: "Cancel the request?", effect: "your request to \(p.displayName) is withdrawn. You can send it again later.",
                                                   button: "Cancel request", tone: .neutral, icon: "xmark.circle") { run { try await online.service.cancelFriendRequest(to: p.id) } }
                }.buttonStyle(SecondaryButtonStyle(fullWidth: true))
            case .requestReceived:
                Button("Accept request") {
                    pending = PendingAction.online(title: "Accept \(p.displayName)?", effect: "you become friends and each of you can see the other's companies as your privacy settings allow.",
                                                   button: "Accept", tone: .success, icon: "person.fill.checkmark") { run { try await online.service.acceptFriendRequest(from: p.id) } }
                }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
                Button("Decline") {
                    pending = PendingAction.online(title: "Decline \(p.displayName)?", effect: "the request is removed and they are not told. They can send another one later.",
                                                   button: "Decline", tone: .neutral, icon: "person.fill.xmark") { run { try await online.service.declineFriendRequest(from: p.id) } }
                }.buttonStyle(SecondaryButtonStyle(fullWidth: true))
            case .friend:
                Button("Remove friend") {
                    pending = PendingAction.online(title: "Remove \(p.displayName)?", effect: "you are no longer friends and they no longer see your companies. You can add them again later.",
                                                   button: "Remove friend", tone: .warning, icon: "person.fill.xmark") { run { try await online.service.removeFriend(p.id) } }
                }.buttonStyle(SecondaryButtonStyle(fullWidth: true))
            case .blocked:
                Button("Unblock") {
                    pending = PendingAction.online(title: "Unblock \(p.displayName)?", effect: "they can find you in search and send you requests again. You are not made friends again.",
                                                   button: "Unblock", tone: .info, icon: "person.fill.checkmark") { run { try await online.service.unblockPlayer(p.id) } }
                }.buttonStyle(SecondaryButtonStyle(fullWidth: true))
            case .you:
                EmptyView()
            }
            if p.relation != .blocked && p.relation != .you {
                Button("Block") {
                    pending = PendingAction.online(title: "Block \(p.displayName)?", effect: "they are removed from your friends and requests, and cannot find you in search or send you requests.",
                                                   button: "Block", destructive: true, tone: .danger, icon: "hand.raised") { run { try await online.service.blockPlayer(p.id) } }
                }.buttonStyle(TertiaryButtonStyle(tint: Theme.loss))
            }
            if p.relation != .you {
                if reportSent {
                    Text("Report sent. Thank you.").textStyle(.caption, tint: Theme.inkSoft)
                } else {
                    Button("Report") { reporting = ReportTarget(id: p.id, name: p.displayName) }.buttonStyle(TertiaryButtonStyle(tint: Theme.inkSoft))
                }
            }
            if let failure, profile != nil { Text(failure).textStyle(.caption, tint: Theme.loss) }
        }
        .disabled(busy)
    }

    /// Loads the profile. A request that never answers is cut off after `loadLimit` so the screen never spins forever.
    private func load() async {
        let mine: UUID = UUID()
        attempt = mine
        loading = true
        failure = nil
        Task {
            try? await Task.sleep(nanoseconds: Self.loadLimit)
            if attempt == mine && loading {
                loading = false
                if profile == nil { failure = "This is taking too long. Check your connection and try again." }
            }
        }
        do {
            let loaded: PlayerProfile = try await online.service.profile(id: playerID)
            guard attempt == mine else { return }
            profile = loaded
            failure = nil
        } catch {
            guard attempt == mine else { return }
            if profile == nil { failure = (error as? LocalizedError)?.errorDescription ?? "Could not load this profile. Try again." }
        }
        if attempt == mine { loading = false }
    }

    private func run(_ call: @escaping () async throws -> Void) {
        busy = true
        Task {
            do { try await call(); failure = nil } catch { failure = (error as? LocalizedError)?.errorDescription ?? "That did not work. Try again." }
            await load()
            busy = false
        }
    }
}

struct ReportTarget: Identifiable { var id: String; var name: String }

struct ReportSheet: View {
    var target: ReportTarget
    var onSend: (ReportReason, String) -> Void
    @Environment(\.popupClose) private var popupClose
    @State private var reason: ReportReason?
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: PopupSpace.block) {
            Text("Why are you reporting \(target.name)?").popupText(.body)
            ForEach(ReportReason.allCases, id: \.self) { (r: ReportReason) in
                Button { Haptics.tap(); reason = r } label: {
                    HStack {
                        Text(r.title).popupText(.body)
                        Spacer()
                        Image(systemName: reason == r ? "largecircle.fill.circle" : "circle").foregroundStyle(reason == r ? Theme.accent : Theme.inkFaint)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(reason == r ? .isSelected : [])
            }
            TextField("Add detail (optional)", text: $note).popupField()
            Text("If you send this, the report goes to the moderators with your name on it. \(target.name) is not told who reported them.").popupText(.caption)
        }
        .centerSheetTitle("Report player")
        .popupFooter {
            PopupFooter(action: "Send report", onCancel: { popupClose?() }, onAction: {
                if let r = reason { onSend(r, note); popupClose?() }
            }, actionEnabled: reason != nil)
        }
    }
}

struct FriendCompaniesView: View {
    var player: PlayerProfile

    var body: some View {
        PhonePageScroll(spacing: Theme.Space.l) {
            OnlineGroup(title: "Companies", footer: "How a company is doing is shown in words. Figures stay private.") {
                OnlineCompanyList(companies: player.companies ?? [])
            }
        }
        .appScreen(title: player.displayName, subtitle: "Companies")
    }
}
