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
                HStack { OutsideBack(); Spacer() }.padding(.horizontal, 18).padding(.top, 8)
                Spacer(minLength: 20)
                VStack(spacing: 18) {
                    GlyphView(glyph: Glyph.luxury, size: 44, weight: 1.3, tint: P.accent)
                    Text("PRIVATE SALES").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(3).foregroundStyle(P.accent)
                    Text("By application only").font(.serifTitle(30)).foregroundStyle(P.ink).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                    Text(message(e)).font(.system(size: 14)).foregroundStyle(P.inkSoft).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    button(e)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: 480)
                Spacer(minLength: 40)
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
            Button(action: apply) {
                Text(e.luxuryGate == .notApplied ? "Apply for access" : "Apply again")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(P.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(P.accent))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("luxury-apply")
        } else {
            Text("You may apply again later.").font(.system(size: 12.5)).foregroundStyle(P.inkFaint)
        }
    }

    private func apply() {
        _ = store.act { $0.applyForLuxuryAccess() }
    }
}
