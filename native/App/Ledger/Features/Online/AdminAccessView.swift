import SwiftUI

struct AdminAccessView: View {
    @Environment(OnlineSession.self) private var online
    @EnvironmentObject private var store: GameStore
    @State private var code = ""
    @State private var working = false
    @State private var outcome: Outcome?
    @State private var pending: PendingAction?
    @State private var worldNote: String?
    @State private var removing = false
    @FocusState private var focused: Bool

    private let P: OutsidePalette = .control

    private enum Outcome: Equatable { case invalid, locked, failed }

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

    private var entry: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("An administrator code is given out by the owner of the game and works once. Type it exactly as you received it.")
                .textStyle(.body, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true)

            SecureField("Code", text: $code)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .font(.system(size: 18, weight: .medium, design: .monospaced)).foregroundStyle(P.ink)
                .focused($focused)
                .submitLabel(.done)
                .padding(.horizontal, Theme.Space.m).frame(minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(P.cardDeep))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(focused ? P.accent : P.line, lineWidth: 1))
                .accessibilityLabel("Administrator code")
                .accessibilityIdentifier("admin-code")

            if let message = message { Text(message).textStyle(.caption, tint: P.loss).fixedSize(horizontal: false, vertical: true) }

            Button {
                Haptics.tap()
                focused = false
                pending = PendingAction.online(
                    title: "Spend this code?",
                    effect: "the code is used up for good and this account becomes an administrator who can change world rules. Every change you make is recorded under your name.",
                    button: "Spend code", risk: "Too many wrong codes lock this for an hour.", tone: .warning, icon: "key") {
                    working = true
                    Task {
                        let r: AdminCodeResult? = await online.redeemAdminCode(code)
                        working = false
                        switch r {
                        case .some(.granted), .some(.alreadyAdmin): outcome = nil; code = ""
                        case .some(.invalid): outcome = .invalid
                        case .some(.locked): outcome = .locked
                        case .none: outcome = .failed
                        }
                    }
                }
            } label: {
                HStack(spacing: Theme.Space.s) {
                    if working { ProgressView().tint(P.onAccent) }
                    Text("Redeem code").font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(P.onAccent)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(P.accent.opacity(canSubmit ? 1 : 0.35)))
            }
            .buttonStyle(PressableStyle())
            .disabled(!canSubmit)
            .accessibilityIdentifier("admin-redeem")
        }
    }

    private var canSubmit: Bool { !working && code.trimmingCharacters(in: .whitespacesAndNewlines).count >= 12 }

    private var message: String? {
        switch outcome {
        case .invalid: return "That code is not valid, has been used, or has expired."
        case .locked: return "Too many tries. Wait an hour and try again."
        case .failed: return online.problem ?? "Could not check the code. Try again."
        case nil: return nil
        }
    }
}
