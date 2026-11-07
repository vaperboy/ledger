import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The hero of Manage: how much of its capacity the company uses, what limits it, and demand against capacity week by week. Read from
/// `operationsFigures` (cached per engine state).
struct CompanyPerformance: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @Environment(\.outsidePalette) private var P

    var body: some View {
        let id: Int = company.id
        let f: OperationsFigures? = store.memo("coOps\(id)") { $0.operationsFigures(companyID: id) } ?? nil
        let use: Double? = f?.capacityUse
        let weeks: [OperationsFigures.Week] = f?.weeks ?? []
        let full: Bool = f?.demandIsLimit == false
        let note: String = use == nil ? "Shows after the first trading week" : (full ? "Capacity is the limit: customers are turned away" : "Demand is the limit: there is room for more customers")
        let trend: [Double] = weeks.map { (w: OperationsFigures.Week) -> Double in w.capacity > 0 ? min(w.demand, w.capacity) / w.capacity : 0 }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            CompanyHero(label: "Capacity used", value: use.map { "\(Int(($0 * 100).rounded()))%" } ?? "\u{2013}", tint: full ? P.warn : nil,
                        change: note, changeTint: full ? P.warn : P.inkSoft, trend: trend)
            if !weeks.isEmpty {
                ChartFrame(title: "Demand against capacity", period: "last \(weeks.count) weeks", height: 84) {
                    DemandCapacityChart(weeks: weeks)
                }
            }
        }
    }
}
