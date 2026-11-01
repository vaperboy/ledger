import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Stats > Performance: how much of its capacity the company uses, what it earns a week and how demand compares with what it can serve,
/// week by week. (Revenue and profit by month and last week's picture are on the Overview.) Read from `operationsFigures`.
struct CompanyPerformance: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    private var figures: OperationsFigures? { engine.operationsFigures(companyID: company.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            topCards
            demandChart
        }
    }

    private var topCards: some View {
        let f: OperationsFigures? = figures
        return HStack(alignment: .top, spacing: 10) {
            capacityCard(f).frame(maxWidth: .infinity)
            profitCard(f).frame(maxWidth: .infinity)
        }
    }

    private func capacityCard(_ f: OperationsFigures?) -> some View {
        let use: Double? = f?.capacityUse
        let big: String = use.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
        let sub: String = use == nil ? "No trading week yet" : (f?.demandIsLimit == true ? "Demand is the limit" : "Capacity is the limit")
        return Card(padding: 12, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Capacity used").font(.system(size: 12.5)).foregroundStyle(Theme.gold)
                Text(big).font(.hero(32)).foregroundStyle(Theme.ivory).minimumScaleFactor(0.6).lineLimit(1)
                Text(sub).font(.system(size: 11.5)).foregroundStyle(Theme.caution).lineLimit(2)
            }
        }
    }

    private func profitCard(_ f: OperationsFigures?) -> some View {
        let profit: Double? = f?.profitPerWeek
        let big: String = profit.map { ($0 < 0 ? "−" : "") + store.short(abs($0), in: company) } ?? "–"
        return Card(padding: 12, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Profit a week").font(.system(size: 12.5)).foregroundStyle(Theme.gold)
                Text(big).font(.hero(32)).foregroundStyle((profit ?? 0) < 0 ? Theme.loss : Theme.ivory).minimumScaleFactor(0.6).lineLimit(1)
                profitChange(f)
            }
        }
    }

    @ViewBuilder private func profitChange(_ f: OperationsFigures?) -> some View {
        if let d = f?.profitChangePerWeek {
            let up: Bool = d >= 0
            Text((up ? "▲ +" : "▼ −") + store.short(abs(d), in: company) + " vs last month")
                .font(.system(size: 11.5)).foregroundStyle(up ? Theme.gain : Theme.loss).lineLimit(2)
        } else {
            Text("No month to compare yet").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
        }
    }

    // MARK: Demand against capacity

    private var demandChart: some View {
        let weeks: [OperationsFigures.Week] = figures?.weeks ?? []
        return Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("DEMAND AGAINST CAPACITY").capsLabel()
                    Spacer(minLength: 8)
                    Text("last 8 weeks").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                }
                if weeks.isEmpty {
                    Text("Shows after the first trading week.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted).padding(.vertical, 20)
                } else {
                    DemandCapacityChart(weeks: weeks)
                }
            }
        }
    }
}
