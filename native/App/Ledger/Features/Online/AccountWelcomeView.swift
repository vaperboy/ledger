import SwiftUI

/// Shown once on a new install, before the start screen: sign in with Apple or Google, or play as a guest (a small, quiet link).
/// Nothing here is needed for single-player; an account only unlocks the online features.
struct AccountWelcomeView: View {
    @Environment(OnlineSession.self) private var online
    @State private var working: SignInProvider?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Theme.Space.xl)
            VStack(spacing: Theme.Space.s) {
                Text("Ledger").textStyle(.display)
                Text("Build a business. Play with friends.").textStyle(.headline, tint: Theme.inkSoft, weight: .regular)
            }
            .multilineTextAlignment(.center)
            Spacer(minLength: Theme.Space.xl)
            VStack(spacing: Theme.Space.m) {
                providerButton(.apple)
                providerButton(.google)
                if let problem = online.problem {
                    Text(problem).textStyle(.caption, tint: Theme.loss).multilineTextAlignment(.center)
                }
                Text("By continuing you confirm you are 13 or older.")
                    .textStyle(.caption).multilineTextAlignment(.center).padding(.top, Theme.Space.xs)
            }
            Button { online.continueAsGuest() } label: { Text("Play as guest").textStyle(.caption, tint: Theme.inkFaint, weight: .regular).underline() }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .padding(.top, Theme.Space.l)
                .disabled(working != nil)
                .accessibilityIdentifier("account-guest")
            Text("You can add an account later in Settings. The game works fully offline either way.")
                .textStyle(.caption, tint: Theme.inkFaint).multilineTextAlignment(.center).padding(.top, Theme.Space.xs)
            Spacer(minLength: Theme.Space.l)
        }
        .padding(.horizontal, Theme.Space.page)
        .frame(maxWidth: 520).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.page.ignoresSafeArea())
    }

    private func providerButton(_ provider: SignInProvider) -> some View {
        let apple: Bool = provider == .apple
        let busy: Bool = working == provider
        return Button {
            Haptics.tap()
            working = provider
            Task { _ = await online.signIn(with: provider); working = nil }
        } label: {
            HStack(spacing: Theme.Space.s) {
                if busy { ProgressView().tint(apple ? Theme.accentInk : Theme.ink) }
                else if apple { Image(systemName: "apple.logo").font(.system(size: 20, weight: .medium)) }
                else { Text("G").font(.system(size: 20, weight: .bold, design: .rounded)) }
                Text("Continue with " + provider.title).font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(apple ? Theme.accentInk : Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(apple ? Theme.ink : Theme.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: apple ? 0 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(working != nil)
        .accessibilityLabel("Continue with " + provider.title)
        .accessibilityIdentifier("account-" + provider.rawValue)
    }
}
