import SwiftUI
import Charts
import GameCore
import Countries
import Finance
import Businesses
import Events
import Simulation

/// The parts of a company's Finances tab: Summary, Ownership and Settings. Every payment, loan and money move is in the Bank
/// app, on this company's account ("Open in Bank").
enum CompanyMoneyPart: String, CaseIterable, Hashable {
    case summary = "Summary", owners = "Ownership", settings = "Settings"
    /// The tab row.
    static let tabs: [CompanyMoneyPart] = [.summary, .owners, .settings]
}

/// "Open in Bank": all money handling (transfers, loans, deposits, taxes, bills, payroll approval, statements) lives in the Bank app.
/// Opens the Bank app on THIS company's account (plain navigation, so no toast); `tab` picks the Bills tab for the pay buttons.
struct OpenInBankButton: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var title = "Open in Bank"
    var tab: BankTab = .account
    var body: some View {
        QuietButton(title: title, fullWidth: true) { store.openBank(.company(companyID), tab: tab) }
            .accessibilityHint("Opens the Bank app")
    }
}

/// One company's Finances tab: a read-only, scannable view of the money, with the company decisions (dividends, shares, selling,
/// settings) kept here and every payment handled in the Bank app.
struct CompanyMoney: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @Binding var part: CompanyMoneyPart

    var body: some View {
        CompanyMoneySummary(engine: engine, company: company, part: $part)
            .navigationDestination(isPresented: Binding(get: { part != .summary }, set: { if !$0 { part = .summary } })) {
                MoneyPageDestination(part: part, companyID: company.id)
            }
    }
}

/// The full-screen page a row of the Finances table opens: Ownership or the company's own settings.
struct MoneyPageDestination: View {
    @EnvironmentObject var store: GameStore
    var part: CompanyMoneyPart
    var companyID: Int

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            SettingsPage(title: part.rawValue, subtitle: co.name) { content(e, co) }
        } else {
            Text("This company no longer exists.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    @ViewBuilder private func content(_ e: GameEngine, _ co: Company) -> some View {
        switch part {
        case .summary: EmptyView()
        case .owners: CompanyOwnerMoney(engine: e, company: co)
        case .settings: CompanySettings(engine: e, company: co)
        }
    }
}

// MARK: Summary

/// Read-only: where the money goes and the margins under it, what is owed, then ownership and legal form. Cash is on the Overview, what is
/// coming up is in the Bank and Accounting, and the reports are in the Reports app.
struct CompanyMoneySummary: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @Binding var part: CompanyMoneyPart

    var body: some View {
        let cur = engine.currency(for: company)
        let o = engine.financeOverview(companyID: company.id)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            CompanyStatsFigures(engine: engine, company: company, block: .spending)
            owedCard(cur, o)
            CompanyPaymentStress(engine: engine, company: company)
            settingsTable(cur)
            CompanyStatsFigures(engine: engine, company: company, block: .legal)
            CompanyLabourCard(engine: engine, company: company)
        }
    }

    // MARK: Cards

    private func owedCard(_ cur: Currency, _ o: FinanceOverview) -> some View {
        let h = engine.companyHealth(company)
        let debtTint: Color = h.debt > 0 ? Theme.loss : Theme.ivory
        let taxTint: Color = o.taxesOwed > 0 ? Theme.caution : Theme.ivory
        let dueTint: Color = o.dueWithin30Days > max(0, company.cash) ? Theme.loss : Theme.ivory
        let cells: [StatStrip.Cell] = [
            .init(label: "Tax and VAT owed", value: cur.tidyShort(o.taxesOwed), tint: taxTint),
            .init(label: "Debt", value: cur.tidyShort(h.debt), tint: debtTint),
            .init(label: "Due in 30 days", value: cur.tidyShort(o.dueWithin30Days), tint: dueTint),
        ]
        return Card(padding: 14, radius: Theme.Radius.card) {
            VStack(alignment: .leading, spacing: 10) {
                StatStrip(cells: cells, ruled: false)
                loansRow(cur, h.debt)
            }
            .environment(\.insideCard, true)
        }
    }

    /// Compact loans row: what the company owes on loans, (loans are applied for and repaid in the Bank app on the Phone).
    private func loansRow(_ cur: Currency, _ debt: Double) -> some View {
        let loans = engine.state.loans.filter { $0.companyID == company.id && $0.balance > 0 }
        let monthly = loans.reduce(0) { $0 + $1.monthlyPayment }
        let sub: String = loans.isEmpty ? "No loans" : "\(loans.count) \(loans.count == 1 ? "loan" : "loans") · \(cur.tidyShort(monthly)) a month"
        return VStack(alignment: .leading, spacing: 8) {
            FlatRow(label: "Loans", value: cur.tidyShort(debt), sub: sub, rule: true)
        }
    }

    // MARK: Table of settings

    /// One row per area of the company's money; each opens a full page (the decisions there are big: dividends, selling, closing).
    private func settingsTable(_ cur: Currency) -> some View {
        let canSell = CompanySale.canSell(engine.state, companyID: company.id)
        let whole: Double = CompanySale.estimatedValue(engine.state, companyID: company.id, data: engine.data)
        let share: String = "You own \(Int(company.ownership.rounded()))%" + (canSell ? ", worth about " + cur.tidyShort(whole * company.ownership / 100) : "")
        let form: String = company.form == .limited ? "Limited company" : "Sole trader"
        let closed: Bool = company.status == .closed
        return SharpTable {
            SettingsTableRow(title: "Ownership", note: "Dividends, owners, shares, selling", value: share) { part = .owners }
            SettingsTableRow(title: "Legal form and trading", note: "Sole trader or limited, rename, close for a while or wind up", value: closed ? "Closed for now" : form, valueTint: closed ? Theme.caution : Theme.ivory) { part = .settings }
        }
    }
}

