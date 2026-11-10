import SwiftUI
import GameCore
import Businesses
import Simulation

private func priceMove(_ d: EnergyMarket.Direction) -> (symbol: String, up: Bool?) {
    switch d {
    case .up: return ("arrow.up.right", true)
    case .down: return ("arrow.down.right", false)
    case .flat: return ("arrow.right", nil)
    }
}

struct ExchangePriceBoard: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P

    var body: some View {
        if let e = store.engine {
            let snap: EnergyMarket.Snapshot = EnergyMarket.snapshot(e.state)
            let rows: [EnergyMarket.PriceRow] = EnergyMarket.worldPrices(e.state)
            VStack(spacing: 0) {
                MarketLabel(title: "Raw materials and energy", note: "against 12 weeks ago")
                energy(snap)
                ForEach(rows) { (r: EnergyMarket.PriceRow) in
                    Hairline()
                    row(r)
                }
                Text(snap.summary).textStyle(.caption, tint: P.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, Theme.Space.s)
            }
            .accessibilityIdentifier("exchange-price-board")
        }
    }

    private func energy(_ snap: EnergyMarket.Snapshot) -> some View {
        let mv: (symbol: String, up: Bool?) = priceMove(snap.direction)
        let tint: Color = mv.up == nil ? P.inkFaint : (mv.up == true ? P.gain : P.loss)
        return HStack(spacing: Theme.Space.m) {
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
        .accessibilityIdentifier("exchange-energy-row")
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
