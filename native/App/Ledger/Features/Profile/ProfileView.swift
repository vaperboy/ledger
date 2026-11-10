import SwiftUI
import PhotosUI
import GameCore
import Events
import Finance
import Businesses
import Simulation

struct ProfileView: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @ObservedObject private var local = ProfileLocal.shared
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var editingName = false
    @State private var nameDraft = ""
    @State private var friends: [PlayerProfile] = []
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine {
                PhonePageScroll(spacing: Theme.Space.xl) {
                    identity(e)
                    codeSection
                    InviteAcceptCard()
                    tiles(e)
                    trophies(e)
                    collectionRow
                    friendsSection
                    if online.isSignedIn, let p = online.profile { privacySection(p) }
                }
            }
        }
        .appScreen(title: "Profile", subtitle: "")
        .confirmAction($pending)
        .task(id: online.isSignedIn) { await syncOnline(); await loadFriends() }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { local.setPhoto(data: data) }
                pickedPhoto = nil
            }
        }
    }

    private func shownName(_ e: GameEngine) -> String { local.name.isEmpty ? e.state.player.name : local.name }

    private func identity(_ e: GameEngine) -> some View {
        let info: PlayerLevel.Info = e.playerLevel
        let rank: String = e.careerStatus.rank.title
        return VStack(spacing: Theme.Space.s) {
            ProfilePicture(name: shownName(e), size: 84)
            HStack(spacing: Theme.Space.s) {
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Text("Change photo").textStyle(.body, tint: Theme.accent, weight: .medium).frame(minHeight: 44)
                }
                .accessibilityIdentifier("profile-photo")
                if local.photo != nil {
                    Button("Remove") { Haptics.tap(); local.removePhoto() }
                        .buttonStyle(TertiaryButtonStyle(tint: Theme.inkSoft))
                }
            }
            if editingName { nameEditor(e) } else { nameLine(e) }
            Text("Level \(info.level) · \(rank)").textStyle(.caption, tint: Theme.inkSoft)
            ProgressLine(fraction: info.progress, tint: Theme.gold, height: 3).frame(maxWidth: 160)
            NavigationLink { AvatarPickerView() } label: {
                Text("Choose a profile icon").textStyle(.caption, tint: Theme.accent).frame(minHeight: 44)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("profile-icon")
        }
        .frame(maxWidth: .infinity)
    }

    private func nameLine(_ e: GameEngine) -> some View {
        Button { Haptics.tap(); nameDraft = shownName(e); editingName = true } label: {
            HStack(spacing: Theme.Space.xs) {
                Text(shownName(e)).textStyle(.title).lineLimit(1).minimumScaleFactor(0.7)
                if e.inHallOfFame { HallOfFameMark() }
                Image(systemName: "pencil").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkFaint)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Name, \(shownName(e)). Double tap to change.")
        .accessibilityIdentifier("profile-name")
    }

    private func nameEditor(_ e: GameEngine) -> some View {
        let clean: String = ProfileRules.clean(nameDraft)
        let problem: String? = clean == shownName(e) ? nil : ProfileRules.problem(with: nameDraft)
        return VStack(spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.s) {
                TextField("Name", text: $nameDraft)
                    .textFieldStyle(.plain).textStyle(.headline, weight: .regular)
                    .textInputAutocapitalization(.words).autocorrectionDisabled()
                    .submitLabel(.done).onSubmit { saveName(clean, problem) }
                    .frame(minHeight: 44)
                Button("Save") { saveName(clean, problem) }
                    .buttonStyle(SecondaryButtonStyle(size: .compact)).disabled(problem != nil || clean.isEmpty)
                Button("Cancel") { editingName = false }
                    .buttonStyle(TertiaryButtonStyle(tint: Theme.inkSoft))
            }
            if let problem { Text(problem).textStyle(.caption, tint: Theme.loss) }
        }
        .padding(.horizontal, Theme.Space.l)
    }

    private func saveName(_ clean: String, _ problem: String?) {
        guard problem == nil, !clean.isEmpty else { return }
        local.setName(clean)
        editingName = false
        if online.isSignedIn { Task { _ = await online.update(ProfileUpdate(displayName: clean)) } }
    }

    private func tiles(_ e: GameEngine) -> some View {
        let companies: Int = e.state.companies.filter { (c: Company) -> Bool in c.type != "hold" && c.status.isLive }.count
        return HStack(spacing: Theme.Space.s) {
            tile("Net worth", store.short(e.netWorth.total))
            tile("Companies", "\(companies)")
            tile("Weeks played", "\(e.state.week)")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(title).textStyle(.label, tint: Theme.inkFaint).lineLimit(1).minimumScaleFactor(0.7)
            Text(value).textStyle(.headline, numeric: true).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .glassSurface()
        .accessibilityElement(children: .combine)
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
        NavigationLink { CollectionView() } label: {
            LedgerRow(leading: .glyph(Glyph.luxury), title: "Collection", subtitle: "Artifacts and auctions", chevron: true)
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
                Text(online.isSignedIn ? "No friends yet. Add one." : "Link an account above to add friends.").textStyle(.caption)
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
        if online.isSignedIn, let p = online.profile {
            HStack(spacing: Theme.Space.xs) {
                Text("Friend code").textStyle(.caption)
                Text(p.code).textStyle(.headline, numeric: true)
                ShareLink(item: InviteLink.message(code: p.code)) { LedgerGlyph(glyph: Glyph.share, size: Theme.Icon.small, tint: Theme.accent).frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Share your friend code")
            }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("profile-code")
        } else if !online.isSignedIn {
            VStack(spacing: Theme.Space.xs) {
                Text("Link an account to get a friend code and use the online world. Your game stays on this device.").textStyle(.caption).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.Space.s) {
                    linkButton(.apple)
                    linkButton(.google)
                }
                if let problem = online.problem { Text(problem).textStyle(.caption, tint: Theme.loss).multilineTextAlignment(.center) }
            }
            .frame(maxWidth: .infinity)
        }
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
            .disabled(online.state == .signingIn)
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
        else if !name.isEmpty, online.profile?.displayName != name, ProfileRules.problem(with: name) == nil { _ = await online.update(ProfileUpdate(displayName: name)) }
        await online.shareProgress(from: store.engine)
    }

    private func loadFriends() async {
        guard online.isSignedIn else { friends = []; return }
        friends = (try? await online.service.friends().friends) ?? []
    }
}
