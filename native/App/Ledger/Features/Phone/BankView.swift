import SwiftUI
import GameCore
import Countries
import Finance
import Simulation

struct BankLoansTab: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var account: BankAccountID
    var loans: [BankLoan]

    @State private var applying = false
    @State private var prefill: Double?

    var body: some View {
        if let e = store.engine {
            VStack(alignment: .leading, spacing: 12) {
                if account != .investments { applyCard(e) }
                loansFor(e)
            }
            .centerSheet(isPresented: $applying, size: .tallBleed) { BankLoanApplyFlow(prefill: prefill) }
            .onAppear { openWithAmount() }
            .onChange(of: store.pendingLoanApply) { _, _ in openWithAmount() }
        }
    }

    private func openWithAmount() {
        guard let amount = store.pendingLoanApply, account != .investments else { return }
        store.pendingLoanApply = nil
        prefill = amount
        applying = true
    }

    @ViewBuilder private func loansFor(_ e: GameEngine) -> some View {
        switch account {
        case .personal: BankAccountLoans(engine: e)
        case .investments: EmptyView()
        }
    }

    private func applyCard(_ e: GameEngine) -> some View {
        let sub: String = "Ask the bank, see its offer, then choose how much"
        return Button { Haptics.tap(); prefill = nil; applying = true } label: {
            CardRow(glyph: BankGlyph.transfer, title: "Apply for a loan", subtitle: sub)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("bank-apply-loan")
    }
}

struct BankAccountLoans: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    @State private var repaying: Loan?

    var body: some View {
        let e = engine
        let s = e.state
        let personal = s.loans.filter { $0.balance > 0 }
        let owed = personal.reduce(0) { $0 + $1.balance }
        let monthly = personal.reduce(0) { $0 + $1.monthlyPayment }
        let missed = personal.reduce(0) { $0 + $1.int("miss") }
        VStack(alignment: .leading, spacing: 12) {
            BankCard(title: "You owe") {
                VStack(alignment: .leading, spacing: 8) {
                    KeyFigures(items: [
                        .init(label: "You owe", value: owed > 0 ? store.short(owed) : "Nothing", tint: owed > 0 ? P.caution : P.ink, sub: personal.isEmpty ? "" : "\(store.short(monthly)) a month"),
                        .init(label: "Credit", value: Banking.creditWord(s.credit), sub: "bank rate \(Currency.percent(s.economy.policyRate, decimals: 2))"),
                    ], columns: 2)
                    if missed > 0 {
                        Label("\(missed) loan instalment\(missed == 1 ? "" : "s") missed. Pay it before the next week: a missed payment adds a penalty and hurts your credit.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(P.loss).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            loansCard(e, personal)
        }
        .centerSheet(item: $repaying, title: "Loan details") { l in LoanDetailSheet(loanID: l.id) }
    }

    private func loansCard(_ e: GameEngine, _ loans: [Loan]) -> some View {
        BankCard(title: "Your loans") {
            VStack(alignment: .leading, spacing: 0) {
                if loans.isEmpty { EmptyState(glyph: Glyph.check, title: "You owe nothing.", centered: false) }
                ForEach(Array(loans.enumerated()), id: \.element.id) { n, l in
                    if n > 0 { Hairline() }
                    Button { repaying = l } label: { loanRow(e, l) }.buttonStyle(PressableStyle())
                }
            }
        }
    }

    private func loanRow(_ e: GameEngine, _ l: Loan) -> some View {
        let cur: Currency = l.companyID == 0 ? e.homeCurrency : (e.state.company(l.companyID).map { e.currency(for: $0) } ?? e.homeCurrency)
        let p = e.loanPayoff(loanID: l.id)
        let paid = l.originalAmount > 0 ? max(0, min(1, 1 - l.balance / l.originalAmount)) : 0
        let missed = l.int("miss")
        return HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(l.name).textStyle(.body).lineLimit(1)
                Text("\(Currency.percent(p?.yearlyRate ?? Banking.rate(of: l, state: e.state), decimals: 2)) · \(cur.tidyShort(l.monthlyPayment)) a month" + (p?.monthsLeft.map { " · \($0) months to go" } ?? ""))
                    .textStyle(.caption, tint: P.inkFaint)
                Text("\(Int(saturating: (paid * 100).rounded()))% repaid" + ((p?.interestLeft ?? 0) > 0 ? " · about \(cur.tidyShort(p!.interestLeft)) interest still to come" : ""))
                    .textStyle(.caption, tint: P.inkFaint)
                if missed > 0 { Text("\(missed) instalment\(missed == 1 ? "" : "s") missed").textStyle(.caption, tint: P.loss, weight: .medium) }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(cur.tidyShort(l.balance)).textStyle(.body, numeric: true).moneyFlash(l.balance)
                Text("left to pay").font(.caption2).foregroundStyle(P.inkFaint)
            }
            LedgerGlyph(glyph: Glyph.chevron, size: 12, tint: P.inkFaint)
        }
        .padding(.vertical, 9).contentShape(Rectangle())
    }
}

struct RepayLoanSheet: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var loanID: Int
    @State private var amount = 0.0

    var body: some View {
        Group {
            Group {
                if let e = store.engine, let l = e.state.loans.first(where: { $0.id == loanID }) {
                    let cur = l.companyID == 0 ? e.homeCurrency : (e.state.company(l.companyID).map { e.currency(for: $0) } ?? e.homeCurrency)
                    let p = e.loanPayoff(loanID: l.id)
                    let pay = min(amount, l.balance)
                    let available = e.state.cash
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(l.name).capsLabel()
                            Text(cur.tidyDisplay(l.balance)).font(.hero(34))
                            Text("left to pay · \(cur.tidyShort(l.monthlyPayment)) a month" + (p?.monthsLeft.map { " · \($0) months to go" } ?? "")).popupText(.caption)
                        }
                        HStack {
                            Button("One instalment") { amount = min(l.balance, l.monthlyPayment) }.buttonStyle(SecondaryButtonStyle(size: .compact))
                            Button("Half") { amount = (l.balance / 2).rounded() }.buttonStyle(SecondaryButtonStyle(size: .compact))
                            Button("All") { amount = l.balance }.buttonStyle(SecondaryButtonStyle(size: .compact))
                        }
                        AmountField(title: "Pay back", currency: cur, amount: $amount)
                        KeyFigures(items: [
                            .init(label: "You pay now", value: pay > 0 ? cur.tidyShort(pay) : "–"),
                            .init(label: "Left after", value: cur.tidyShort(max(0, l.balance - pay))),
                            .init(label: "Available", value: cur.tidyShort(available), tint: available < pay ? P.loss : P.ink, sub: "your account"),
                        ])
                        Button(pay > 0 ? "Pay back \(cur.tidyShort(pay))" : "Choose an amount") {
                            if store.act({ $0.repayLoan(id: loanID, amount: pay) }) == true {
                                Haptics.success()
                                store.show(pay >= l.balance - 0.5 ? "\(l.name) is paid off." : "\(cur.tidyShort(pay)) paid back.", tone: "good")
                                dismiss()
                            } else { Haptics.warning(); store.show("Not enough money to pay that back.", tone: "warn") }
                        }.buttonStyle(GoldButtonStyle()).disabled(pay <= 0)
                    }
                } else {
                    Text("This loan is paid off.").foregroundStyle(P.inkSoft)
                }
            }
        }
    }
}
