import SwiftUI
import GameCore
import Countries
import Finance
import Simulation

/// The Deposits tab. Personal account: the savings account and fixed deposits (the engine's `moveToSavings`, `openDeposit`). Investments
/// account: shares, crypto and funds with the trade sheet, the fund manager and the ventures link (`InvestContent`). A company account has
/// neither savings nor deposits.
struct BankDepositsTab: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var account: BankAccountID
    var detail: BankAccountDetail

    var body: some View {
        switch account {
        case .investments: InvestContent()
        case .personal: BankSavingsAndDeposits()
        case .company:
            Text("A company account has no savings or fixed deposits. Spare cash can be moved to your own account, or the company can pay it out.")
                .font(.system(size: 13)).foregroundStyle(P.inkSoft).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Savings and fixed deposits of the personal account.
struct BankSavingsAndDeposits: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    @State private var amount = 0.0
    @State private var depositWeeks = 26
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine {
            let cur = e.homeCurrency
            VStack(alignment: .leading, spacing: 12) {
                savings(e, cur)
                deposits(e, cur)
            }
            .confirmAction($pending)
        }
    }

    private func savings(_ e: GameEngine, _ cur: Currency) -> some View {
        let rate: String = Currency.percent(PersonalFinance.savingsRate(e.state), decimals: 2)
        return BankCard(title: "Savings", trailing: cur.tidyDisplay(e.state.savings) + " · " + rate) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Earns interest and can be moved back any day. Loan repayments draw on it when the current account is short.").font(.caption2).foregroundStyle(P.inkFaint)
                AmountField(title: "Amount", currency: cur, amount: $amount)
                HStack {
                    Button(amount > 0 ? "Save \(cur.tidyShort(amount))" : "Save") { move(amount, cur) }.buttonStyle(QuietButtonStyle()).disabled(amount <= 0 || amount > e.state.cash)
                    Button(amount > 0 ? "Withdraw \(cur.tidyShort(amount))" : "Withdraw") { move(-amount, cur) }.buttonStyle(QuietButtonStyle()).disabled(amount <= 0 || amount > e.state.savings)
                }
                if amount > e.state.cash && amount > e.state.savings && amount > 0 {
                    Text("More than either account holds: \(cur.tidyShort(max(0, e.state.cash))) current, \(cur.tidyShort(e.state.savings)) savings.").font(.caption2).foregroundStyle(P.caution)
                }
            }
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
                                            button: "Lock it") {
                        if store.act({ $0.openDeposit(amount: a, weeks: w) }) == true { Haptics.success(); store.show("\(cur.tidyShort(a)) locked until week \((store.engine?.state.week ?? 0) + w).", tone: "good"); amount = 0 }
                        else { Haptics.warning(); store.show("Not enough on the current account for that deposit.", tone: "warn") }
                    }
                }.buttonStyle(QuietButtonStyle()).disabled(amount <= 0)
                Text("Only the current account can fund a deposit; move savings back first if needed.").font(.caption2).foregroundStyle(P.inkFaint)
            }
        }
    }

    private func move(_ a: Double, _ cur: Currency) {
        guard a != 0 else { return }
        if store.act({ $0.moveToSavings(a) }) == true { Haptics.success(); store.show(a > 0 ? "\(cur.tidyShort(a)) moved to savings." : "\(cur.tidyShort(-a)) moved to the current account.", tone: "good"); amount = 0 }
        else { Haptics.warning(); store.show(a > 0 ? "Not that much on the current account." : "Not that much in savings.", tone: "warn") }
    }
}
