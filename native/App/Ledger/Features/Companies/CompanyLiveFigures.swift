import SwiftUI
import GameCore
import Simulation

/// The company page's main figures moving: the week so far (it grows as each day plays, and only the difference rolls), with how the last
/// closed week moved against the one before it. A holding shows what it earned by source instead, since it sells nothing.
struct CompanyLiveFigures: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    var body: some View {
        if company.status == .open {
            if company.type == "hold" {
                holdingIncome
            } else {
                weekFigures
            }
        }
    }

    // MARK: Trading company

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

    /// One figure: the week so far at the right, and under the name the last closed week with its change on the week before.
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

    // MARK: Holding

    @ViewBuilder private var holdingIncome: some View {
        let id: Int = company.id
        let week: Int = engine.state.week
        let income: HoldingIncome? = (store.memo("coHold\(id)") { (e: GameEngine) -> HoldingIncome? in e.holdingIncome(companyID: id, weeks: max(0, week - 51)...week) }).flatMap { $0 }
        if let income, !income.isEmpty {
            let money: (Double) -> String = { (v: Double) -> String in store.short(v, in: company) }
            LedgerSection("Income") {
                VStack(spacing: 0) {
                    if abs(income.dividends) >= 0.5 {
                        incomeRow("Dividends from your companies", sub: "paid in over the last year", income.dividends, money)
                    }
                    if abs(income.dividends) >= 0.5 && abs(income.fundGains) >= 0.5 { CardLine() }
                    if abs(income.fundGains) >= 0.5 {
                        incomeRow("Gains on investments", sub: "treasury funds against what was paid", income.fundGains, money)
                    }
                }
            }
        }
    }

    private func incomeRow(_ label: String, sub: String, _ value: Double, _ money: @escaping (Double) -> String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(label).textStyle(.body)
                Text(sub).textStyle(.caption, tint: Theme.inkFaint)
            }
            Spacer(minLength: Theme.Space.s)
            ArrowAmount(gain: value, format: money, live: true, roll: true, step: .headline)
        }
        .padding(.vertical, Theme.Space.s)
        .accessibilityElement(children: .combine)
    }
}
