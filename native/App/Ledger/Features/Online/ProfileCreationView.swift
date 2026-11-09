import SwiftUI

/// The last step of linking: confirm you are 18 or older, then the profile is created. Only that yes is kept (never an age or a date of
/// birth). Anyone who is not 18 cannot create a profile; the empty account is removed and they play on as a guest.
/// Full-page on first run (`embedded` false) and a card inside Settings otherwise.
struct ProfileCreationView: View {
    var embedded = false
    @Environment(OnlineSession.self) private var online
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmed = false
    @State private var working = false
    @State private var pending: PendingAction?

    private let P: OutsidePalette = .passport

    var body: some View {
        Group {
            if embedded { card } else {
                ScrollView {
                    card.padding(.horizontal, Theme.Space.page).padding(.vertical, Theme.Space.xxl)
                        .frame(maxWidth: 520).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .background(P.ground.ignoresSafeArea())
            }
        }
        .environment(\.outsidePalette, P)
        .confirmAction($pending)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.m) {
                LedgerSeal(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create your profile").font(.system(size: 22, weight: .medium, design: .serif)).foregroundStyle(P.ink).accessibilityAddTraits(.isHeader)
                    Text("One last step").textStyle(.caption, tint: P.inkSoft)
                }
            }

            Button {
                Haptics.tap()
                confirmed.toggle()
            } label: {
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(confirmed ? P.accent : P.lineStrong, lineWidth: 1.5)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(confirmed ? P.accent : Color.clear))
                        if confirmed { LedgerGlyph(glyph: Glyph.check, size: 14, tint: P.onAccent) }
                    }
                    .frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("I am 18 or older").textStyle(.headline, tint: P.ink)
                        Text("Only this yes is saved. No age or date of birth is asked for or kept.").textStyle(.caption, tint: P.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Theme.Space.m)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(P.cardDeep))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(confirmed ? P.accent.opacity(0.6) : P.line, lineWidth: 0.8))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .animation(Motion.quick(reduceMotion), value: confirmed)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("I am 18 or older")
            .accessibilityValue(confirmed ? "Confirmed" : "Not confirmed")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("profile-adult")

            if let problem = online.problem { Text(problem).textStyle(.caption, tint: P.loss) }

            Button {
                Haptics.tap()
                pending = PendingAction.online(
                    title: "Create your profile?",
                    effect: "your profile is created with a default name you can change, other players can see it as your privacy setting allows, and the one-time gold reward is paid.",
                    button: "Create profile", risk: "You are confirming that you are 18 or older.", tone: .success, icon: "person.crop.circle.badge.checkmark") {
                    working = true
                    Task { _ = await online.confirmAdult(); working = false }
                }
            } label: {
                HStack(spacing: Theme.Space.s) {
                    if working { ProgressView().tint(P.onAccent) }
                    Text("Create profile").font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(P.onAccent)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(P.accent.opacity(confirmed ? 1 : 0.35)))
            }
            .buttonStyle(PressableStyle())
            .disabled(!confirmed || working)
            .accessibilityIdentifier("profile-create")

            Button {
                Haptics.tap()
                pending = PendingAction.online(
                    title: "No profile?",
                    effect: "no profile is created, the empty account is removed, and you carry on as a guest. Your game on this device is not touched.",
                    button: "Carry on as guest", tone: .neutral, icon: "person.crop.circle.badge.xmark") {
                    working = true
                    Task { await online.declineProfile(); working = false }
                }
            } label: {
                Text("I am under 18, or I do not want a profile").textStyle(.caption, tint: P.inkFaint, weight: .regular).underline()
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(working)
            .accessibilityIdentifier("profile-decline")
        }
        .padding(Theme.Space.l)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(P.line, lineWidth: 0.8))
    }
}
