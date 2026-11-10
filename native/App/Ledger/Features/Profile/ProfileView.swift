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
    @State private var nameDraft = ""
    @State private var shortOfGold = false
    @State private var shortNeed = 0
    @State private var showPacks = false
    @StateObject private var checker = UsernameChecker()
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
                .levelLadderPopup(isPresented: $showLadder, engine: e)
            }
        }
        .appScreen(title: "Profile", subtitle: "")
        .confirmAction($pending)
        .centerSheet(isPresented: $renaming, title: "Username") { renameCard }
        .centerSheet(isPresented: $shortOfGold, title: "Not enough gold") { ShortOfGoldCard(needed: shortNeed, onPacks: { shortOfGold = false; showPacks = true }) }
        .navigationDestination(isPresented: $showPacks) { StoreApp() }
        .task(id: online.isSignedIn) { await syncOnline(); await loadFriends() }
    }

    private func identity(_ e: GameEngine) -> some View {
        let info: PlayerLevel.Info = e.playerLevel
        let rank: String = e.careerStatus.rank.title
        let accent: Color = LookKit.accent(season.pass.equipped) ?? Theme.gold
        return VStack(spacing: Theme.Space.s) {
            ProfileCard(onRename: { startRename(e) })
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

    private func hasUsername(_ e: GameEngine) -> Bool { ProfileRules.problem(with: local.name) == nil }

    private func startRename(_ e: GameEngine) {
        nameDraft = hasUsername(e) ? local.name : ""
        checker.reset()
        renaming = true
    }

    private func renameCost(_ e: GameEngine) -> Int { hasUsername(e) ? UsernameCost.change : 0 }

    @ViewBuilder private var renameCard: some View {
        if let e = store.engine {
            let cost: Int = renameCost(e)
            RenameCard(placeholder: "Username", text: $nameDraft,
                       note: cost > 0 ? "3 to 16 letters, numbers or _. Changing costs \(StoreText.gold(cost)). Your old name is never given to anyone else." : "3 to 16 letters, numbers or _. Your first username is free.",
                       buttonTitle: cost > 0 ? "Change \u{00B7} \(StoreText.gold(cost))" : "Save", enabled: checker.canUse, identifier: "profile-name",
                       onSubmit: { submitRename(e, cost: cost) }) { UsernameStatusLine(checker: checker) }
                .onChange(of: nameDraft) { _, new in checker.check(new, current: local.name, online: online) }
        }
    }

    private func submitRename(_ e: GameEngine, cost: Int) {
        let name: String = ProfileRules.clean(nameDraft)
        guard checker.canUse else { return }
        renaming = false
        if cost == 0 {
            Task { await applyName(name, cost: 0) }
        } else {
            StorePurchase.afterPopup {
                StorePurchase.ask(offer: StorePurchase.offer(.username(cost)), pending: $pending, onShort: { (price: Int) in shortNeed = price; shortOfGold = true }) {
                    Task { await applyName(name, cost: cost) }
                }
            }
        }
    }

    private func applyName(_ name: String, cost: Int) async {
        if online.isSignedIn {
            switch await online.claimUsername(name) {
            case .ok?: break
            case .taken?: store.show("That username was just taken.", tone: "warn"); return
            case .invalid?: store.show("That username is not allowed.", tone: "warn"); return
            case nil: store.show("Could not reach the server. Try again.", tone: "warn"); return
            }
        }
        if cost > 0, !(await StoreSession.shared.buy(.username(cost), paidBoxesAllowed: true)) { return }
        Haptics.success()
        local.setName(name)
    }

    private func tiles(_ e: GameEngine) -> some View {
        let companies: Int = e.state.companies.filter { (c: Company) -> Bool in c.status.isLive }.count
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
            if online.isSignedIn, let p = online.profile {
                HStack(spacing: Theme.Space.xs) {
                    Text("Friend code").textStyle(.caption)
                    Text(p.code).textStyle(.headline, numeric: true)
                    ShareLink(item: InviteLink.message(code: p.code)) { LedgerGlyph(glyph: Glyph.share, size: Theme.Icon.small, tint: Theme.accent).frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Share your friend code")
                }
                .accessibilityIdentifier("profile-code")
                if online.offline { Text("Offline. It reconnects by itself.").textStyle(.caption).accessibilityIdentifier("online-offline") }
            } else if !online.isSignedIn {
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
    }

    private func loadFriends() async {
        guard online.isSignedIn else { friends = []; return }
        friends = (try? await online.service.friends().friends) ?? []
    }
}

struct ProfileCard: View {
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @ObservedObject private var local = ProfileLocal.shared
    @ObservedObject private var season = SeasonModel.shared
    @AppStorage(CosmeticKeys.badge) private var badgeID: String = Cosmetics.defaultBadgeID
    @AppStorage(CosmeticKeys.theme) private var themeID: String = Cosmetics.defaultThemeID
    private let session = StoreSession.shared
    var compact = false
    var onRename: (() -> Void)? = nil

    var body: some View {
        if let e = store.engine {
            let look: [String: String] = season.pass.equipped
            let name: String = local.name.isEmpty ? e.state.player.name : local.name
            let info: PlayerLevel.Info = e.playerLevel
            let accent: Color = LookKit.accent(look) ?? Theme.gold
            let badge: Cosmetics.Badge = Cosmetics.resolvedBadge(badgeID, earned: e.careerCosmetics, pro: ent.isPro)
            let tone: Color = Cosmetics.resolvedTheme(themeID, pro: ent.isPro).accent
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            VStack(spacing: Theme.Space.s) {
                ProfilePicture(name: name, size: compact ? 64 : 84).overlay(Circle().strokeBorder(accent, lineWidth: 2))
                HStack(spacing: Theme.Space.xs) {
                    if let onRename {
                        NameTapLabel(label: name, action: onRename) { LookNamePlate(look: look, name: name) }
                    } else {
                        LookNamePlate(look: look, name: name)
                    }
                    if e.inHallOfFame { HallOfFameMark() }
                }
                LookTradeChip(look: look, company: LookKit.company(store))
                HStack(spacing: Theme.Space.xs) {
                    CosmeticBadgeView(badge: badge, tint: tone, size: 18)
                    Text("Level \(info.level) \u{00B7} \(e.careerStatus.rank.title)").textStyle(.caption, tint: Theme.inkSoft)
                }
                showcaseRow
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? Theme.Space.m : Theme.Space.l).padding(.horizontal, Theme.Space.m)
            .background(ZStack { shape.fill(Theme.inset); LookBackdrop(look: look) })
            .clipShape(shape)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("profile-card")
        }
    }

    @ViewBuilder private var showcaseRow: some View {
        let cabinet: Cabinet = session.state.cabinet
        let pieces: [ArtifactDef] = local.showcase.compactMap { (id: String) -> ArtifactDef? in
            cabinet.items.first(where: { (i: ArtifactItem) -> Bool in i.id == id }).flatMap { (i: ArtifactItem) -> ArtifactDef? in ArtifactCatalog.def(i.defID) }
        }
        if compact || !pieces.isEmpty {
            HStack(spacing: Theme.Space.s) {
                ForEach(0..<ProfileLocal.showcaseSlots, id: \.self) { (n: Int) in
                    if n < pieces.count {
                        ItemArt(artifact: pieces[n], size: 40)
                    } else if compact {
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                            .strokeBorder(Theme.inkFaint.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(width: 40, height: 40)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Showcase")
        }
    }
}
