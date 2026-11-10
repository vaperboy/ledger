import SwiftUI
import Simulation

/// The small marker on a locked item: a key glyph and the words `Ledger Pro`. Shown only while the item is locked.
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

/// Wraps a button's action: runs it when the feature is open, otherwise opens the paywall named after the item.
/// Use: `Button { gate.run(.saveSlots, "More save slots") { createSlot() } }` with `@Environment(Entitlements.self) var gate`.
extension Entitlements {
    func run(_ feature: LockedFeature, _ title: String? = nil, action: () -> Void) {
        if require(feature, title: title) { action() }
    }
}

extension View {
    /// Overlays the Ledger Pro marker at the trailing top corner of a locked item.
    func proMarked(_ feature: LockedFeature) -> some View {
        overlay(alignment: .topTrailing) { ProMark(feature: feature).padding(6) }
    }
}
