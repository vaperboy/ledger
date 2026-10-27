import SwiftUI
import GameCore
import Countries
import Finance
import Simulation

/// Which of the money tiles was tapped.
enum BankMoveKind: String, Identifiable {
    case transfer, deposit, withdraw
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Every payment the Bank app can make, as engine calls with their result reported. Used by the alert banner, the Bills tab and Pay bill.
enum BankPay {
    /// Approve the coming payroll, or run a late one now (`resolvePayrollAlert`).
    static func resolve(_ store: GameStore, companyID: Int) {
        let outcome = store.act { $0.resolvePayrollAlert(companyID: companyID) }
        let cur: Currency? = store.engine.flatMap { e in e.state.company(companyID).map { e.currency(for: $0) } }
        switch outcome {
        case .approved?:
            Haptics.success(); store.show("Payroll approved. It goes out on pay day.", tone: "good")
        case .paidLate(let paid, let short)?:
            let paidText: String = cur?.tidyShort(paid) ?? store.short(paid)
            if short > 0.5 {
                let shortText: String = cur?.tidyShort(short) ?? store.short(short)
                Haptics.warning(); store.show("Paid \(paidText). Still short \(shortText): put money into the company and pay again.", tone: "warn")
            } else { Haptics.success(); store.show("Late payroll paid: \(paidText).", tone: "good") }
        case .notNeeded(let why)?:
            Haptics.warning(); store.show(why, tone: "warn")
        case nil: break
        }
    }

    /// Pay one loan instalment early (`repayLoan`). The balance falls by the instalment; there is no fee.
    static func instalment(_ store: GameStore, loanID: Int) {
        guard let e = store.engine, let l = e.state.loans.first(where: { $0.id == loanID }) else { store.show("That loan is already paid off.", tone: "n"); return }
        let cur: Currency = l.companyID == 0 ? e.homeCurrency : (e.state.company(l.companyID).map { e.currency(for: $0) } ?? e.homeCurrency)
        let pay: Double = min(l.balance, l.monthlyPayment)
        if store.act({ $0.repayLoan(id: loanID, amount: pay) }) == true {
            Haptics.success(); store.show("\(cur.tidyShort(pay)) paid on \(l.name).", tone: "good")
        } else { Haptics.warning(); store.show("Not enough money to pay that instalment now.", tone: "warn") }
    }
}

/// Transfer, Deposit and Withdraw. Personal account: Deposit and Withdraw move money to and from savings, Transfer moves it between you and
/// a company. Company account: Deposit puts money in from you, Withdraw takes it out to you, Transfer does either. These are the engine's
/// `moveToSavings`, `putMoneyInto` and `takeMoneyOut`.
struct BankMoveSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var account: BankAccountID
    var kind: BankMoveKind
    @State private var amount = 0.0
    @State private var chosen = 0
    @State private var pending: PendingAction?

