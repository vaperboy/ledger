import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct CompanyPerformance: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @Environment(\.outsidePalette) private var P

    var body: some View {
        let id: Int = company.id
        let f: OperationsFigures? = engine.operationsFigures(companyID: id)
        let use: Double? = f?.capacityUse
        let weeks: [OperationsFigures.Week] = f?.weeks ?? []
        let limit: SalesLimit.Kind = f?.limit.kind ?? .unknown
        let full: Bool = limit == .capacity
        let none: Bool = limit == .stopped
        let held: Bool = limit == .held
        let note: String = f?.limit.text ?? "Shows after the first trading week"
        let trend: [Double] = weeks.map { (w: OperationsFigures.Week) -> Double in w.capacityUse }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            CompanyHero(label: "Capacity used", value: none ? "None" : (use.map { "\(Int(saturating: ($0 * 100).rounded()))%" } ?? "\u{2013}"), tint: none ? P.loss : (full ? P.warn : nil),
                        change: note, changeTint: none ? P.loss : (full || held ? P.warn : P.inkSoft), trend: trend)
            if !weeks.isEmpty {
                ChartFrame(title: "Demand against capacity", period: "last \(weeks.count) weeks", height: 84) {
                    DemandCapacityChart(weeks: weeks)
                }
            }
        }
    }
}
