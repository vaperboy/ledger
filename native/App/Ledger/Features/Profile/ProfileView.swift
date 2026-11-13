import SwiftUI
import GameCore
import Events
import Finance
import Businesses
import Simulation

struct ProfileView: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @ObservedObject private var local = ProfileLocal.shared
    @ObservedObject private var season = SeasonModel.shared
    @State private var showLadder = false
    @State private var renaming = false
    @State private var friends: [PlayerProfile] = []
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine {
                PhonePageScroll(spacing: Theme.Space.xl) {
                    identity(e)
                    codeSection
                    InviteAcceptCard()
                    trophies(e)
                    collectionRow
                    friendsSection
                    if online.isSignedIn, let p = online.profile { privacySection(p) }
                }
                .levelLadderPopup(isPresented: $showLadder, engine: e)
            }
        }
        .appScreen(title: "Profile", subtitle: "")
        .confirmAction($pending)
        .usernameChange(isPresented: $renaming)
        .task(id: online.isSignedIn) { await syncOnline(); await loadFriends() }
    }

    private func identity(_ e: GameEngine) -> some View {
        let info: PlayerLevel.Info = e.playerLevel
        let rank: String = e.careerStatus.rank.title
        let accent: Color = Theme.gold
        return VStack(spacing: Theme.Space.s) {
            PlayerCard(data: PlayerCardData.mine(e, store: store), onRename: { renaming = true })
            if local.nameTaken {
                Text("Your username is taken by another player. Tap your name to choose a new one.").textStyle(.caption, tint: Theme.loss)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            NavigationLink { CustomiseView() } label: { Text("Customise").frame(maxWidth: .infinity) }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .accessibilityIdentifier("profile-customise")
            Button { Haptics.tap(); showLadder = true } label: {
                VStack(spacing: Theme.Space.xs) {
                    Text("Level \(info.level) \u{00B7} \(rank)").textStyle(.caption, tint: Theme.inkSoft)
                    ProgressLine(fraction: info.progress, tint: accent, height: 3).frame(maxWidth: 160)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Level \(info.level), \(rank). Shows every level and what it unlocks.")
            .accessibilityIdentifier("profile-level")
        }
        .frame(maxWidth: .infinity)
    }

    private func trophies(_ e: GameEngine) -> some View {
        let got: [Trophies.Entry] = TrophyList.unlocked(e)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text("Trophies").capsLabel(Theme.inkFaint)
                Spacer()
                NavigationLink { TrophyShowcase() } label: { Text("See all").textStyle(.body, tint: Theme.accent).frame(minHeight: 44) }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("profile-trophies-all")
            }
            if got.isEmpty {
                Text("Firsts and milestones show up here: the first customer, the first employee, the first million.")
                    .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: Theme.Space.s) {
                        ForEach(got.prefix(12)) { (t: Trophies.Entry) in
                            VStack(spacing: Theme.Space.xs) {
                                ThumbnailView(kind: .trophy, key: ArtLibrary.trophyKey(id: t.id, group: t.group), size: 48, shape: .round, glyph: Glyph.achievements, tint: Theme.gold)
                                Text(t.name).textStyle(.caption, tint: Theme.ink).lineLimit(2).multilineTextAlignment(.center)
                            }
                            .frame(width: 84)
                            .padding(.vertical, Theme.Space.s)
                            .glassSurface()
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var collectionRow: some View {
        NavigationLink { CabinetView() } label: {
            LedgerRow(leading: .glyph(Glyph.luxury), title: "Artifacts and cards", subtitle: "Your pieces, collections and sales", chevron: true)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("profile-collection")
    }

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text("Friends").capsLabel(Theme.inkFaint)
                Spacer()
                if online.isSignedIn {
                    NavigationLink { FriendsScreen() } label: {
                        Text("Add friend").textStyle(.body, tint: Theme.accent, weight: .medium).frame(minHeight: 44)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("profile-add-friend")
                }
            }
            if friends.isEmpty {
                Text(online.isSignedIn ? "No friends yet. Add one." : "Friends show here once you are online.").textStyle(.caption)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(friends.prefix(5).enumerated()), id: \.element.id) { (i: Int, p: PlayerProfile) in
                        if i > 0 { Hairline() }
                        NavigationLink { PlayerProfileView(playerID: p.id) } label: {
                            PlayerRow(player: p) { LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: Theme.inkFaint) }
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
    }

    @ViewBuilder private var codeSection: some View {
        VStack(spacing: Theme.Space.xs) {
            if online.isSignedIn {
                if online.offline { Text("Offline. It reconnects by itself.").textStyle(.caption).accessibilityIdentifier("online-offline") }
            } else {
                Text(guestNote).textStyle(.caption).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            if online.canLink {
                if online.isSignedIn {
                    Text("Link an account to keep your profile and progress across devices. Your game stays on this device.").textStyle(.caption)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: Theme.Space.s) {
                    ForEach(online.linkProviders, id: \.self) { (provider: SignInProvider) in linkButton(provider) }
                }
            }
            if let problem = online.problem, online.canLink || !online.isSignedIn {
                Text(problem).textStyle(.caption, tint: Theme.loss).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var guestNote: String {
        if online.offline { return "Offline. Your game stays on this device and the online world returns by itself." }
        if online.service.createsAccountsItself { return online.pausedByPlayer ? "You are offline by choice. Go online from Settings." : "Setting up your online profile." }
        return "Link an account to get a friend code and use the online world. Your game stays on this device."
    }

    private func linkButton(_ provider: SignInProvider) -> some View {
        Button {
            Haptics.tap()
            pending = PendingAction.online(
                title: "Link " + provider.title + "?",
                effect: "your profile and progress are saved to this \(provider.title) account and follow you to other devices, and you receive a one-time gold reward. The account is not used to find friends.",
                button: "Continue with " + provider.title, tone: .info, icon: "person.crop.circle") {
                Task { _ = await online.signIn(with: provider) }
            }
        } label: { Text(provider.title).frame(maxWidth: .infinity) }
            .buttonStyle(SecondaryButtonStyle(size: .compact))
            .disabled(online.isLinking)
            .accessibilityIdentifier("profile-link-" + provider.rawValue)
    }

    private func privacySection(_ p: PlayerProfile) -> some View {
        HStack {
            Text("Who can see my profile").textStyle(.headline)
            Spacer()
            Menu {
                ForEach(PrivacyLevel.allCases, id: \.self) { (level: PrivacyLevel) in
                    Button(level.title) { Task { _ = await online.update(ProfileUpdate(privacy: level)) } }
                }
            } label: { Text(p.privacy.title).textStyle(.body, tint: Theme.accent) }
        }
        .frame(minHeight: 48)
        .accessibilityIdentifier("profile-privacy")
    }

    private func syncOnline() async {
        guard online.isSignedIn else { return }
        await online.refreshProfile()
        let name: String = local.name
        if name.isEmpty, let shown = online.profile?.displayName { local.setName(shown) }
        else if !name.isEmpty, online.profile?.displayName != name, ProfileRules.problem(with: name) == nil {
            if await online.claimUsername(name) == .taken { local.nameTaken = true }
        }
        await online.shareProgress(from: store.engine)
        LookSync.push(online)
    }

    private func loadFriends() async {
        guard online.isSignedIn else { friends = []; return }
        friends = (try? await online.service.friends().friends) ?? []
    }
}