    /// One way of moving money: where it comes from and goes to, in whose currency, and how much can leave.
    private struct Leg: Identifiable {
        var id: Int
        var title: String
        var note: String
        var source: Double
        var currency: Currency
        var run: (Double) -> String?
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let e = store.engine {
                    let legs: [Leg] = makeLegs(e)
                    let leg: Leg? = legs.indices.contains(chosen) ? legs[chosen] : legs.first
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        if let leg {
                            form(leg, legs)
                        } else {
                            emptyState(e)
                        }
                    }
                    .padding(Theme.Space.margin)
                }
            }
            .ledgerBackground()
            .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .confirmAction($pending)
        }
    }

    @ViewBuilder private func form(_ leg: Leg, _ legs: [Leg]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if legs.count > 1 {
                VStack(spacing: 8) {
                    ForEach(legs) { l in
                        ChoiceCard(title: l.title, subtitle: l.note, selected: l.id == leg.id) { chosen = l.id; amount = 0 }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(leg.title).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory)
                    if !leg.note.isEmpty { Text(leg.note).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted) }
                }
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Amount").capsLabel()
                AmountField(title: "Amount", currency: leg.currency, amount: $amount)
                HStack(spacing: 8) {
                    Button("Half") { amount = max(0, leg.source / 2).rounded() }.buttonStyle(SmallOutlineButtonStyle())
                    Button("All") { amount = max(0, leg.source) }.buttonStyle(SmallOutlineButtonStyle())
                    Spacer(minLength: 0)
                    Text("Available " + leg.currency.tidyShort(max(0, leg.source))).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                }
                if amount > leg.source + 0.5 {
                    Text("More than this account can move now.").font(.caption).foregroundStyle(Theme.caution)
                }
            }
            QuietButton(title: amount > 0 ? "\(kind.title) \(leg.currency.tidyShort(amount))" : "Enter an amount", fullWidth: true) { go(leg) }
                .disabled(amount <= 0)
                .opacity(amount <= 0 ? 0.5 : 1)
        }
    }

    @ViewBuilder private func emptyState(_ e: GameEngine) -> some View {
        if let cid = account.companyID, let co = e.state.company(cid), co.form == .limited, kind != .deposit {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("A limited company cannot hand its cash to you directly.").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory)
                Text("It pays money out as a dividend (from retained profit, taxed on your return) or as your salary. The salary is set on this account's Account tab; dividends are paid from the company's Ownership section.")
                    .font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                QuietButton(title: "Open the company", fullWidth: true) { dismiss(); store.openCompany(cid, section: .finances) }
            }
        } else {
            Text("There is nowhere to move money to yet. Start a company first.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
        }
    }

    // MARK: Ways of moving money

    private func makeLegs(_ e: GameEngine) -> [Leg] {
        let home = e.homeCurrency
        var legs: [Leg] = []
        func add(_ title: String, _ note: String, _ source: Double, _ cur: Currency, _ run: @escaping (Double) -> String?) {
            legs.append(Leg(id: legs.count, title: title, note: note, source: source, currency: cur, run: run))
        }
        switch account {
        case .personal, .investments:
            let s = e.state
            if kind == .deposit || (kind == .transfer && account == .investments) {
                add("Current account to savings", "Earns interest; comes back any day.", s.cash, home) { a in
                    self.store.act({ $0.moveToSavings(a) }) == true ? "\(home.tidyShort(a)) moved to savings." : nil
                }
            }
            if kind == .withdraw || (kind == .transfer && account == .investments) {
                add("Savings to current account", "For bills, loans and buying investments.", s.savings, home) { a in
                    self.store.act({ $0.moveToSavings(-a) }) == true ? "\(home.tidyShort(a)) moved to the current account." : nil
                }
            }
            if kind == .transfer && account == .personal {
                for co in s.liveCompanies {
                    let cur = e.currency(for: co)
                    let cid = co.id, name = co.name
                    add("To \(name)", "From your current account into the company's.", s.cash, home) { a in
                        let inCompany: Double = a
                        return self.store.act({ $0.putMoneyInto(companyID: cid, amount: inCompany) }) == true ? "\(cur.tidyDisplay(a)) moved into \(name)." : nil
                    }
                    if co.form != .limited {
                        add("From \(name)", "A sole trader's money is yours; taking it out is not taxed again.", co.cash, cur) { a in
                            self.takeOut(cid, a, cur, name)
                        }
                    }
                }
            }
        case .company(let cid):
            guard let co = e.state.company(cid) else { return [] }
            let cur = e.currency(for: co)
            let name = co.name
            if kind == .deposit || kind == .transfer {
                add("From your account into \(name)", "Your current account \(home.tidyShort(e.state.cash)).", e.state.cash, cur) { a in
                    self.store.act({ $0.putMoneyInto(companyID: cid, amount: a) }) == true ? "\(cur.tidyDisplay(a)) moved into \(name)." : nil
                }
            }
            if (kind == .withdraw || kind == .transfer) && co.form != .limited {
                add("From \(name) to your account", "A sole trader's money is yours; taking it out is not taxed again.", co.cash, cur) { a in
                    self.takeOut(cid, a, cur, name)
                }
            }
        }
        return legs
    }

    private func takeOut(_ cid: Int, _ a: Double, _ cur: Currency, _ name: String) -> String? {
        switch store.act({ $0.takeMoneyOut(companyID: cid, amount: a) }) {
        case .ok?: return "\(cur.tidyDisplay(a)) moved from \(name) to your account."
        case .dividendOnly?: store.show("A limited company can only pay dividends.", tone: "warn"); return ""
        default: return nil
        }
    }

    // MARK: Doing it

    /// Routine moves run at once. A move of more than half of what the source holds is material, so it asks first.
    private func go(_ leg: Leg) {
        let a = amount
        guard a > 0 else { Haptics.warning(); store.show("Enter an amount first.", tone: "warn"); return }
        let big: Bool = leg.source > 0 && a > leg.source * 0.5
        let run: () -> Void = {
            if let done = leg.run(a) {
                if !done.isEmpty { Haptics.success(); store.show(done, tone: "good") }
                amount = 0
            } else {
                Haptics.warning(); store.show("There is not \(leg.currency.tidyDisplay(a)) available to move.", tone: "warn")
            }
        }
        if big {
            pending = PendingAction(title: "Move \(leg.currency.tidyShort(a))?",
                                    message: "\(leg.title): more than half of what the account holds (\(leg.currency.tidyDisplay(leg.source))). Check that bills due soon are still covered.",
                                    button: "Move it", amount: nil, currency: leg.currency, run: run)
        } else { run() }
    }
}

/// Pay bill: everything coming up on the account, with Pay now where the engine allows it.
struct BankPaySheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var account: BankAccountID

    var body: some View {
        NavigationStack {
            ScrollView {
                if let e = store.engine, let d = e.bankAccount(account) {
                    BankBillsList(account: account, upcoming: d.upcoming, cash: d.balance)
                        .padding(Theme.Space.margin)
                }
            }
            .ledgerBackground()
            .navigationTitle("Pay bill").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
