import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

struct DonateScreen: View {
    var e: GameEngine
    var r: CountryRead
    var back: () -> Void
    @EnvironmentObject var store: GameStore
    @State private var text = ""
    @State private var confirming = false
    private let P: OutsidePalette = .pledge

    private var amount: Double? {
        guard let v = CivicWords.number(text) else { return nil }
        let a: Double = v.rounded()
        return a >= 1 ? a : nil
    }

    private var cash: Double { e.state.cash }

    private var blocked: String? {
        guard let a = amount else { return "Type an amount of at least \(r.cur.tidyDisplay(1))." }
        if a > cash { return "You hold \(r.cur.tidyDisplay(cash)) in cash." }
        return nil
    }

    var body: some View {
        CivicPage(spacing: 20) {
            CivicHeader(title: "Donate", subtitle: "A gift to the treasury of \(r.name)", onBack: back)
            pledge
            roll
        }
        .outsideScreen(.pledge)
        .accessibilityIdentifier("country-donate")
    }

    private var pledge: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                GlyphView(glyph: Glyph.coinStack, size: 20, weight: 1.6, tint: P.accent)
                Text("Pledge").textStyle(.label)
                Spacer(minLength: 0)
                Text("You hold \(r.cur.tidyShort(cash))").textStyle(.caption)
            }
            Text("What this does not buy").font(.system(size: 22, weight: .medium, design: .serif)).foregroundStyle(P.ink)
            VStack(alignment: .leading, spacing: 6) {
                noLine("No office and no vote.")
                noLine("No price support and no favours.")
                noLine("The gift is public, with your name, and is final.")
            }
            Rectangle().fill(P.accent.opacity(0.4)).frame(height: 1)
            CivicAmountField(text: $text, symbol: r.cur.country.currencySymbol, ink: P.ink, soft: P.inkSoft, fill: P.cardDeep, edge: P.line)
            quick
            if confirming, let a = amount, blocked == nil { confirmBar(a) } else { give }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(P.accent.opacity(0.45), lineWidth: 1.5))
        .onChange(of: text) { _, _ in confirming = false }
    }

    private func noLine(_ t: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\u{2013}").foregroundStyle(P.accent)
            Text(t).textStyle(.body).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var quick: some View {
        HStack(spacing: 8) {
            ForEach([0.01, 0.05, 0.25], id: \.self) { (f: Double) in
                let a: Double = (cash * f).rounded()
                Button {
                    Haptics.choose()
                    text = String(Int(a))
                } label: {
                    Text(CivicWords.pct(f) + " of cash").font(.system(size: 12, weight: .semibold)).foregroundStyle(P.accent)
                        .padding(.horizontal, 12).frame(minHeight: 36)
                        .background(Capsule().strokeBorder(P.accent.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                .disabled(a < 1)
            }
            Spacer(minLength: 0)
        }
    }

    private var give: some View {
        PrimaryAction(title: amount.map { "Give " + r.cur.tidyDisplay($0) } ?? "Give", blockedReason: blocked, identifier: "donate-give") {
            confirming = true
        }
    }

    private func confirmBar(_ a: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Give \(r.cur.tidyDisplay(a)) to the treasury? It cannot be taken back.").textStyle(.headline)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Cancel") { confirming = false }.buttonStyle(SecondaryButtonStyle(fullWidth: true))
                Button("Yes, give") { donate(a) }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
            }
        }
    }

    private func donate(_ a: Double) {
        let country: String = r.code
        let ok: Bool = store.govRun { (s: inout GameState, _: GameData, _: FinanceContext) -> Void in
            try GovernmentBridge.donate(&s, country: country, amount: a)
        }
        confirming = false
        guard ok else { return }
        text = ""
        Haptics.success()
        store.outcome(chosen: "Donated \(r.cur.tidyDisplay(a))", result: "The gift is in the treasury and on the public roll.")
    }

    private var roll: some View {
        let list: [GovDonation] = Array(r.gov.donations.prefix(30))
        let total: Double = r.gov.donations.reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Roll of donors").textStyle(.label)
                Spacer(minLength: 8)
                if !list.isEmpty { Text("Given in all: " + r.cur.tidyShort(total)).textStyle(.caption) }
            }
            VStack(alignment: .leading, spacing: 0) {
                if list.isEmpty {
                    Text("No one has given yet. The first name goes at the top.").textStyle(.body).padding(16)
                } else {
                    ForEach(Array(list.enumerated()), id: \.element.id) { (i: Int, d: GovDonation) in
                        if i > 0 { Rectangle().fill(P.hairline).frame(height: 1) }
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.shown(d.name, account: d.account)).font(.system(size: 16, weight: .medium, design: .serif)).foregroundStyle(P.ink)
                                Text(CivicWords.date(d.week)).textStyle(.caption, tint: P.inkFaint)
                            }
                            Spacer(minLength: 8)
                            Text(r.cur.tidyDisplay(d.amount)).font(.system(size: 16, weight: .semibold, design: .serif).monospacedDigit()).foregroundStyle(P.accent)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(P.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(P.line, lineWidth: 1))
        }
    }
}
