import SwiftUI

/// The Account section of Settings: sign in or link Apple and Google, own profile, friends, sign out, export and delete.
/// A guest sees only the sign-in rows; single-player works the same either way.
struct AccountSettingsGroup: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @State private var pending: PendingAction?
    @State private var exportURL: URL?
    @State private var working = false

    var body: some View {
        Group {
            if online.isSignedIn { signedIn } else { guest }
        }
        .confirmAction($pending)
    }

    private var guest: some View {
        OnlineGroup(title: "Account", footer: "You are playing as a guest. Link an account to find friends and show a profile. Your game stays on this device either way.") {
            providerRow(.apple)
            Hairline()
            providerRow(.google)
            if let problem = online.problem {
                Text(problem).textStyle(.caption, tint: Theme.loss).padding(.bottom, Theme.Space.s)
            }
        }
    }

    private func providerRow(_ provider: SignInProvider) -> some View {
        Button {
            Haptics.tap()
            working = true
            Task { _ = await online.signIn(with: provider); working = false }
        } label: {
            OnlineLine(glyph: Glyph.person, title: "Link " + provider.title, note: "Continue with " + provider.title, chevron: true)
        }
        .buttonStyle(PressableStyle())
        .disabled(working || online.state == .signingIn)
        .accessibilityIdentifier("settings-link-" + provider.rawValue)
    }

    private var signedIn: some View {
        OnlineGroup(title: "Account", footer: "Deleting the account removes your profile, friends and requests from the server. The game on this device is not touched.") {
            OnlineLine(glyph: Glyph.person, title: "Signed in with " + (online.provider?.title ?? ""), note: online.profile?.displayName ?? "")
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
            Button {
                pending = PendingAction(title: "Sign out?", message: "You become a guest on this device. Your game stays; your profile and friends wait for you to sign in again.",
                                        button: "Sign out", alwaysAsk: true, tone: .info, icon: "rectangle.portrait.and.arrow.right") { Task { await online.signOut() } }
            } label: { OnlineLine(glyph: Glyph.exit, title: "Sign out", chevron: true) }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("settings-sign-out")
            Hairline()
            Button {
                pending = PendingAction(title: "Delete your account?", message: "Your profile, friends and requests are removed for good. Your game on this device is kept.",
                                        button: "Delete account", destructive: true, alwaysAsk: true, risk: "This cannot be undone.") { Task { await online.deleteAccount() } }
            } label: { OnlineLine(glyph: Glyph.warning, title: "Delete account", note: "Removes everything online", tint: Theme.loss, chevron: true) }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("settings-delete-account")
            if let problem = online.problem {
                Text(problem).textStyle(.caption, tint: Theme.loss).padding(.bottom, Theme.Space.s)
            }
        }
    }

    /// Two steps: prepare the file, then share it.
    @ViewBuilder private var exportRow: some View {
        if let url = exportURL {
            ShareLink(item: url) { OnlineLine(glyph: Glyph.share, title: "Share my data file", note: "Everything the server holds about you", chevron: true) }
                .buttonStyle(PressableStyle())
        } else {
            Button {
                working = true
                Task { exportURL = await online.exportData(); working = false }
            } label: { OnlineLine(glyph: Glyph.download, title: "Export my data", note: "A file with everything the server holds about you", chevron: true) }
                .buttonStyle(PressableStyle())
                .disabled(working)
                .accessibilityIdentifier("settings-export-data")
        }
    }
}
