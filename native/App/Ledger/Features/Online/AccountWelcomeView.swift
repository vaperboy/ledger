import SwiftUI

/// Shown once on a new install, before the start screen. The account is for profile memory only (your progress and profile follow you
/// to other devices); it is not how friends are found, and nothing in single-player needs it. Playing as a guest is the small link at the bottom.
struct AccountWelcomeView: View {
    @Environment(OnlineSession.self) private var online
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var working: SignInProvider?
    @State private var pending: PendingAction?
    @State private var shown = false

    private let P: OutsidePalette = .passport

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: Theme.Space.m) {
                    LedgerSeal()
                    Text("Ledger").font(.system(size: 40, weight: .medium, design: .serif)).foregroundStyle(P.ink)
                    Text("Keep your profile and progress safe.").textStyle(.headline, tint: P.inkSoft, weight: .regular).multilineTextAlignment(.center)
                }
                .padding(.top, Theme.Space.xxl)
                .opacity(shown || reduceMotion ? 1 : 0)
                .offset(y: shown || reduceMotion ? 0 : 8)

                benefits.padding(.top, Theme.Space.xl)

                VStack(spacing: Theme.Space.s) {
                    providerButton(.apple)
                    providerButton(.google)
                    if let problem = online.problem {
                        Text(problem).textStyle(.caption, tint: P.loss).multilineTextAlignment(.center)
                    }
                }
                .padding(.top, Theme.Space.xl)

                Button { Haptics.tap(); online.continueAsGuest() } label: {
                    Text("Play as guest").textStyle(.caption, tint: P.inkFaint, weight: .regular).underline()
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .padding(.top, Theme.Space.l)
                .disabled(working != nil)
                .accessibilityHint("Your game stays on this device and you can link an account later in Settings.")
                .accessibilityIdentifier("account-guest")

                Text("If you play as a guest, your game stays on this device only. You can link an account later in Settings.")
                    .textStyle(.caption, tint: P.inkFaint).multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Space.l).padding(.bottom, Theme.Space.xl)
            }
            .padding(.horizontal, Theme.Space.page)
            .frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .background(P.ground.ignoresSafeArea())
        .environment(\.outsidePalette, P)
        .confirmAction($pending)
        .onAppear { withAnimation(Motion.arrive(reduceMotion)) { shown = true } }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            benefit(Glyph.person, "A profile that is yours", "Other players see only what you allow.")
            benefit(Glyph.phone, "Progress that follows you", "Pick up on another device where you left off.")
            benefit(Glyph.achievements, "A one-time gold reward", "Paid once when you link, never again for the same account.")
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(P.line, lineWidth: 0.8))
        .accessibilityElement(children: .contain)
    }

    private func benefit(_ glyph: String, _ title: String, _ note: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            LedgerGlyph(glyph: glyph, size: Theme.Icon.medium, tint: P.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).textStyle(.headline, tint: P.ink)
                Text(note).textStyle(.caption, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func providerButton(_ provider: SignInProvider) -> some View {
        let apple: Bool = provider == .apple
        let busy: Bool = working == provider
        return Button {
            Haptics.tap()
            pending = PendingAction.online(
                title: "Link " + provider.title + "?",
                effect: "your profile and progress are saved to this \(provider.title) account and follow you to other devices, and you receive a one-time gold reward. The account is not used to find friends.",
                button: "Continue with " + provider.title,
                tone: .info, icon: "person.crop.circle") {
                working = provider
                Task { _ = await online.signIn(with: provider); working = nil }
            }
        } label: {
            HStack(spacing: Theme.Space.s) {
                if busy { ProgressView().tint(apple ? P.onAccent : P.ink) }
                else if apple { Image(systemName: "apple.logo").font(.system(size: 20, weight: .medium)) }
                else { Text("G").font(.system(size: 20, weight: .bold, design: .rounded)) }
                Text("Continue with " + provider.title).font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(apple ? P.onAccent : P.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(apple ? P.accent : P.cardDeep))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(P.lineStrong, lineWidth: apple ? 0 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(working != nil)
        .accessibilityLabel("Continue with " + provider.title)
        .accessibilityIdentifier("account-" + provider.rawValue)
    }
}
