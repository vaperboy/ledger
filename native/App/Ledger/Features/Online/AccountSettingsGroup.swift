import SwiftUI

/// The Account section of Settings: link Apple or Google (profile memory only, with a one-time gold reward), own profile, friends, sign out,
/// export and delete, and the administrator entry. A guest sees only the link rows; single-player works the same either way.
struct AccountSettingsGroup: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @State private var pending: PendingAction?
    @State private var exportURL: URL?
    @State private var working = false

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            Group {
                if online.awaitingAdultConfirmation { ProfileCreationView(embedded: true) }
                else if online.isSignedIn { signedIn }
                else { guest }
            }
            if online.isSignedIn && !online.awaitingAdultConfirmation { mergeCard }
            AgeConfirmationGroup()
        }
        .confirmAction($pending)
    }

    // MARK: Guest

    private var guest: some View {
        OnlineGroup(title: "Account", footer: guestFooter) {
            providerRow(.apple)
            Hairline()
            providerRow(.google)
            if let note = online.notice {
                Text(note).textStyle(.caption, tint: Theme.inkSoft).padding(.bottom, Theme.Space.s)
            }
            if let problem = online.problem {
                Text(problem).textStyle(.caption, tint: Theme.loss).padding(.bottom, Theme.Space.s)
            }
        }
    }

    private var guestFooter: String {
        let reward: String = online.linkRewardGold > 0 ? "\(online.linkRewardGold) gold" : "gold"
        return "You are playing as a guest. Linking keeps your profile and progress across devices and pays a one-time reward of \(reward). It is not used to find friends. Your game stays on this device either way."
    }

    private func providerRow(_ provider: SignInProvider) -> some View {
        Button {
            Haptics.tap()
            pending = PendingAction.online(
                title: "Link " + provider.title + "?",
                effect: "your profile and progress are saved to this \(provider.title) account and follow you to other devices, and you receive a one-time gold reward. You are asked to confirm you are 18 or older before a profile is created.",
                button: "Continue with " + provider.title, tone: .info, icon: "person.crop.circle") {
                working = true
                Task { _ = await online.signIn(with: provider); working = false }
            }
        } label: {
            OnlineLine(glyph: Glyph.person, title: "Link " + provider.title, note: "Profile and progress, one-time gold reward", chevron: true)
        }
        .buttonStyle(PressableStyle())
        .disabled(working || online.state == .signingIn)
        .accessibilityIdentifier("settings-link-" + provider.rawValue)
    }

    // MARK: Signed in

    private var signedIn: some View {
        OnlineGroup(title: "Account", footer: "Deleting the account removes your profile, friends and requests from the server. The game on this device is not touched.") {
            OnlineLine(glyph: Glyph.person, title: "Linked with " + (online.provider?.title ?? ""), note: online.profile?.displayName ?? "")
            Hairline()
            NavigationLink {
                MyProfileView()
            } label: { OnlineLine(glyph: Glyph.person, title: "My profile", note: "Name, colour, privacy and companies", chevron: true) }
                .buttonStyle(PressableStyle())
            Hairline()
            Button { store.openApp(.friends) } label: { OnlineLine(glyph: Glyph.team, title: "Friends", note: "Requests, search and your friends", chevron: true) }
                .buttonStyle(PressableStyle())
            Hairline()
            exportRow
            Hairline()
            adminRow
            Hairline()
            Button {
                pending = PendingAction.online(title: "Sign out?",
                                               effect: "you become a guest on this device. Your game stays; your profile and progress wait for you to sign in again.",
                                               button: "Sign out", tone: .info, icon: "rectangle.portrait.and.arrow.right") { Task { await online.signOut() } }
            } label: { OnlineLine(glyph: Glyph.exit, title: "Sign out", chevron: true) }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("settings-sign-out")
            Hairline()
            Button {
                pending = PendingAction.online(title: "Delete your account?",
                                               effect: "your profile, friends, requests and progress are removed from the server for good. Your game on this device is kept.",
                                               button: "Delete account", risk: "This cannot be undone.", destructive: true, tone: .danger, icon: "trash") { Task { await online.deleteAccount() } }
            } label: { OnlineLine(glyph: Glyph.warning, title: "Delete account", note: "Removes everything online", tint: Theme.loss, chevron: true) }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("settings-delete-account")
            if let problem = online.problem {
                Text(problem).textStyle(.caption, tint: Theme.loss).padding(.bottom, Theme.Space.s)
            }
        }
    }

    /// The administrator entry. Whether the account is an administrator is the server's answer (`OnlineSession.isAdmin`), never a setting here.
    @ViewBuilder private var adminRow: some View {
        if online.isAdmin {
            NavigationLink { AdminScreen() } label: {
                OnlineLine(glyph: Glyph.settings, title: "Administration", note: "World rules, confirmations and the audit log", chevron: true)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("settings-admin")
        } else {
            NavigationLink { AdminAccessView() } label: {
                OnlineLine(glyph: Glyph.lock, title: "Administrator access", note: "Have a one-time code?", chevron: true)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("settings-admin-access")
        }
    }

    /// Two steps: prepare the file, then share it.
    @ViewBuilder private var exportRow: some View {
        if let url = exportURL {
            ShareLink(item: url) { OnlineLine(glyph: Glyph.share, title: "Share my data file", note: "Everything the server holds about you", chevron: true) }
                .buttonStyle(PressableStyle())
        } else {
            Button {
                pending = PendingAction.online(title: "Export your data?",
                                               effect: "a file with everything the server holds about you is prepared here. Nothing is sent anywhere until you choose to share it.",
                                               button: "Prepare file", tone: .info, icon: "square.and.arrow.up") {
                    working = true
                    Task { exportURL = await online.exportData(); working = false }
                }
            } label: { OnlineLine(glyph: Glyph.download, title: "Export my data", note: "A file with everything the server holds about you", chevron: true) }
                .buttonStyle(PressableStyle())
                .disabled(working)
                .accessibilityIdentifier("settings-export-data")
        }
    }

    // MARK: Progress

    /// Shown when the account already holds more progress than this device's game, until the player has chosen which side stays.
    @ViewBuilder private var mergeCard: some View {
        if let m = online.mergePrompt {
            OnlineGroup(title: "Two games, one profile",
                        footer: "Your profile already holds progress up to week \(m.accountWeek). The game on this device is at week \(m.deviceWeek). Either way, the game itself is not changed.") {
                mergeButton("Use this game for my profile", note: "Replaces the progress your profile shows", choice: .device,
                            effect: "the level, week and companies your profile shows are replaced by this game's, and friends see the new figures.")
                Hairline()
                mergeButton("Keep my profile as it is", note: "This game does not update it until it passes week \(m.accountWeek)", choice: .account,
                            effect: "this game stops updating your profile until it passes week \(m.accountWeek). Nothing on this device changes.")
            }
        } else if online.progressChoice == .account {
            OnlineGroup(title: "Progress", footer: "This game is not updating your profile while the profile is ahead of it.") {
                mergeButton("Use this game for my profile", note: "Replaces the progress your profile shows", choice: .device,
                            effect: "the level, week and companies your profile shows are replaced by this game's, and friends see the new figures.")
            }
        }
    }

    private func mergeButton(_ title: String, note: String, choice: OnlineSession.ProgressChoice, effect: String) -> some View {
        Button {
            pending = PendingAction.online(title: title + "?", effect: effect, button: "Yes, do it", tone: .info, icon: "arrow.triangle.2.circlepath") {
                Task { await online.resolveMerge(choice, engine: store.engine) }
            }
        } label: { OnlineLine(glyph: Glyph.person, title: title, note: note, chevron: true) }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("settings-merge-" + choice.rawValue)
    }
}