/// What unpaid loans, bills and VAT have set in motion: restricted credit, a called loan, suppliers who want cash, overdue VAT.
struct CompanyPaymentStress: View {
    var engine: GameEngine
    var company: Company

    var body: some View {
        let cur = engine.currency(for: company)
        let loans = engine.state.loans.filter { $0.companyID == company.id }
        let missed = loans.reduce(0) { $0 + $1.int("miss") }
        let called = company.int("loanCall")
        let weeksLeft = called - engine.state.week
        let sup = company.int("supCut")
        let vatOver = company.num("vatOver")
        let billsOwed = (company.payables["rent"] ?? 0) + (company.payables["other"] ?? 0)
        if missed > 0 || company.flag("loanFrozen") || called != 0 || sup > 0 || vatOver > 1 {
            CardSection("Behind on payments") {
                VStack(alignment: .leading, spacing: 6) {
                    if called != 0 { line("The bank has called the loan: pay the next instalment within \(max(0, weeksLeft).weeksText) or the company is wound up.", Theme.loss) }
                    else if missed > 0 { line("\(missed) loan instalment\(missed == 1 ? "" : "s") missed. Unpaid interest and a penalty were added to the loan.", Theme.loss) }
                    if company.flag("loanFrozen") { line("Credit restricted: no new loans until the instalments are back on track.", Theme.caution) }
                    if vatOver > 1 { line("VAT overdue \(cur.tidyShort(vatOver)), with interest running and a penalty added.", Theme.loss) }
                    if sup >= 2 { line("Suppliers have stopped delivering stock until the overdue bills are paid.", Theme.loss) }
                    else if sup == 1 { line("Suppliers only deliver stock against cash in the account.", Theme.caution) }
                    if billsOwed > 0 { line("Rent and supplier bills waiting for month end: \(cur.tidyShort(billsOwed)).", Theme.ivoryMuted) }
                }
            }
        }
    }
    private func line(_ text: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: tint == Theme.ivoryMuted ? "info.circle" : "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(tint).padding(.top, 2)
            Text(text).font(.system(size: 13.5, weight: tint == Theme.ivoryMuted ? .regular : .medium)).foregroundStyle(tint == Theme.ivoryMuted ? Theme.ivoryMuted : Theme.ivory).fixedSize(horizontal: false, vertical: true)
        }
    }
}


// MARK: Ownership (company decisions)

/// Company decisions: dividend, owners and shares, going public, buy-back, selling. Payments are in the Bank app.
struct CompanyOwnerMoney: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var amount = 0.0
    @State private var pending: PendingAction?

    var body: some View {
        let cur = engine.currency(for: company)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if company.form == .limited {
                CardSection(title: "Pay a dividend", trailing: {
                    Text("Company cash " + cur.tidyShort(company.cash)).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
                }) {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        AmountField(title: "Amount", currency: cur, amount: $amount)
                        Button("Pay a dividend…") { confirmDividend(cur) }.buttonStyle(QuietButtonStyle())
                        Text("Most you can pay out now: \(cur.tidyDisplay(engine.maximumDividend(companyID: company.id))). Dividends come from retained profit and are taxed on your return.")
                            .font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            CompanyOwnershipSection(engine: engine, company: company)
            CompanySaleSection(engine: engine, company: company)
        }
        .confirmAction($pending)
    }

    private func confirmDividend(_ cur: Currency) {
        guard amount > 0 else { Haptics.warning(); store.show("Enter an amount first.", tone: "warn"); return }
        let amt = amount
        let after: Double = max(0, company.cash - amt)
        let most: Double = engine.maximumDividend(companyID: company.id)
        let message: String = "The cash leaves the company for good: \(cur.tidyDisplay(after)) stays in it. Dividend tax is due on your personal return; co-owners get their share. Most you can pay now: \(cur.tidyDisplay(most))."
        pending = PendingAction(title: "Pay \(cur.tidyDisplay(amt)) as a dividend?", message: message, button: "Pay dividend", destructive: true) {
            switch store.act({ $0.payDividend(companyID: company.id, amount: amt) }) {
            case .ok?: Haptics.success(); amount = 0; store.show("Dividend of \(cur.tidyDisplay(amt)) paid.", tone: "good")
            case .noRetainedProfit?: Haptics.warning(); store.show("There are no retained profits to pay out.", tone: "warn")
            case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash in the company.", tone: "warn")
            case nil: break
            default: Haptics.warning(); store.show("A dividend of that size is not possible now.", tone: "warn")
            }
        }
    }
}
