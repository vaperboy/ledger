import SwiftUI
import GameCore
import Simulation

struct CompanyLiveFigures: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    var body: some View {
        if company.status == .open {
            weekFigures
        }
    }

    @ViewBuilder private var weekFigures: some View {
        let id: Int = company.id
        let cmp: CompanyWeekCompare? = (store.memo("coWeek\(id)") { (e: GameEngine) -> CompanyWeekCompare? in e.companyWeekCompare(companyID: id) }).flatMap { $0 }
        if let c = cmp {
            LedgerSection("This week so far") {
                VStack(spacing: 0) {
                    row("Sales", c.soFar.sales, gain: c.soFar.sales, last: c.last?.sales, before: c.before?.sales, cost: false, title: c.lastTitle)
                    CardLine()
                    row("Wages", c.soFar.wages, gain: -c.soFar.wages, last: c.last?.wages, before: c.before?.wages, cost: true, title: c.lastTitle)
                    CardLine()
                    row("All costs", c.soFar.costs, gain: -c.soFar.costs, last: c.last?.costs, before: c.before?.costs, cost: true, title: c.lastTitle)
                    CardLine()
                    row("Profit", c.soFar.profit, gain: c.soFar.profit, last: c.last?.profit, before: c.before?.profit, cost: false, title: c.lastTitle)
                }
            }
        }
    }

    private func row(_ label: String, _ now: Double, gain: Double, last: Double?, before: Double?, cost: Bool, title: String?) -> some View {
        let money: (Double) -> String = { (v: Double) -> String in store.short(v, in: company) }
        return HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(label).textStyle(.body)
                if let last {
                    HStack(spacing: Theme.Space.xs) {
                        Text((title ?? "Last week") + " " + money(last)).textStyle(.caption, tint: Theme.inkFaint, numeric: true).lineLimit(1)
                        ChangeNote(now: last, before: before, isCost: cost, against: "the week before", format: money)
                    }
                }
            }
            Spacer(minLength: Theme.Space.s)
            ArrowAmount(gain: gain, amount: now, format: money, live: true, roll: true, step: .headline)
        }
        .padding(.vertical, Theme.Space.s)
        .accessibilityElement(children: .combine)
    }

}
