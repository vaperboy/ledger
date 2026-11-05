import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The page block of a product line (insurance cover, loan or deposit account, fund fee class, power tariff, oil field, group service): what one unit
/// earns, what it costs by cause, the risk it carries and the capital behind it, with the profit or loss at the price on the slider.
/// It is shown from `WaveItemBlocks`; it draws nothing for any other item.
struct Wave11ItemBlock: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var itemID: String
    /// The price on the shared slider, in the units of the item list.
    var price: Double
    var cur: Currency

    var body: some View {
        if let e = store.engine, let u = Wave11.economics(e.state, companyID: companyID, itemID: itemID, data: e.data) {
            let listMarket: Double = SalesItems.rows(e.state, companyID: companyID, data: e.data).first(where: { $0.id == itemID })?.marketPrice ?? 0
            let real: Double = listMarket > 0 ? price / listMarket * u.marketPrice : u.price
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                book(u)
                costs(u, real)
                if u.risk > 0 || u.reserve > 0 { risk(u) }
                if !u.note.isEmpty { Text(u.note).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4) }
            }
        }
    }

    private func count(_ v: Double) -> String { String(format: "%.0f", v) }

    private func book(_ u: Wave11.Econ) -> some View {
        TeamGroup(u.kindLabel) {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: u.unitWord.capitalized + "s", value: count(u.units), rule: false)
                    FlatRow(label: u.sizeLabel, value: itemAmount(u.size, cur))
                    if u.volume > 0 { FlatRow(label: "Sold a week", value: count(u.volume), sub: u.unitWord) }
                }
            }
        }
    }

    private func costs(_ u: Wave11.Econ, _ real: Double) -> some View {
        let atPrice = Wave11.atPrice(u, price: real)
        let word: String = atPrice.profitPerUnit >= 0 ? "profit " : "loss "
        let line: String = word + itemAmount(abs(atPrice.profitPerUnit), cur) + " per " + u.unitWord + " (" + String(format: "%.0f%%", atPrice.margin * 100) + ")"
        return TeamGroup("What it costs") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: "Price", value: itemAmount(real, cur), sub: "per " + u.unitWord + " " + u.priceUnit, rule: false)
                    ForEach(u.parts, id: \.label) { (p: Wave11.Part) in
                        FlatRow(label: p.label, value: itemAmount(p.perUnit, cur), sub: "per " + u.unitWord)
                    }
                    if u.credit != 0 { FlatRow(label: "Income on the float", value: itemAmount(u.credit, cur), sub: "per " + u.unitWord) }
                    FlatRow(label: "Wages, premises and overheads", value: itemAmount(u.overheadPerUnit, cur), sub: "per " + u.unitWord)
                    FlatRow(label: "Price that breaks even", value: itemAmount(u.costPerUnit, cur), sub: "per " + u.unitWord)
                    FlatRow(label: "At this price", value: line, tint: atPrice.profitPerUnit >= 0 ? Theme.gain : Theme.loss)
                    FlatRow(label: "This line now", value: (u.weeklyProfit >= 0 ? "profit " : "loss ") + itemAmount(abs(u.weeklyProfit), cur) + " a week", tint: u.weeklyProfit >= 0 ? Theme.gain : Theme.loss)
                }
            }
        }
    }

    private func risk(_ u: Wave11.Econ) -> some View {
        TeamGroup("Risk") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    if u.risk > 0 { FlatRow(label: u.riskLabel, value: itemAmount(u.risk, cur), sub: "per " + u.unitWord, rule: false) }
                    if u.stress > u.risk { FlatRow(label: "In a bad year", value: itemAmount(u.stress, cur), sub: "per " + u.unitWord) }
                    if u.swing > 0 { FlatRow(label: "Swing of the result", value: String(format: "%.0f%%", u.swing * 100)) }
                    if u.reserve > 0 { FlatRow(label: u.reserveLabel, value: itemAmount(u.reserve, cur)) }
                }
            }
        }
    }
}
