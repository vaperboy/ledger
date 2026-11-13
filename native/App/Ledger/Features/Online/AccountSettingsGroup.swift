import SwiftUI
import Businesses

struct AccountSettingsGroup: View {
    @Environment(OnlineSession.self) private var online
    @State private var pending: PendingAction?
    @State private var exportURL: URL?
    @State private var working = false

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            if online.isLinked { linked } else { unlinked }
        }
        .confirmAction($pending)
    }

    private var unlinked: some View {
        OnlineGroup(title: "Account", footer: footer) {
            statusLine
            if online.canLink {
                if showsStatus { Hairline() }
                SignInButtons().padding(.vertical, Theme.Space.m)
            }
            if let note = online.notice {
                Text(note).textStyle(.caption, tint: Theme.inkSoft).padding(.bottom, Theme.Space.s)
            }
            if let problem = online.problem {
                Text(problem).textStyle(.caption, tint: Theme.loss).padding(.bottom, Theme.Space.s)
            }
        }
    }

    private var showsStatus: Bool {
        online.isSignedIn ? online.offline : (online.pausedByPlayer || online.service.createsAccountsItself)
    }

    @ViewBuilder private var statusLine: some View {
        if online.isSignedIn {
            if online.offline {
                statusRow(title: "Offline", note: "Playing without the server. It reconnects by itself.", id: "online-offline")
            }
        } else if online.pausedByPlayer {
            Button { Haptics.tap(); online.resume() } label: {
                OnlineLine(glyph: Glyph.cloud, title: "Go online", note: "You are offline by choice", chevron: true)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("settings-go-online")
        } else if online.service.createsAccountsItself {
            if online.offline {
                statusRow(title: "Offline", note: "Playing without the server. It reconnects by itself.", id: "online-offline")
            } else {
                statusRow(title: "Connecting", note: "Setting up your online profile.", id: "online-connecting")
            }
        }
    }

    private func statusRow(title: String, note: String, id: String) -> some View {
        OnlineLine(glyph: Glyph.cloud, title: title, note: note, tint: Theme.inkFaint)
            .accessibilityIdentifier(id)
    }

    private var footer: String {
        let reward: String = online.linkRewardGold > 0 ? "\(online.linkRewardGold) gold" : "gold"
        guard online.canLink else { return "" }
        return "Sign in to save your profile and game to your account. On a new phone, sign in the same way to get them back. The first sign-in pays a one-time reward of \(reward). It is not used to find friends."
    }

    private var linked: some View {
        OnlineGroup(title: "Account", footer: "Your game is saved to this account as you play, so you can load it on a new phone.") {
            OnlineLine(glyph: Glyph.person, title: "Signed in with " + (online.provider?.title ?? ""), note: online.profile?.displayName ?? "")
            if let note = online.notice {
                Text(note).textStyle(.caption, tint: Theme.inkSoft).padding(.bottom, Theme.Space.s)
            }
            Hairline()
            exportRow
            if let problem = online.problem {
                Text(problem).textStyle(.caption, tint: Theme.loss).padding(.bottom, Theme.Space.s)
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

struct DeleteAccountGroup: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @State private var pending: PendingAction?
    @State private var checking = false

    var body: some View {
        if online.isSignedIn {
            OnlineGroup(title: "", footer: "Deleting the account removes your profile, friends and everything saved online. Anything still open with other players is settled first. The game on this device is not touched.") {
                Button { askToDelete() } label: { OnlineLine(glyph: Glyph.warning, title: "Delete account", note: "Removes everything online", tint: Theme.loss, chevron: true) }
                    .buttonStyle(PressableStyle())
                    .disabled(checking)
                    .accessibilityIdentifier("settings-delete-account")
                if let problem = online.problem {
                    Text(problem).textStyle(.caption, tint: Theme.loss).padding(.bottom, Theme.Space.s)
                }
            }
            .confirmAction($pending)
        }
    }

    // The server lists what it will settle with other players, so the player sees all of it before confirming.
    private func askToDelete() {
        checking = true
        Task {
            let preview: DeletionPreview? = await online.deletionPreview()
            checking = false
            guard let preview else { Haptics.warning(); return }
            let settled: String = preview.items.isEmpty ? "" : "\n\nSettled first:\n" + preview.items.map { (line: String) -> String in "• " + line }.joined(separator: "\n")
            pending = PendingAction(title: "Delete your account?",
                                    message: "Your profile, friends, saved game and everything else online are removed for good. Your game on this device is kept." + settled,
                                    button: "Delete account", destructive: true, alwaysAsk: true, risk: "This cannot be undone.") {
                Task {
                    await online.deleteAccount()
                    if !online.isSignedIn { SupplyMarketStore.shared.accountDeleted(store) }
                }
            }
        }
    }
}
