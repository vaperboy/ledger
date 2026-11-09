import SwiftUI

struct MyProfileView: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @State private var pending: PendingAction?

    var body: some View {
        PhonePageScroll(spacing: Theme.Space.l) {
            if let p = online.profile, online.isSignedIn {
                header(p)
                OnlineGroup(title: "") {
                    NavigationLink { WorldFeedView() } label: {
                        OnlineLine(glyph: Glyph.world, title: "World", note: "Events, friends' activity and invitations", chevron: true)
                    }
                    .buttonStyle(PressableStyle())
                }
                lookGroup(p)
                privacyGroup(p)
                companiesGroup(p)
                recordGroup(p)
            } else {
                AccountSettingsGroup()
            }
        }
        .appScreen(title: "Online profile", subtitle: "What other players see")
        .confirmAction($pending)
        .task { await online.refreshProfile() }
    }

    private func header(_ p: PlayerProfile) -> some View {
        VStack(spacing: Theme.Space.s) {
            PlayerAvatar(player: p, size: 84)
            NamePlateText(name: p.displayName)
            Text(p.subline).textStyle(.caption)
            if !p.badges.isEmpty {
                Text(p.badges.joined(separator: "  ·  ")).textStyle(.caption, tint: Theme.accent).multilineTextAlignment(.center)
            }
            HStack(spacing: Theme.Space.xs) {
                Text("Your code").textStyle(.caption)
                Text(p.code).textStyle(.headline, numeric: true)
                ShareLink(item: p.code) { LedgerGlyph(glyph: Glyph.share, size: Theme.Icon.small, tint: Theme.accent) }.accessibilityLabel("Share your code")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.m)
    }

    private func lookGroup(_ p: PlayerProfile) -> some View {
        OnlineGroup(title: "Look") {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Avatar colour").textStyle(.headline)
                HStack(spacing: Theme.Space.s) {
                    ForEach(0..<PlayerProfile.avatarColourCount, id: \.self) { (i: Int) in
                        Button {
                            Haptics.tap()
                            Task { _ = await online.update(ProfileUpdate(avatarColour: i)) }
                        } label: {
                            Circle().fill(ProfileAvatar.colours[i]).frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: p.avatarColour == i ? 2 : 0).padding(-3))
                                .frame(minWidth: 36, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Colour \(i + 1)").accessibilityAddTraits(p.avatarColour == i ? .isSelected : [])
                    }
                }
            }
            .padding(.vertical, Theme.Space.s)
            Hairline()
            HStack {
                Text("Country").textStyle(.headline)
                Spacer()
                Menu {
                    ForEach(OnlineCountry.codes, id: \.self) { (code: String) in
                        Button(OnlineCountry.name(code)) { Task { _ = await online.update(ProfileUpdate(countryCode: code)) } }
                    }
                } label: {
                    Text(OnlineCountry.name(p.countryCode)).textStyle(.body, tint: Theme.accent)
                }
            }
            .frame(minHeight: 48)
        }
    }

    private func privacyGroup(_ p: PlayerProfile) -> some View {
        OnlineGroup(title: "Who can see my profile", footer: p.privacy.note) {
            ForEach(Array(PrivacyLevel.allCases.enumerated()), id: \.element) { (i: Int, level: PrivacyLevel) in
                if i > 0 { Hairline() }
                Button {
                    Haptics.tap()
                    guard p.privacy != level else { return }
                    pending = PendingAction.online(title: "Show your profile to \(level.title.lowercased())?", effect: level.note.prefix(1).lowercased() + level.note.dropFirst(),
                                                   button: "Change", tone: .info, icon: "eye") { Task { _ = await online.update(ProfileUpdate(privacy: level)) } }
                } label: {
                    HStack {
                        Text(level.title).textStyle(.headline)
                        Spacer()
                        if p.privacy == level { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                    }
                    .frame(minHeight: 48).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(p.privacy == level ? .isSelected : [])
            }
        }
    }

    private func companiesGroup(_ p: PlayerProfile) -> some View {
        let list: [OnlineCompany] = p.companies ?? []
        return OnlineGroup(title: "My companies", footer: companiesNote(p.privacy)) {
            if list.isEmpty {
                Text("No companies shared yet.").textStyle(.body, tint: Theme.inkSoft).frame(minHeight: 52, alignment: .leading)
            } else {
                OnlineCompanyList(companies: list)
            }
            Hairline()
            Button {
                pending = PendingAction.online(title: "Update your profile?", effect: "your open companies, level and week are sent to your profile, and other players see them as your privacy setting allows.",
                                               button: "Update", tone: .info, icon: "arrow.triangle.2.circlepath") { Task { await online.shareProgress(from: store.engine) } }
            } label: { OnlineLine(glyph: Glyph.hire, title: "Update from my game", note: store.engine == nil ? "Start or open a game first" : "Shares your open companies, level and week", chevron: true) }
                .buttonStyle(PressableStyle()).disabled(store.engine == nil)
        }
    }

    private func companiesNote(_ level: PrivacyLevel) -> String {
        switch level {
        case .everyone: return "Everyone sees how many companies you run. Only friends see which ones."
        case .friends: return "Only friends see your companies."
        case .onlyMe: return "Nobody sees your companies."
        }
    }

    private func recordGroup(_ p: PlayerProfile) -> some View {
        OnlineGroup(title: "Trade record", footer: "Trades with other players will be counted here.") {
            OnlineLine(glyph: Glyph.market, title: "Trades completed", value: "\(p.tradesCompleted ?? 0)")
        }
    }
}
