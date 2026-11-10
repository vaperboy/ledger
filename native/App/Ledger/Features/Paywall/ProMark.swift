import SwiftUI
import Simulation

struct ProMark: View {
    var feature: LockedFeature
    @Environment(Entitlements.self) private var ent

    var body: some View {
        if !ent.isUnlocked(feature) {
            HStack(spacing: 4) {
                GlyphView(glyph: Glyph.lock, size: 11, weight: 1.6, tint: Theme.gold)
                Text("Ledger Pro").textStyle(.caption, tint: Theme.accent, weight: .medium)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

extension Entitlements {
    func run(_ feature: LockedFeature, _ title: String? = nil, action: () -> Void) {
        if require(feature, title: title) { action() }
    }
}

extension View {
}
