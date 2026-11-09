import SwiftUI

enum Terms {
    static let key = "ledger.terms.accepted"
    static var accepted: Bool { UserDefaults.standard.bool(forKey: key) }

    static func accept() {
        UserDefaults.standard.set(true, forKey: key)
        AgeConfirmation.set(true)
    }

    static let sections: [(title: String, text: String)] = [
        ("The game", "Ledger is a simulation. Companies, money and rivals are made up, and nothing in the game is financial advice."),
        ("Gold and purchases", "Gold buys boxes, cosmetics and extra slots. It never buys in-game money and cannot be cashed out. Purchases go through the App Store, and prices are always shown before you pay. Boxes show their exact odds."),
        ("Your profile", "An account is optional and only keeps your profile and progress safe across devices. Other players see only what your privacy settings allow. You can delete the account at any time."),
        ("Fair play", "Do not cheat, exploit bugs for gain or harass other players. Accounts that do can be limited or removed."),
        ("Age", "Ledger is for players aged 18 or older. Only that confirmation is kept: no age or date of birth is asked for or stored."),
    ]
}

struct TermsView: View {
    var onAccept: () -> Void

    private let P: OutsidePalette = .passport

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    HStack(spacing: Theme.Space.m) {
                        LedgerSeal(size: 44)
                        Text("Terms and conditions").font(.system(size: 24, weight: .medium, design: .serif)).foregroundStyle(P.ink)
                            .accessibilityAddTraits(.isHeader)
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        ForEach(Array(Terms.sections.enumerated()), id: \.offset) { (_: Int, s: (title: String, text: String)) in
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text(s.title).textStyle(.headline, tint: P.ink)
                                Text(s.text).textStyle(.body, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(Theme.Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(P.card))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(P.line, lineWidth: 0.8))
                    HStack(spacing: Theme.Space.l) {
                        Link("Full terms", destination: LedgerLinks.terms).textStyle(.caption, tint: P.inkSoft)
                        Link("Privacy", destination: LedgerLinks.privacy).textStyle(.caption, tint: P.inkSoft)
                    }
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.xl).padding(.bottom, Theme.Space.l)
                .frame(maxWidth: 520).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: Theme.Space.s) {
                Text("By continuing you confirm you are 18 or older.").textStyle(.caption, tint: P.inkSoft).multilineTextAlignment(.center)
                Button {
                    Haptics.tap()
                    Terms.accept()
                    onAccept()
                } label: {
                    Text("Accept and continue").font(.system(size: 17, weight: .semibold)).foregroundStyle(P.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(P.accent))
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("terms-accept")
            }
            .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.m).padding(.bottom, Theme.Space.s)
            .frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
        .background(P.ground.ignoresSafeArea())
        .environment(\.outsidePalette, P)
    }
}
