import SwiftUI
import GameCore
import Businesses
import Simulation

/// The arrow symbol of a price move and whether it is up (green), down (red) or level (nil).
private func priceMove(_ d: EnergyMarket.Direction) -> (symbol: String, up: Bool?) {
    switch d {
    case .up: return ("arrow.up.right", true)
    case .down: return ("arrow.down.right", false)
    case .flat: return ("arrow.right", nil)
    }
}

/// The Energy row of the Market overview: what electricity costs now and why, in words.
struct EnergyMarketRow: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P

    var body: some View {
        if let e = store.engine {
            let snap: EnergyMarket.Snapshot = EnergyMarket.snapshot(e.state)
            let mv: (symbol: String, up: Bool?) = priceMove(snap.direction)
            let tint: Color = mv.up == nil ? P.inkFaint : (mv.up == true ? P.gain : P.loss)
            VStack(alignment: .leading, spacing: 0) {
                MarketLabel(title: "Energy")
                HStack(spacing: Theme.Space.m) {
                    Image(systemName: mv.symbol)
                        .font(.system(size: Theme.Icon.small, weight: .medium))
                        .foregroundStyle(tint)
                        .frame(width: Theme.Icon.large)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text("Electricity").textStyle(.headline)
                        Text("Demand \(snap.demandWord.lowercased()), supply \(snap.supplyWord.lowercased())").textStyle(.caption).lineLimit(2)
                    }
                    Spacer(minLength: Theme.Space.s)
                    VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                        Text(String(format: "%.0f%% of normal", snap.priceIndex * 100)).textStyle(.headline, numeric: true)
                        Text(String(format: "%+.0f%% in 12 weeks", snap.change * 100)).textStyle(.caption, tint: P.inkFaint, numeric: true)
                    }
                }
                .padding(.vertical, Theme.Space.m)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("market-energy-row")
            }
        }
    }
}

/// The World prices card: electricity and every commodity the economy prices, as an index where 100% is normal.
struct WorldPricesCard: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P

    var body: some View {
        if let e = store.engine {
            let rows: [EnergyMarket.PriceRow] = EnergyMarket.worldPrices(e.state)
            VStack(spacing: 0) {
                MarketLabel(title: "World prices", note: "against 12 weeks ago")
                ForEach(Array(rows.enumerated()), id: \.element.id) { (pair: (offset: Int, element: EnergyMarket.PriceRow)) in
                    if pair.offset > 0 { Hairline() }
                    row(pair.element)
                }
                Text(EnergyMarket.snapshot(e.state).summary).textStyle(.caption, tint: P.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, Theme.Space.s)
            }
            .accessibilityIdentifier("market-world-prices")
        }
    }

    private func row(_ r: EnergyMarket.PriceRow) -> some View {
        let mv: (symbol: String, up: Bool?) = priceMove(r.direction)
        let tint: Color = mv.up == nil ? P.inkFaint : (mv.up == true ? P.gain : P.loss)
        return HStack(spacing: Theme.Space.m) {
            Image(systemName: mv.symbol)
                .font(.system(size: Theme.Icon.small, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: Theme.Icon.large)
                .accessibilityHidden(true)
            Text(r.name).textStyle(.headline).lineLimit(1)
            Spacer(minLength: Theme.Space.s)
            VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                Text(String(format: "%.0f%%", r.index * 100)).textStyle(.headline, numeric: true)
                Text(String(format: "%+.0f%%", r.change * 100)).textStyle(.caption, tint: P.inkFaint, numeric: true)
            }
        }
        .padding(.vertical, Theme.Space.m)
        .accessibilityElement(children: .combine)
    }
}
