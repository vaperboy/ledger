import SwiftUI
import GameCore
import Countries
import Finance
import Simulation

/// Which of the money tiles was tapped: Transfer moves money from you into a company, Deposit is the same from inside a company's account.
enum BankMoveKind: String, Identifiable {
    case transfer, deposit
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Every payment the Bank app can make, as engine calls with their result reported. Used by the alert banner, the Bills tab and Pay bill.
@MainActor
enum BankPay {
    /// Pay a coming rent, supplier, invoice, tax or VAT bill now (`payObligationNow`): the engine settles it exactly as its date would and
    /// says what happened; the toast is the engine's real result.
    static func early(_ store: GameStore, _ o: Obligation) {
        guard let outcome = store.act({ $0.payObligationNow(o) }) else { return }
        let cur: Currency? = store.engine.flatMap { e in e.state.company(o.companyID).map { e.currency(for: $0) } }
        switch outcome {
        case .paid(let amount):
            let text: String = cur?.tidyShort(amount) ?? store.short(amount)
            store.settle(.applied, "\(text) paid: \(o.title.tidyText). Nothing more is taken on its date.", tone: "good")
            Haptics.success()
        case .refused(let why):
            store.settle(.refused(why), "")
        }
    }

    /// Pay this month's instalment now (`payLoanInstalmentNow`): it is taken once and the month-end collection skips the loan, so nothing is charged twice.
    static func instalment(_ store: GameStore, loanID: Int) {
        guard let e = store.engine, let l = e.state.loans.first(where: { $0.id == loanID }) else { store.show("That loan is already paid off.", tone: "n"); return }
        let cur: Currency = l.companyID == 0 ? e.homeCurrency : (e.state.company(l.companyID).map { e.currency(for: $0) } ?? e.homeCurrency)
        let result: Banking.EarlyInstalment? = store.act({ (g: inout GameEngine) -> Banking.EarlyInstalment in g.payLoanInstalmentNow(loanID: loanID) })
        switch result {
        case .paid(let amount)?:
            Haptics.success(); store.show("\(cur.tidyShort(amount)) paid on \(l.name). It is not taken again at month end.", tone: "good")
        case .alreadySettled?:
            store.show("This month's instalment of \(l.name) is already paid.", tone: "n")
        case .notEnoughMoney?:
            Haptics.warning(); store.show("Not enough money to pay that instalment now.", tone: "warn")
        case .noLoan?:
            store.show("That loan is already paid off.", tone: "n")
        case nil:
            break
        }
    }
}

/// Transfer and Deposit: both put money from your account into a company (the engine's `putMoneyInto`). A company pays money out only as
/// salary or dividend, so there is no way back through this sheet.
struct BankMoveSheet: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
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
        Group {
            Group {
                if let e = store.engine {
                    let legs: [Leg] = makeLegs(e)
                    let leg: Leg? = legs.indices.contains(chosen) ? legs[chosen] : legs.first
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        Text(kind.title).popupText(.figure)
                        if let leg {
                            form(leg, legs)
                        } else {
                            emptyState(e)
                        }
                    }
                }
            }
            .confirmAction($pending)
        }
    }

    @ViewBuilder private func form(_ leg: Leg, _ legs: [Leg]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if legs.count > 1 {
                VStack(spacing: 8) {
                    ForEach(legs) { l in
                        ChoiceCard(title: l.title, subtitle: l.note, selected: l.id == leg.id) { chosen = l.id }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(leg.title).popupText(.button)
                    if !leg.note.isEmpty { Text(leg.note).popupText(.caption) }
                }
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Amount").capsLabel()
                AmountField(title: "Amount", currency: leg.currency, amount: $amount)
                HStack(spacing: Theme.Space.s) {
                    Button("Half") { amount = max(0, leg.source / 2).rounded() }.buttonStyle(SecondaryButtonStyle(size: .compact))
                    Button("All") { amount = max(0, leg.source) }.buttonStyle(SecondaryButtonStyle(size: .compact))
                    Spacer(minLength: 0)
                    Text("Available " + leg.currency.tidyShort(max(0, leg.source))).popupText(.caption)
                }
            }
            // Over the limit is blocked here with the reason, so the engine never has to refuse it.
            PrimaryAction(title: amount > 0 ? "\(kind.title) \(leg.currency.tidyShort(amount))" : kind.title,
                          blockedReason: amount <= 0 ? "Enter an amount." : (amount > leg.source + 0.5 ? "More than this account can move now (\(leg.currency.tidyShort(max(0, leg.source))) available)." : nil),
                          identifier: "bank-move-go") { go(leg) }
        }
    }

    @ViewBuilder private func emptyState(_ e: GameEngine) -> some View {
        Text("There is nowhere to move money to yet. Start a company first.").popupText(.subtitle)
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
            if kind == .transfer && account == .personal {
                for co in s.liveCompanies {
                    let cur = e.currency(for: co)
                    let cid = co.id, name = co.name
                    add("To \(name)", "From your account into the company's.", s.cash, home) { a in
                        let inCompany: Double = a
                        return self.store.act({ $0.putMoneyInto(companyID: cid, amount: inCompany) }) == true ? "\(cur.tidyDisplay(a)) moved into \(name)." : nil
                    }
                }
            }
        case .company(let cid):
            guard let co = e.state.company(cid) else { return [] }
            let cur = e.currency(for: co)
            let name = co.name
            if kind == .deposit || kind == .transfer {
                add("From your account into \(name)", "Your account \(home.tidyShort(e.state.cash)).", e.state.cash, cur) { a in
                    self.store.act({ $0.putMoneyInto(companyID: cid, amount: a) }) == true ? "\(cur.tidyDisplay(a)) moved into \(name)." : nil
                }
            }
        }
        return legs
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
    var account: BankAccountID

    var body: some View {
        Group {
            if let e = store.engine, let d = e.bankAccount(account) {
                BankBillsList(account: account, upcoming: d.upcoming, cash: d.balance)
            }
        }
    }
}
