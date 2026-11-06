import SwiftUI
import GameCore
import Simulation

/// The first screen of the Luxury app: entry is by application. It never says what is looked at, only the answer.
struct LuxuryGateView: View {
    @EnvironmentObject var store: GameStore
    private var P: OutsidePalette { .luxury }

    var body: some View {
        if let e = store.engine {
            VStack(spacing: 0) {
                HStack { OutsideBack(); Spacer() }.padding(.horizontal, Theme.Space.s).padding(.top, Theme.Space.xs)
                Spacer(minLength: Theme.Space.l)
                VStack(spacing: Theme.Space.l) {
                    LedgerGlyph(glyph: Glyph.luxury, size: Theme.Icon.large, tint: P.accent)
                    VStack(spacing: Theme.Space.xs) {
                        Text("Private sales").textStyle(.label)
                        Text("By application only").textStyle(.title).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                    }
                    Text(message(e)).textStyle(.body, tint: P.inkSoft).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    button(e)
                }
                .padding(.horizontal, Theme.Space.xl)
                .frame(maxWidth: ShopMetrics.maxWidth)
                Spacer(minLength: Theme.Space.xxl)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func message(_ e: GameEngine) -> String {
        switch e.luxuryGate {
        case .declined: return "Thank you for your interest. We are unable to offer you access at this time."
        default: return "Our collection of cars, jets, yachts, homes, watches and art is shown to approved members. Send your application to be considered."
        }
    }

    @ViewBuilder private func button(_ e: GameEngine) -> some View {
        if e.luxuryGateCanApply {
            Button(e.luxuryGate == .notApplied ? "Apply for access" : "Apply again", action: apply)
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .accessibilityIdentifier("luxury-apply")
        } else {
            Text("You may apply again later.").textStyle(.caption, tint: P.inkFaint)
        }
    }

    private func apply() {
        Haptics.tap()
        _ = store.act { $0.applyForLuxuryAccess() }
    }
}
