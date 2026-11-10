import SwiftUI
import GameCore
import Countries
import Simulation

struct BankFixedDeposits: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    @State private var amount = 0.0
    @State private var depositWeeks = 26
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine {
            let cur = e.homeCurrency
            VStack(alignment: .leading, spacing: 12) {
                deposits(e, cur)
            }
            .confirmAction($pending)
        }
    }

    private func deposits(_ e: GameEngine, _ cur: Currency) -> some View {
        let q = e.depositQuote(amount: amount, weeks: depositWeeks)
        let held: Double = e.deposits.reduce(0) { $0 + $1.balance }
        return BankCard(title: "Fixed deposits", trailing: e.deposits.isEmpty ? "" : cur.tidyShort(held)) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                ForEach(e.deposits) { d in
                    ListRow(symbol: "lock.fill", tint: P.accent, title: "Fixed deposit at \(Currency.percent(d.rate, decimals: 2))",
                            subtitle: d.weeksLeft == 0 ? "Matures this week" : "Matures in \(d.weeksLeft) week\(d.weeksLeft == 1 ? "" : "s")", trailing: cur.tidyDisplay(d.balance))
                }
                AmountField(title: "Amount", currency: cur, amount: $amount)
                SegmentedChoice(items: GameEngine.depositTermChoices, title: { "\($0) weeks" }, selection: $depositWeeks)
                KeyFigures(items: [
                    .init(label: "Rate", value: Currency.percent(q.yearlyRate, decimals: 2), sub: "a year, fixed"),
                    .init(label: "Interest at the end", value: amount > 0 ? cur.tidyShort(q.interest) : "–", tint: P.gain),
                    .init(label: "Back to you", value: amount > 0 ? cur.tidyShort(amount + q.interest) : "–", sub: "in \(depositWeeks) weeks"),
                ])
                Button(amount > 0 ? "Lock \(cur.tidyShort(amount)) for \(depositWeeks) weeks" : "Enter an amount above") {
                    let a = amount, w = depositWeeks
                    pending = PendingAction(title: "Lock \(cur.tidyShort(a)) for \(w) weeks?",
                                            message: "It earns \(Currency.percent(q.yearlyRate, decimals: 2)) a year: \(cur.tidyDisplay(q.interest)) interest, paid with the money in \(w) weeks. Until then it is out of reach, also for bills. The interest is taxed as income.",
                                            button: "Lock it", amount: a, currency: cur) {
                        if store.act({ $0.openDeposit(amount: a, weeks: w) }) == true { Haptics.success(); store.show("\(cur.tidyShort(a)) locked until week \((store.engine?.state.week ?? 0) + w).", tone: "good"); amount = 0 }
                        else { Haptics.warning(); store.show("Not enough money in your account for that deposit.", tone: "warn") }
                    }
                }.buttonStyle(QuietButtonStyle()).disabled(amount <= 0)
            }
        }
    }
}
