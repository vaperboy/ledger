import SwiftUI
import GameCore
import Countries
import Finance
import Investments
import Simulation

/// The bank (Group > Money > Bank): your accounts, savings and fixed deposits, your personal loans with repayment, borrowing with a
/// choice of term and the whole cost shown first, and an overview of what your companies owe. Company loans are taken and repaid in each
/// company's own Finances section; the rows here open it.
struct BankContent: View {
    @EnvironmentObject var store: GameStore
    @State private var amount = 0.0
    @State private var depositWeeks = 26
    @State private var borrow = 0.0
    @State private var term = 60
    @State private var repaying: Loan?
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine {
            let cur = e.homeCurrency
            let s = e.state
            let personal = s.loans.filter { $0.companyID == 0 }
            let owed = personal.reduce(0) { $0 + $1.balance }
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cash and savings").capsLabel()
                    Text(cur.display(s.cash + s.savings)).font(.hero(36)).foregroundStyle(s.cash + s.savings < 0 ? Theme.loss : Theme.ivory).minimumScaleFactor(0.6).lineLimit(1)
                    KeyFigures(items: [
                        .init(label: "Current account", value: store.short(s.cash), tint: s.cash < 0 ? Theme.loss : Theme.ivory),
                        .init(label: "You owe", value: owed > 0 ? store.short(owed) : "Nothing", tint: owed > 0 ? Theme.caution : Theme.ivory, sub: personal.isEmpty ? "" : "\(store.short(personal.reduce(0) { $0 + $1.monthlyPayment })) a month"),
                        .init(label: "Credit", value: Banking.creditWord(s.credit), sub: "bank rate \(Currency.percent(s.economy.policyRate, decimals: 2))"),
                    ]).padding(.top, 8)
                }
                savings(e, cur)
                deposits(e, cur)
                loans(e, cur, personal)
                borrowing(e, cur)
                companyLoans(e)
            }
            .sheet(item: $repaying) { l in RepayLoanSheet(loanID: l.id).presentationDetents([.medium, .large]) }
            .confirmAction($pending)
        }
    }

    // MARK: Savings and deposits

    private func savings(_ e: GameEngine, _ cur: Currency) -> some View {
        LedgerSection(title: "Savings", trailing: { Text(cur.display(e.state.savings)).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivoryMuted) }) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Earns interest and can be moved back any day. Loan repayments draw on it when the current account is short.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                AmountField(title: "Amount", currency: cur, amount: $amount)
                HStack {
                    Button("Save") { move(amount, cur) }.buttonStyle(QuietButtonStyle()).disabled(amount <= 0)
                    Button("Withdraw") { move(-amount, cur) }.buttonStyle(QuietButtonStyle()).disabled(amount <= 0)
                }
            }
        }
    }

    private func deposits(_ e: GameEngine, _ cur: Currency) -> some View {
        let q = e.depositQuote(amount: amount, weeks: depositWeeks)
        return LedgerSection(title: "Fixed deposits", trailing: {
            if !e.deposits.isEmpty { Text(cur.short(e.deposits.reduce(0) { $0 + $1.balance })).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivoryMuted) }
        }) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                ForEach(e.deposits) { d in
                    ListRow(symbol: "lock.fill", tint: Theme.gold, title: "Fixed deposit at \(Currency.percent(d.rate, decimals: 2))",
                            subtitle: d.weeksLeft == 0 ? "Matures this week" : "Matures in \(d.weeksLeft) week\(d.weeksLeft == 1 ? "" : "s")", trailing: cur.display(d.balance))
                }
                SectionTabs(items: GameEngine.depositTermChoices, title: { "\($0) weeks" }, selection: $depositWeeks).padding(.horizontal, -Theme.Space.margin)
                KeyFigures(items: [
                    .init(label: "Rate", value: Currency.percent(q.yearlyRate, decimals: 2), sub: "a year, fixed"),
                    .init(label: "Interest at the end", value: amount > 0 ? cur.short(q.interest) : "–", tint: Theme.gain),
                    .init(label: "Back to you", value: amount > 0 ? cur.short(amount + q.interest) : "–", sub: "in \(depositWeeks) weeks"),
                ])
                Button(amount > 0 ? "Lock \(cur.short(amount)) for \(depositWeeks) weeks" : "Enter an amount above") {
                    let a = amount, w = depositWeeks
                    pending = PendingAction(title: "Lock \(cur.short(a)) for \(w) weeks?",
                                            message: "It earns \(Currency.percent(q.yearlyRate, decimals: 2)) a year: \(cur.display(q.interest)) interest, paid with the money in \(w) weeks. Until then it is out of reach, also for bills. The interest is taxed as income.",
                                            button: "Lock it") {
                        if store.act({ $0.openDeposit(amount: a, weeks: w) }) == true { Haptics.success(); store.show("\(cur.short(a)) locked until week \((store.engine?.state.week ?? 0) + w).", tone: "good"); amount = 0 }
                        else { Haptics.warning(); store.show("Not enough on the current account for that deposit.", tone: "warn") }
                    }
                }.buttonStyle(QuietButtonStyle()).disabled(amount <= 0)
                Text("Only the current account can fund a deposit; move savings back first if needed.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    private func move(_ a: Double, _ cur: Currency) {
        guard a != 0 else { return }
        if store.act({ $0.moveToSavings(a) }) == true { Haptics.success(); store.show(a > 0 ? "\(cur.short(a)) moved to savings." : "\(cur.short(-a)) moved to the current account.", tone: "good"); amount = 0 }
        else { Haptics.warning(); store.show(a > 0 ? "Not that much on the current account." : "Not that much in savings.", tone: "warn") }
    }

    // MARK: Personal loans

    private func loans(_ e: GameEngine, _ cur: Currency, _ loans: [Loan]) -> some View {
        LedgerSection("Your loans") {
            VStack(alignment: .leading, spacing: 0) {
                if loans.isEmpty { Text("You owe nothing personally.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted) }
                ForEach(Array(loans.enumerated()), id: \.element.id) { n, l in
                    if n > 0 { Hairline() }
                    Button { repaying = l } label: { loanRow(e, cur, l) }.buttonStyle(.plain)
                }
                if !loans.isEmpty {
                    Text("Tap a loan to pay some or all of it back early. Early repayment has no fee and cuts the interest still to come.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 6)
                }
            }
        }
    }

    private func loanRow(_ e: GameEngine, _ cur: Currency, _ l: Loan) -> some View {
        let p = e.loanPayoff(loanID: l.id)
        let paid = l.originalAmount > 0 ? max(0, min(1, 1 - l.balance / l.originalAmount)) : 0
        let missed = l.int("miss")
        return HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(l.name).font(.system(size: 14)).foregroundStyle(Theme.ivory).lineLimit(1)
                Text("\(Currency.percent(p?.yearlyRate ?? Banking.rate(of: l, state: e.state), decimals: 2)) · \(cur.short(l.monthlyPayment)) a month" + (p?.monthsLeft.map { " · \($0) months to go" } ?? ""))
                    .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                Text("\(Int((paid * 100).rounded()))% repaid" + ((p?.interestLeft ?? 0) > 0 ? " · about \(cur.short(p!.interestLeft)) interest still to come" : ""))
                    .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                if missed > 0 { Text("\(missed) instalment\(missed == 1 ? "" : "s") missed").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.loss) }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(cur.short(l.balance)).font(.system(size: 14).monospacedDigit()).foregroundStyle(Theme.ivory)
                Text("left to pay").font(.caption2).foregroundStyle(Theme.ivoryFaint)
            }
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
        }
        .padding(.vertical, 9).contentShape(Rectangle())
    }

    // MARK: Borrowing

    private func borrowing(_ e: GameEngine, _ cur: Currency) -> some View {
        let q = e.loanQuote(kind: "cons", amount: borrow, termMonths: term, companyID: nil)
        let problem: String? = borrow <= 0 ? nil : q.tooSmall ? "Below the bank's smallest loan." : !q.withinLimit ? "More than the bank would lend you (\(cur.short(q.maximum)))." : nil
        return LedgerSection(title: "Borrow", trailing: { Text("up to \(cur.short(q.maximum))").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("A personal consumer loan, paid into your current account. What the bank lends depends on your credit (\(q.creditBand)), your income and what you already owe.")
                    .font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                AmountField(title: "Amount", currency: cur, amount: $borrow)
                SectionTabs(items: GameEngine.loanTermChoices, title: { $0 % 12 == 0 ? "\($0 / 12) yr" : "\($0) mo" }, selection: $term).padding(.horizontal, -Theme.Space.margin)
                KeyFigures(items: [
                    .init(label: "Interest", value: Currency.percent(q.yearlyRate, decimals: 2), sub: "a year, moves with the bank rate"),
                    .init(label: "Each month", value: borrow > 0 ? cur.short(q.monthlyPayment) : "–", sub: "\(term) payments"),
                    .init(label: "Interest in total", value: borrow > 0 ? cur.short(q.totalInterest) : "–", tint: Theme.loss),
                    .init(label: "You pay back", value: borrow > 0 ? cur.short(q.totalRepaid) : "–"),
                ], columns: 2)
                if let problem { Text(problem).font(.caption).foregroundStyle(Theme.caution) }
                Button(borrow > 0 ? "Borrow \(cur.short(borrow)) over \(term / 12 > 0 && term % 12 == 0 ? "\(term / 12) year\(term == 12 ? "" : "s")" : "\(term) months")" : "Enter an amount above") {
                    let a = borrow, t = term
                    pending = PendingAction(title: "Borrow \(cur.short(a))?",
                                            message: "\(t) monthly payments of \(cur.display(q.monthlyPayment)) at \(Currency.percent(q.yearlyRate, decimals: 2)): \(cur.display(q.totalRepaid)) in all, \(cur.display(q.totalInterest)) of it interest. The rate follows the bank rate, so the cost can change. A missed payment adds a penalty and hurts your credit.",
                                            button: "Borrow") { take(a, t, cur) }
                }.buttonStyle(QuietButtonStyle()).disabled(borrow <= 0 || problem != nil)
            }
        }
    }

    private func take(_ a: Double, _ t: Int, _ cur: Currency) {
        switch store.act({ $0.takeLoan(kind: "cons", amount: a, termMonths: t, companyID: nil) }) {
        case .ok?: Haptics.success(); store.show("\(cur.short(a)) is on your current account.", tone: "good"); borrow = 0
        case .tooSmall?: Haptics.warning(); store.show("Too small for the bank.", tone: "warn")
        default: Haptics.warning(); store.show("The bank declined: it would not lend that much.", tone: "bad")
        }
    }

    // MARK: Company loans

    @ViewBuilder private func companyLoans(_ e: GameEngine) -> some View {
        let byCompany = Dictionary(grouping: e.state.loans.filter { $0.companyID != 0 }, by: { $0.companyID })
        let rows: [(co: Company, loans: [Loan])] = byCompany.compactMap { id, ls in e.state.company(id).map { (co: $0, loans: ls) } }
            .sorted { $0.loans.reduce(0) { $0 + $1.balance } > $1.loans.reduce(0) { $0 + $1.balance } }
        LedgerSection(title: "Your companies' loans", trailing: {
            if !rows.isEmpty { Text("\(rows.count) compan\(rows.count == 1 ? "y" : "ies")").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }
        }) {
            VStack(alignment: .leading, spacing: 0) {
                if rows.isEmpty {
                    Text("None of your companies has a loan. A company borrows in its own Finances section.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
                }
                ForEach(Array(rows.enumerated()), id: \.element.co.id) { n, r in
                    if n > 0 { Hairline() }
                    let balance = r.loans.reduce(0) { $0 + $1.balance }
                    let monthly = r.loans.reduce(0) { $0 + $1.monthlyPayment }
                    let missed = r.loans.reduce(0) { $0 + $1.int("miss") }
                    Button { store.openCompany(r.co.id, section: .finances) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.co.name).font(.system(size: 13.5)).foregroundStyle(Theme.ivory).lineLimit(1)
                                Text("\(r.loans.count) loan\(r.loans.count == 1 ? "" : "s") · \(store.short(monthly, in: r.co)) a month" + (r.co.flag("loanFrozen") ? " · credit restricted" : ""))
                                    .font(.system(size: 11)).foregroundStyle(r.co.flag("loanFrozen") ? Theme.caution : Theme.ivoryFaint)
                                if missed > 0 { Text("\(missed) instalment\(missed == 1 ? "" : "s") missed").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.loss) }
                            }
                            Spacer(minLength: 8)
                            Text(store.short(balance, in: r.co)).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(Theme.ivory)
                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                        }.padding(.vertical, 9).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                if !rows.isEmpty {
                    Text("Each row opens that company's Finances, where its loans are taken and repaid. A sole trader's loans are guaranteed by you personally.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 6)
                }
            }
        }
    }
}

