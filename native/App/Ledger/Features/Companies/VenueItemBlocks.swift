import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The page block of a venue item (entry tickets, tables, passes, memberships, lessons, bar, food, merchandise): what it sells against its capacity, what one sale
/// costs and where the price breaks even. Shown from `TradeItemBlocks`;
/// it draws nothing for any other item.
struct VenueItemBlock: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var itemID: String

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID),
           let u = VenueItems.economics(e.state, companyID: companyID, itemID: itemID, data: e.data) {
            let cur: Currency = e.currency(for: co)
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                usage(u)
                costs(u, cur)
            }
        }
    }

    private func percent(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }

    private func usage(_ u: VenueItems.Economics) -> some View {
        let seasonText: String = String(format: "%+.0f%% against an average month", (u.seasonIndex - 1) * 100)
        return TeamGroup(u.kindLabel) {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: "Sold last week", value: String(format: "%.0f", u.sold), sub: "per " + u.per, rule: false)
                    if u.capacity > 0 {
                        FlatRow(label: "Capacity", value: String(format: "%.0f a week", u.capacity), sub: u.capacityPerSession > 0 && u.capacityPerSession != u.capacity ? String(format: "%.0f per %@", u.capacityPerSession, u.sessionName) : "")
                        FlatRow(label: "Filled", value: percent(u.occupancy))
                    }
                    if u.isSub {
                        FlatRow(label: u.bundleDays > 0 ? "Pass holders (estimate)" : "Members", value: String(format: "%.0f", u.holders))
                        FlatRow(label: "Lost a month", value: percent(u.churnMonthly), sub: "of them leave")
                    }
                    if u.bundleDays > 0 { FlatRow(label: "Covers", value: String(format: "%.0f visits", u.bundleDays), sub: "price per visit above") }
                    if u.edge > 0 { FlatRow(label: "House edge", value: String(format: "%.1f%%", u.edge * 100), sub: String(format: "about %.0f played per sale", u.playedPerSale)) }
                    if u.booked > 0 { FlatRow(label: "Booked ahead", value: "\(u.booked)", sub: "estimate") }
                    FlatRow(label: "This month", value: seasonText)
                }
            }
        }
    }

    private func costs(_ u: VenueItems.Economics, _ cur: Currency) -> some View {
        let profitText: String = (u.weeklyProfit >= 0 ? "profit " : "loss ") + itemAmount(u.weeklyProfit, cur) + " a week"
        return TeamGroup("What it costs") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: "Cost of one sale", value: itemAmount(u.costPerSale, cur), sub: "at the last quarter's sales", rule: false)
                    FlatRow(label: "Price that breaks even", value: itemAmount(u.breakEvenPrice, cur), sub: "per " + u.per)
                    FlatRow(label: "Only when sold", value: itemAmount(u.variablePerSale, cur), sub: u.recipe)
                    if u.bundlePrice > 0 { FlatRow(label: "Whole pass at this price", value: itemAmount(u.bundlePrice, cur)) }
                    ForEach(u.fixedParts, id: \.label) { (p: VenueItems.Part) in
                        FlatRow(label: p.label, value: itemAmount(p.weekly, cur), sub: "a week")
                    }
                    FlatRow(label: "This item now", value: profitText, tint: u.weeklyProfit >= 0 ? Theme.gain : Theme.loss)
                }
            }
        }
    }
}
