import SwiftUI
import Simulation

struct ProPlansView: View {
    @Environment(Entitlements.self) private var ent

    private struct Spec {
        var product: LedgerProduct
        var name: String
        var billing: String
        var summary: String
        var includes: [String]
        var excludes: String = ""
    }

    private static let yearly = Spec(
        product: .plusYearly, name: "Ledger Plus, yearly", billing: "Subscription, renews every year",
        summary: "Everything in Pro, plus the premium Season Pass. Billed once a year.",
        includes: ["Every locked item and 3 save slots", "No ads", "Premium Season Pass track"])
    private static let monthly = Spec(
        product: .plusMonthly, name: "Ledger Plus, monthly", billing: "Subscription, renews every month",
        summary: "The same as the yearly plan, paid month by month. Stop whenever you like.",
        includes: ["Every locked item and 3 save slots", "No ads", "Premium Season Pass track"])
    private static let pro = Spec(
        product: .pro, name: "Ledger Pro", billing: "One-time purchase, yours for good",
        summary: "Pay once and keep every locked item. Nothing renews.",
        includes: ["Every locked item and 3 save slots", "No ads", "Family Sharing"], excludes: "Does not include the premium Season Pass track.")
    private static let founder = Spec(
        product: .founder, name: "Founder's Edition", billing: "One-time purchase, yours for good",
        summary: "Ledger Pro with a Founder mark, for people who want to back the game. Nothing renews.",
        includes: ["Everything in Ledger Pro", "A Founder mark in Settings"], excludes: "Does not include the premium Season Pass track.")

