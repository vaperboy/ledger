import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Events
import Simulation

enum HoldingStartupSheet: Identifiable, Hashable {
    case back(Int), more(Int), sell(Int)

    var id: String {
        switch self {
        case .back(let n): return "hsu-back-\(n)"
        case .more(let n): return "hsu-more-\(n)"
        case .sell(let n): return "hsu-sell-\(n)"
        }
    }
}

struct HoldingStartupStakes: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var sheet: HoldingStartupSheet?

    var body: some View {
        let cur: Currency = engine.currency(for: company)
        let stakes: [StartupHolding.Stake] = engine.holdingStartupStakes(holdingID: company.id)
        let pitches: [Startups.Pitch] = engine.startupPitchesOnOffer
        return Group {
            if !stakes.isEmpty || !pitches.isEmpty {
                MoreBlock(title: "Startup stakes", card: false, trailing: { Text("\(stakes.filter { (s: StartupHolding.Stake) -> Bool in s.live }.count)").textStyle(.caption, tint: Theme.inkFaint) }) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(stakes.enumerated()), id: \.element.id) { (n: Int, s: StartupHolding.Stake) in
                            if n > 0 { Hairline().padding(.leading, 40 + Theme.Space.m) }
                            stakeCard(s, cur)
                        }
                        if !pitches.isEmpty {
                            Text("Pitches open now").capsLabel(Theme.inkFaint)
                                .padding(.top, stakes.isEmpty ? 0 : Theme.Space.m).padding(.bottom, Theme.Space.xs)
                            ForEach(Array(pitches.enumerated()), id: \.element.id) { (n: Int, p: Startups.Pitch) in
                                if n > 0 { Hairline() }
                                pitchRow(p, cur)
                            }
                        }
                    }
                }
            }
        }
        .centerSheet(item: $sheet, category: .detail, tone: .info) { (sh: HoldingStartupSheet) in sheetContent(sh) }
    }

    private func stakeCard(_ s: StartupHolding.Stake, _ cur: Currency) -> some View {
        let id: Int = s.id
        let status: String = s.live ? s.stageName : (s.failed ? "Failed" : "Sold")
        let row = LedgerRow(leading: .thumb(ThumbSpec(kind: .trade, key: s.sector, glyph: Glyph.ventures, initials: s.name, shape: .square)),
                            title: s.name,
                            subtitle: "\(status) \u{00B7} \(holdingPct((s.percent * 10).rounded() / 10)) \u{00B7} \(s.tier.title)",
                            value: cur.tidyShort(s.value), valueNote: "paid " + cur.tidyShort(s.paid), chevron: s.live)
            .contentShape(Rectangle())
        return Group {
            if s.live {
                Menu {
                    Button("Buy more\u{2026}") { sheet = .more(id) }
                    Button("Sell part\u{2026}") { sheet = .sell(id) }
                } label: { row }
                .menuStyle(.button)
                .buttonStyle(PressableStyle())
            } else {
                row
            }
        }
        .accessibilityIdentifier("holding-startup-\(id)")
    }

    private func pitchRow(_ p: Startups.Pitch, _ cur: Currency) -> some View {
        LedgerRow(leading: .thumb(ThumbSpec(kind: .trade, key: p.sector, glyph: Glyph.ventures, initials: p.name, shape: .square)),
                  title: p.name, subtitle: "\(p.sector) \u{00B7} \(p.blurb)",
                  value: cur.tidyShort(p.raise), valueNote: "at \(cur.tidyShort(p.postMoney))",
                  pill: "Back it", pillTone: .good,
                  identifier: "holding-startup-pitch-\(p.id)") { sheet = .back(p.id) }
    }

    @ViewBuilder private func sheetContent(_ sh: HoldingStartupSheet) -> some View {
        switch sh {
        case .back(let id): HoldingBackStartupSheet(holdingID: company.id, pitchID: id).environmentObject(store)
        case .more(let id): HoldingBuyMoreStartupSheet(holdingID: company.id, stakeID: id).environmentObject(store)
        case .sell(let id): HoldingSellStartupSheet(holdingID: company.id, stakeID: id).environmentObject(store)
        }
    }
}
