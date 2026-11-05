import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The page block of a rentable unit (building, car, room type, gaming seat): units, occupancy, what one rented night, day, hour or week costs and where the
/// rate breaks even. Shown from `TradeItemBlocks`; it draws nothing for any other item.
struct RentalUnitBlock: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var itemID: String

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID),
           let u = RentalUnits.economics(e.state, companyID: companyID, itemID: itemID, data: e.data) {
            let cur: Currency = e.currency(for: co)
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                usage(u)
                costs(u, cur)
            }
        }
    }

    private func percent(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }

    private func usage(_ u: RentalUnits.UnitEconomics) -> some View {
        let seasonText: String = String(format: "%+.0f%% against an average month", (u.seasonIndex - 1) * 100)
        return TeamGroup(u.kindLabel) {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: "Units", value: String(format: "%.0f", u.units), rule: false)
                    FlatRow(label: "Rented last week", value: String(format: "%.0f of %.0f a week", u.rented, u.capacity), sub: "per " + u.per)
                    FlatRow(label: "Occupancy", value: percent(u.occupancy))
                    FlatRow(label: "Booked ahead", value: "\(u.booked)", sub: "estimate for the coming week")
                    FlatRow(label: "This month", value: seasonText)
                    if !u.status.isEmpty { FlatRow(label: "Status", value: u.status == "repair" ? "Being repaired" : u.status) }
                }
            }
        }
    }

    private func costs(_ u: RentalUnits.UnitEconomics, _ cur: Currency) -> some View {
        let profitText: String = (u.weeklyProfit >= 0 ? "profit " : "loss ") + itemAmount(u.weeklyProfit, cur) + " a week"
        return TeamGroup("What it costs") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: "Cost of one rented " + u.per, value: itemAmount(u.costPerPeriod, cur), sub: "at the last quarter's occupancy", rule: false)
                    FlatRow(label: "Rate that breaks even", value: itemAmount(u.breakEvenRate, cur), sub: "per " + u.per)
                    FlatRow(label: "Only when rented", value: itemAmount(u.variablePerPeriod, cur), sub: "cleaning, damage, commission")
                    ForEach(u.fixedParts, id: \.label) { (p: RentalUnits.Part) in
                        FlatRow(label: p.label, value: itemAmount(p.weekly, cur), sub: "a week")
                    }
                    FlatRow(label: "This unit now", value: profitText, tint: u.weeklyProfit >= 0 ? Theme.gain : Theme.loss)
                }
            }
        }
    }
}