/// Pay back part or all of one loan: presets for one instalment, half and everything, with the balance after.
struct RepayLoanSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var loanID: Int
    @State private var amount = 0.0

    var body: some View {
        NavigationStack {
            ScrollView {
                if let e = store.engine, let l = e.state.loans.first(where: { $0.id == loanID }) {
                    let cur = l.companyID == 0 ? e.homeCurrency : (e.state.company(l.companyID).map { e.currency(for: $0) } ?? e.homeCurrency)
                    let p = e.loanPayoff(loanID: l.id)
                    let pay = min(amount, l.balance)
                    let available = l.companyID == 0 ? e.state.cash + e.state.savings : (e.state.company(l.companyID)?.cash ?? 0)
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(l.name).capsLabel()
                            Text(cur.display(l.balance)).font(.hero(34))
                            Text("left to pay · \(cur.short(l.monthlyPayment)) a month" + (p?.monthsLeft.map { " · \($0) months to go" } ?? "")).font(.caption).foregroundStyle(Theme.ivoryFaint)
                        }
                        HStack {
                            Button("One instalment") { amount = min(l.balance, l.monthlyPayment) }.buttonStyle(SmallOutlineButtonStyle())
                            Button("Half") { amount = (l.balance / 2).rounded() }.buttonStyle(SmallOutlineButtonStyle())
                            Button("All") { amount = l.balance }.buttonStyle(SmallOutlineButtonStyle())
                        }
                        AmountField(title: "Pay back", currency: cur, amount: $amount)
                        KeyFigures(items: [
                            .init(label: "You pay now", value: pay > 0 ? cur.short(pay) : "–"),
                            .init(label: "Left after", value: cur.short(max(0, l.balance - pay))),
                            .init(label: "Available", value: cur.short(available), tint: available < pay ? Theme.loss : Theme.ivory, sub: l.companyID == 0 ? "cash and savings" : "company cash"),
                        ])
                        Text("The monthly payment stays the same, so the loan ends sooner; paying it all closes it.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                        Button(pay > 0 ? "Pay back \(cur.short(pay))" : "Choose an amount") {
                            if store.act({ $0.repayLoan(id: loanID, amount: pay) }) == true {
                                Haptics.success()
                                store.show(pay >= l.balance - 0.5 ? "\(l.name) is paid off." : "\(cur.short(pay)) paid back.", tone: "good")
                                dismiss()
                            } else { Haptics.warning(); store.show("Not enough money to pay that back.", tone: "warn") }
                        }.buttonStyle(GoldButtonStyle()).disabled(pay <= 0)
                    }
                    .padding(Theme.Space.margin)
                } else {
                    Text("This loan is paid off.").foregroundStyle(Theme.ivoryMuted).padding()
                }
            }
            .ledgerBackground()
            .navigationTitle("Pay back").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
