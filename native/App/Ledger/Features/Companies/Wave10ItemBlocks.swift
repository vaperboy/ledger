import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The page block of a transport or logistics service (wave 10: ride, parcel, lane, voyage, route, warehouse service): sold against capacity (load factor), empty share,
/// lead time, what one unit costs by cause and the price that breaks even. The lead hooks it into `WaveItemBlocks` with `Wave10ItemBlock(companyID: companyID, itemID: itemID)`;
/// it draws nothing for any other item.
struct Wave10ItemBlock: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var itemID: String

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID),
           let info = Wave10.info(e.state, companyID: companyID, itemID: itemID, data: e.data) {
            let cur: Currency = e.currency(for: co)
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if info.kind == "service" { usage(info) }
                costs(info, cur)
            }
        }
    }

    private func percent(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }

    private func usage(_ info: Wave10.Info) -> some View {
        let u = info.economics
        let seasonText: String = String(format: "%+.0f%% against an average month", (u.seasonIndex - 1) * 100)
        let lead: String = info.leadDays == 0 ? "on demand" : "\(info.leadDays) days"
        return TeamGroup("How it runs") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: "Capacity it uses", value: String(format: "%.1f vehicles, bays or aircraft", u.units), sub: info.note, rule: false)
                    FlatRow(label: "Sold last week", value: String(format: "%.0f of %.0f", u.rented, u.capacity), sub: "per " + u.per)
                    FlatRow(label: "Load factor", value: percent(u.occupancy), sub: "sold against capacity")
                    FlatRow(label: "Empty at a normal load", value: percent(info.empty), sub: "empty running or empty seats")
                    FlatRow(label: "Lead time", value: lead)
                    FlatRow(label: "Booked ahead", value: "\(u.booked)", sub: "estimate for the coming week")
                    FlatRow(label: "This month", value: seasonText)
                }
            }
        }
    }

    private func costs(_ info: Wave10.Info, _ cur: Currency) -> some View {
        let u = info.economics
        let profitText: String = (u.weeklyProfit >= 0 ? "profit " : "loss ") + itemAmount(u.weeklyProfit, cur) + " a week"
        return TeamGroup("What it costs") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: "Cost of one " + u.per, value: itemAmount(u.costPerPeriod, cur), sub: "at the last quarter's load factor", rule: false)
                    FlatRow(label: "Price that breaks even", value: itemAmount(u.breakEvenRate, cur), sub: "per " + u.per)
                    FlatRow(label: "Only when sold", value: itemAmount(u.variablePerPeriod, cur), sub: "fuel, tolls, handling, commission")
                    ForEach(u.fixedParts, id: \.label) { (p: Wave8.Part) in
                        FlatRow(label: p.label, value: itemAmount(p.weekly, cur), sub: "a week")
                    }
                    if info.kind == "service" { FlatRow(label: "This service now", value: profitText, tint: u.weeklyProfit >= 0 ? Theme.gain : Theme.loss) }
                }
            }
        }
    }
}
