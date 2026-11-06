import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Capacity on Manage: how much of its capacity the company uses, what limits it, and demand against capacity week by week. Profit is on
/// the Overview (which links here for capacity). Read from `operationsFigures`.
struct CompanyPerformance: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @Environment(\.outsidePalette) private var P

    private var figures: OperationsFigures? { engine.operationsFigures(companyID: company.id) }

    var body: some View {
        let f: OperationsFigures? = figures
        let use: Double? = f?.capacityUse
        let weeks: [OperationsFigures.Week] = f?.weeks ?? []
        let note: String = use == nil ? "No trading week yet" : (f?.demandIsLimit == true ? "Demand is the limit" : "Capacity is the limit")
        return LedgerSection("Capacity", rule: false) {
            Figure(label: "Capacity used", value: use.map { "\(Int(($0 * 100).rounded()))%" } ?? "\u{2013}", note: note,
                   tint: f?.demandIsLimit == false ? P.warn : nil)
            ChartFrame(title: "Demand against capacity", period: "last 8 weeks", height: 96, isEmpty: weeks.isEmpty,
                       emptyText: "Shows after the first trading week.") {
                DemandCapacityChart(weeks: weeks)
            }
        }
    }
}
