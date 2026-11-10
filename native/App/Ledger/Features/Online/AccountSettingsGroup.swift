import SwiftUI
import Businesses

struct AccountSettingsGroup: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @State private var pending: PendingAction?
    @State private var exportURL: URL?
    @State private var working = false

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            if online.isSignedIn { signedIn } else { guest }
        }
        .confirmAction($pending)
    }

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
                effect: "your profile and progress are saved to this \(provider.title) account and follow you to other devices, and you receive a one-time gold reward.",
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

    private var signedIn: some View {
        OnlineGroup(title: "Account", footer: "Deleting the account removes your profile, friends and requests from the server. The game on this device is not touched.") {
            OnlineLine(glyph: Glyph.person, title: "Linked with " + (online.provider?.title ?? ""), note: online.profile?.displayName ?? "")
            Hairline()
            Button { store.openProfile() } label: { OnlineLine(glyph: Glyph.person, title: "Profile", note: "Your name, friend code and who can see you", chevron: true) }
                .buttonStyle(PressableStyle())
            Hairline()
            exportRow
            Hairline()
            Button { askToDelete() } label: { OnlineLine(glyph: Glyph.warning, title: "Delete account", note: "Removes everything online", tint: Theme.loss, chevron: true) }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("settings-delete-account")
            if let problem = online.problem {
                Text(problem).textStyle(.caption, tint: Theme.loss).padding(.bottom, Theme.Space.s)
            }
        }
    }

    private func askToDelete() {
        let market: SupplyMarketStore = SupplyMarketStore.shared
        let rule = SupplyGuards.accountDeletion(openContracts: market.service.openContractsAsSupplier(ownerID: market.service.ownerID))
        guard rule.allowed else {
            Haptics.warning()
            store.tell("The account cannot be deleted yet", rule.reason ?? "", tone: "warn")
            return
        }
        pending = PendingAction(title: "Delete your account?", message: "Your profile, friends and requests are removed for good, and your supply listings stop. Your game on this device is kept.",
                                button: "Delete account", destructive: true, alwaysAsk: true, risk: "This cannot be undone.") {
            Task {
                await online.deleteAccount()
                if !online.isSignedIn { market.accountDeleted(store) }
            }
        }
    }

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
}
