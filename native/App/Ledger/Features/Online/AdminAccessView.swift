import SwiftUI

struct AdminAccessView: View {
    @Environment(OnlineSession.self) private var online
    @EnvironmentObject private var store: GameStore
    @State private var pending: PendingAction?
    @State private var worldNote: String?
    @State private var removing = false

    private let P: OutsidePalette = .control


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                HStack(alignment: .center, spacing: Theme.Space.s) {
                    OutsideBack()
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text("Administrator access").textStyle(.title, tint: P.ink).accessibilityAddTraits(.isHeader)
                        Text("One-time code").textStyle(.caption, tint: P.inkSoft)
                    }
                    Spacer(minLength: 0)
                }

                if online.isAdmin { granted } else { entry }
            }
            .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.xl)
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden).noSidewaysDrag()
        .outsideScreen(P)
        .confirmAction($pending)
        .accessibilityIdentifier("admin-access")
    }

    private var granted: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.m) {
                LedgerGlyph(glyph: Glyph.check, size: Theme.Icon.large, tint: P.gain)
                VStack(alignment: .leading, spacing: 2) {
                    Text("This account is an administrator").textStyle(.headline, tint: P.ink)
                    Text("The server confirmed it. Every change you make is logged with your name.").textStyle(.caption, tint: P.inkSoft)
                }
            }
            NavigationLink { AdminScreen() } label: {
                Text("Open Administration").font(.system(size: 17, weight: .semibold)).foregroundStyle(P.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(P.accent))
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("admin-open")
            Button {
                Haptics.tap()
                pending = PendingAction.online(
                    title: "Remove all fake players?",
                    effect: "every computer-made player disappears from supplier lists, rankings and the world for everyone, and their supply deals end. Real players stay. This cannot be undone.",
                    button: "Remove fake players", risk: "Supplier lists may look emptier until more real players join.", destructive: true, tone: .danger, icon: "person.2.slash") {
                    removeFakePlayers()
                }
            } label: {
                HStack(spacing: Theme.Space.s) {
                    if removing { ProgressView().tint(P.loss) }
                    Text(FakePlayers.removed ? "Fake players removed" : "Remove all fake players").font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(P.loss)
                .frame(maxWidth: .infinity, minHeight: 54)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(P.loss.opacity(FakePlayers.removed ? 0.3 : 0.8), lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .disabled(removing || FakePlayers.removed)
            .accessibilityIdentifier("admin-remove-fakes")
            if let worldNote { Text(worldNote).textStyle(.caption, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(Theme.Space.l)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(P.line, lineWidth: 0.8))
    }

    private func removeFakePlayers() {
        removing = true
        Task {
            do {
                try await online.service.adminRemoveFakePlayers(reason: "Remove fake players")
                FakePlayers.removed = true
                _ = store.act { $0.removeFakePlayers() }
                worldNote = "Fake players are gone from supplier lists, rankings and the world."
            } catch {
                worldNote = (error as? LocalizedError)?.errorDescription ?? "That did not work. Try again."
            }
            removing = false
        }
    }

    /// Codes are typed in one place only: the Store's "Redeem gift code".
    private var entry: some View {
        Text("An administrator code is given out by the owner of the game and works once. Type it in the Store under Redeem gift code, at the top of the Store page.")
            .textStyle(.body, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("admin-code-where")
    }
}