    var body: some View {
        ScrollView {
            content.padding(.bottom, Theme.Space.l)
        }
        .scrollIndicators(.hidden)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Ledger plans").capsLabel(Theme.inkFaint)
                Text("A subscription renews until you cancel it. A one-time purchase is paid once and is yours for good.")
                    .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Space.m)
            if ent.ownsPro { ownedRow }
            if ent.isPlus {
                plusStatus
            } else {
                group("Subscriptions", [Self.yearly, Self.monthly])
            }
            if !ent.ownsPro && !ent.isPlus { group("One-time purchases", [Self.pro, Self.founder]) }
            comparison
            if !ent.isPlus {
                Text("Ledger Plus is a subscription. It renews automatically at the price shown unless it is cancelled at least 24 hours before the period ends, and your Apple ID is charged within 24 hours before it renews. Manage or cancel it in your App Store account settings. Ledger Pro and Founder's Edition are one-time purchases and never renew.")
                    .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true).padding(.horizontal, Theme.Space.m)
                    .accessibilityIdentifier("plans-disclosure")
            }
            if let note = ent.message { Text(note).textStyle(.caption).padding(.horizontal, Theme.Space.m) }
            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button { Task { await ent.restore() } } label: { Text("Restore purchases") }
                .buttonStyle(PlainTextButtonStyle(tint: Theme.ivoryMuted))
                .disabled(ent.isBusy)
                .accessibilityIdentifier("plans-restore")
            Link("Terms", destination: LedgerLinks.terms).textStyle(.caption)
            Link("Privacy", destination: LedgerLinks.privacy).textStyle(.caption)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.m)
    }

    private func group(_ title: String, _ specs: [Spec]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title).textStyle(.headline).padding(.horizontal, Theme.Space.m)
            ForEach(specs, id: \.product) { (s: Spec) in card(s) }
        }
    }

    private var ownedRow: some View {
        HStack(spacing: Theme.Space.s) {
            GlyphView(glyph: Glyph.check, size: 14, weight: 1.8, tint: Theme.gain)
            VStack(alignment: .leading, spacing: 2) {
                Text(ent.isFounder ? "You own Founder's Edition" : "You own Ledger Pro").textStyle(.headline)
                Text("One-time purchase. Every locked item is open and ads are off, for good.").textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StoreSurface(tint: Theme.gain, radius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
    }

    private var plusStatus: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                GlyphView(glyph: Glyph.check, size: 14, weight: 1.8, tint: Theme.gain)
                Text("Ledger Plus is active").textStyle(.headline)
                Spacer(minLength: 0)
                StoreTag(text: "Subscription", tint: Theme.gain)
            }
            Text(ent.plusRenews.map { "Renews on \($0.formatted(date: .abbreviated, time: .omitted)). Everything in Pro, no ads and the premium Season Pass track." }
                 ?? "Everything in Pro, no ads and the premium Season Pass track.")
                .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            Button { Haptics.tap(); Task { await ent.manageSubscription() } } label: {
                Text("Manage or cancel the subscription").textStyle(.caption, tint: Theme.accent, weight: .semibold).frame(minHeight: 32, alignment: .leading)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("plans-manage")
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StoreSurface(tint: Theme.gold, radius: Theme.Radius.card))
    }

    private func card(_ s: Spec) -> some View {
        let best: Bool = s.product == .plusYearly
        let price: String = ent.price(s.product)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                Text(s.billing).textStyle(.caption, tint: s.product.isPlus ? Theme.accent : Theme.ink, weight: .semibold).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if best { StoreTag(text: "Best value") }
            }
            Text(s.name).textStyle(.title)
            Text(s.summary).textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ForEach(s.includes, id: \.self) { (line: String) in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        GlyphView(glyph: Glyph.check, size: 12, weight: 1.8, tint: Theme.gain)
                        Text(line).textStyle(.caption, tint: Theme.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !s.excludes.isEmpty { Text(s.excludes).textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true) }
            }
            Hairline()
            HStack(alignment: .center, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(price.isEmpty ? "..." : priceLine(s.product, price)).textStyle(.headline, numeric: true)
                    if let extra = extraLine(s.product, price) { Text(extra).textStyle(.caption, tint: Theme.gain).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: Theme.Space.s)
                Button { Haptics.tap(); Task { await ent.purchase(s.product) } } label: {
                    Text(buttonTitle(s.product)).textStyle(.headline, tint: Theme.accentInk)
                        .padding(.horizontal, Theme.Space.l).frame(minHeight: 44)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(PressableStyle())
                .disabled(ent.isBusy || price.isEmpty)
                .accessibilityIdentifier("plan-\(s.product.rawValue)")
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StoreSurface(tint: Theme.gold, glow: best, radius: Theme.Radius.card))
        .storeSheen(radius: Theme.Radius.card, enabled: best)
        .accessibilityElement(children: .contain)
    }

    private func priceLine(_ p: LedgerProduct, _ price: String) -> String {
        switch p {
        case .plusYearly: return price + " a year"
        case .plusMonthly: return price + " a month"
        default: return price + ", once"
        }
    }

    private func extraLine(_ p: LedgerProduct, _ price: String) -> String? {
        guard p.isPlus else { return nil }
        if ent.trialEligible, let trial = ent.trialLength(p) { return "\(trial) free, then \(priceLine(p, price))" }
        if p == .plusYearly, !ent.yearlySaving.isEmpty { return ent.yearlySaving + " against paying monthly" }
        return nil
    }

    private func buttonTitle(_ p: LedgerProduct) -> String {
        if ent.isBusy { return "Working..." }
        if p.isPlus { return ent.trialEligible ? "Try free" : "Subscribe" }
        return "Buy"
    }

    private var comparison: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Compare").capsLabel(Theme.inkFaint)
            Grid(alignment: .center, horizontalSpacing: Theme.Space.s, verticalSpacing: Theme.Space.s) {
                GridRow {
                    Color.clear.frame(height: 1).gridColumnAlignment(.leading)
                    Text("Plus").textStyle(.headline)
                    Text("Pro").textStyle(.headline)
                    Text("Founder").textStyle(.headline)
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    label("How you pay")
                    word("Subscription")
                    word("Once")
                    word("Once")
                }
                row("Every locked item, 3 save slots", true, true, true)
                row("No ads", true, true, true)
                row("Premium Season Pass track", true, false, false)
                row("Founder mark in Settings", false, false, true)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StoreSurface(tint: Theme.gold, radius: Theme.Radius.card))
        .accessibilityIdentifier("plans-compare")
    }

    private func label(_ text: String) -> some View {
        Text(text).textStyle(.caption, tint: Theme.ink).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func word(_ text: String) -> some View {
        Text(text).textStyle(.caption, tint: Theme.inkSoft).multilineTextAlignment(.center).minimumScaleFactor(0.8)
    }

    private func mark(_ on: Bool) -> some View {
        Group {
            if on { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.gain) }
            else { Text("-").textStyle(.caption, tint: Theme.inkFaint) }
        }
        .accessibilityLabel(on ? "Included" : "Not included")
    }

    private func row(_ title: String, _ plus: Bool, _ pro: Bool, _ founder: Bool) -> some View {
        GridRow {
            label(title)
            mark(plus)
            mark(pro)
            mark(founder)
        }
    }
}
