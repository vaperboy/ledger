import SwiftUI
import GameCore
import Countries
import Finance
import Simulation

struct TaxLine: Identifiable {
    var id: String
    var title: String
    var rule: String
    var amount: Double
}

enum TaxExplainer {
    static func lines(_ b: PersonalFinance.TaxBreakdown, country c: Country, money: (Double) -> String) -> [TaxLine] {
        var out: [TaxLine] = []
        if b.incomeTax > 0 || b.withheld > 0 || b.incomeDue != 0 {
            var rule: String = "\(money(b.incomeTax)) on \(money(b.taxableIncome)) of salary"
            if b.withheld > 0 { rule += ", less \(money(b.withheld)) already withheld or paid in advance" }
            out.append(TaxLine(id: "income", title: b.incomeDue < 0 ? "Income tax refund" : "Income tax", rule: rule + ".", amount: b.incomeDue))
        }
        if b.dividends > 0 || b.dividendTax > 0 {
            var rule: String = "\(Currency.percent(c.dividendTax, decimals: 2)) on \(money(b.dividends)) of dividends"
            if b.shield > 0 { rule += " after a \(money(b.shield)) tax-free shield" }
            out.append(TaxLine(id: "dividend", title: "Dividend tax", rule: rule + ".", amount: b.dividendTax))
        }
        if b.gainsTax > 0, c.capitalGainsTax > 0 {
            let base: Double = b.gainsTax / c.capitalGainsTax
            out.append(TaxLine(id: "gains", title: "Tax on gains", rule: "\(Currency.percent(c.capitalGainsTax, decimals: 2)) on \(money(base)) of profit from selling investments.", amount: b.gainsTax))
        }
        if b.interestTax > 0, c.savingsInterestTax > 0 {
            let base: Double = b.interestTax / c.savingsInterestTax
            out.append(TaxLine(id: "interest", title: "Tax on interest", rule: "\(Currency.percent(c.savingsInterestTax, decimals: 2)) on \(money(base)) of deposit interest.", amount: b.interestTax))
        }
        if b.wealthTax > 0 {
            out.append(TaxLine(id: "wealth", title: "Wealth tax", rule: "\(Currency.percent(c.wealthRate, decimals: 2)) a year on the part of your wealth above the allowance.", amount: b.wealthTax))
        }
        return out
    }
}

struct TaxTable: View {
    @EnvironmentObject var store: GameStore
    var title: String
    var breakdown: PersonalFinance.TaxBreakdown
    var country: Country

    var body: some View {
        let lines: [TaxLine] = TaxExplainer.lines(breakdown, country: country) { (v: Double) -> String in store.short(v) }
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title).capsLabel()
            if lines.isEmpty {
                Text("No personal tax is due.").popupText(.caption)
            }
            ForEach(Array(lines.enumerated()), id: \.element.id) { (n: Int, l: TaxLine) in
                if n > 0 { Hairline() }
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(l.title).popupText(.body)
                        Spacer(minLength: Theme.Space.s)
                        Text(store.short(l.amount)).popupText(.rowValue).lineLimit(1)
                    }
                    Text(l.rule).popupText(.caption).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            Hairline()
            HStack(alignment: .firstTextBaseline) {
                Text("Still to settle").popupText(.rowValue)
                Spacer(minLength: Theme.Space.s)
                Text(store.short(breakdown.total)).popupText(.rowValue).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct YearTaxBlock: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        if let e = store.engine, let b = e.lastTaxAssessment(), e.state.week - b.week <= 8 {
            TaxTable(title: "Your personal tax this year", breakdown: b, country: e.context.homeCountry(e.state))
        }
    }
}

struct TaxEstimateCard: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var open = false

    @ViewBuilder var body: some View {
        let b: PersonalFinance.TaxBreakdown = engine.taxEstimate()
        let owed: Double = engine.state.tax.pending
        if b.annual > 0 || b.total > 0 || owed > 0 {
            card(b, owed: owed)
                .centerSheet(isPresented: $open, title: "How the tax adds up") {
                    TaxTable(title: "Estimate if the year ended now", breakdown: b, country: engine.context.homeCountry(engine.state))
                        .environmentObject(store)
                }
        }
    }

    private func card(_ b: PersonalFinance.TaxBreakdown, owed: Double) -> some View {
        let liquid: Double = max(0, engine.state.cash)
        let covered: Bool = b.total <= liquid
        let share: Double = b.total > 0 ? min(1, liquid / b.total) : 1
        let weeks: Int = PersonalFinance.weeksToYearEnd(week: engine.state.week)
        let due: String = GameCalendar.dateString(week: engine.state.week + weeks, dayOffset: 6)
        return CardSection(title: "Tax this year (estimate)", trailing: {
            Button("How it adds up") { open = true }.buttonStyle(TertiaryButtonStyle(size: .compact))
        }) {
            HStack(alignment: .firstTextBaseline) {
                Text(store.short(b.annual)).textStyle(.figure, tint: P.ink).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: Theme.Space.s)
                Text("Paid as you earn it").textStyle(.caption, tint: P.inkFaint)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Paid so far").textStyle(.caption, tint: P.inkFaint)
                Spacer(minLength: Theme.Space.s)
                Text(store.short(b.paidSoFar)).textStyle(.caption, tint: P.inkSoft)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(b.total < 0 ? "Refund at year end (\(due))" : "Settled at year end (\(due))").textStyle(.caption, tint: P.inkFaint)
                Spacer(minLength: Theme.Space.s)
                Text(store.short(abs(b.total))).textStyle(.caption, tint: b.total > 0 && !covered ? P.loss : P.inkSoft)
            }
            ProgressLine(fraction: share, tint: covered ? P.gain : P.loss)
            Text(covered
                 ? "Tax is taken when you receive the money. Only the difference is settled at year end."
                 : "Your cash of \(store.short(liquid)) are \(store.short(b.total - liquid)) short. Take dividends, sell investments or arrange a loan before then.")
                .textStyle(.caption, tint: covered ? P.inkFaint : P.warn).fixedSize(horizontal: false, vertical: true)
            if owed > 0 {
                Text("\(store.short(owed)) from last year is still unpaid: answer the tax decision in the Inbox.")
                    .textStyle(.caption, tint: P.loss).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
