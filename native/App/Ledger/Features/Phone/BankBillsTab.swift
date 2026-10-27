import SwiftUI
import GameCore
import Countries
import Finance
import Simulation

/// A list of coming payments with Pay now where the engine allows it: payroll is approved (or, when late, run now) through
/// `resolvePayrollAlert`; a loan instalment is paid early with `repayLoan`. Rent, supplier bills, invoices, tax and VAT leave by themselves
/// on their date (the engine has no early payment for them), and the row says so.
struct BankBillsList: View {
    @EnvironmentObject var store: GameStore
    var account: BankAccountID
    var upcoming: [Obligation]
    var cash: Double

    var body: some View {
        if let e = store.engine {
            let alerts: [PayrollAlert] = e.payrollAlerts()
            VStack(alignment: .leading, spacing: 0) {
                if upcoming.isEmpty { Text("Nothing is due.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted).padding(.vertical, 6) }
                ForEach(Array(upcoming.enumerated()), id: \.element.id) { n, u in
                    if n > 0 { Hairline() }
                    row(u, alerts, e)
                }
            }
        }
    }

    private func row(_ u: Obligation, _ alerts: [PayrollAlert], _ e: GameEngine) -> some View {
        let co: Company? = u.companyID == 0 ? nil : e.state.company(u.companyID)
        let fmt = BankFmt(store: store, company: co)
        let short: Bool = cash < u.amount
        return VStack(alignment: .leading, spacing: 4) {
            BankObligationRow(obligation: u, fmt: fmt)
            HStack(spacing: 8) {
                Text(u.detail.tidyText).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                action(u, alerts, e)
            }
            if short && u.daysAway <= 30 && account != .investments {
                Text("The account does not hold this much yet. Move money in first.").font(.system(size: 11.5)).foregroundStyle(Theme.caution)
            }
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder private func action(_ u: Obligation, _ alerts: [PayrollAlert], _ e: GameEngine) -> some View {
        switch u.kind {
        case .payroll:
            if let a = alerts.first(where: { $0.companyID == u.companyID }) {
                SmallOutlineButton(title: a.isLate ? "Pay now" : "Approve") { BankPay.resolve(store, companyID: u.companyID) }
            }
        case .loan:
            if let loanID = Int(u.id.dropFirst(4)) {
                SmallOutlineButton(title: "Pay now") { BankPay.instalment(store, loanID: loanID) }
            }
        default:
            Text("Leaves on its date").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
        }
    }
}

/// Bills: what is due in 30 days and whether it is covered, every coming payment, tax and VAT owed, the tax rules and licences, and (for a
/// company) the pay day and payroll run. The old Group > Money Overview, Taxes and Costs, and the company payroll desk, in one place.
struct BankBillsTab: View {
    @EnvironmentObject var store: GameStore
    var account: BankAccountID
    var detail: BankAccountDetail
    @State private var showRules = false

    var body: some View {
        if let e = store.engine {
            let o = e.financeOverview(companyID: account.companyID)
            let fmt = BankFmt.make(store, account)
            let co: Company? = account.companyID.flatMap { e.state.company($0) }
            VStack(alignment: .leading, spacing: 12) {
                dueCard(detail, fmt)
                BankCard(title: "Coming up", trailing: "\(detail.upcoming.count) payment\(detail.upcoming.count == 1 ? "" : "s")") {
                    BankBillsList(account: account, upcoming: detail.upcoming, cash: detail.balance)
                }
                if let co { CompanyPayroll(engine: e, company: co) }
                taxCard(o, fmt)
                rulesCard(o)
            }
        }
    }

    private func dueCard(_ d: BankAccountDetail, _ fmt: BankFmt) -> some View {
        let due: Double = d.upcoming.filter { $0.daysAway <= 30 }.reduce(0) { $0 + $1.amount }
        let short: Double = max(0, due - max(0, d.available))
        return Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Due in the next 30 days").capsLabel()
                    Spacer()
                    Chip(text: short > 0 ? "Short by \(fmt.short(short))" : "Covered", tint: short > 0 ? Theme.loss : Theme.gain)
                }
                Text(fmt.full(due)).font(.hero(30)).foregroundStyle(short > 0 ? Theme.loss : Theme.ivory).minimumScaleFactor(0.6).lineLimit(1)
                if short > 0 {
                    Text("This account will not cover what is due. Move money in, sell something or borrow before the dates below.")
                        .font(.caption).foregroundStyle(Theme.loss).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func taxCard(_ o: FinanceOverview, _ fmt: BankFmt) -> some View {
        BankCard(title: "Tax and VAT", trailing: fmt.short(o.taxesOwed) + " owed") {
            VStack(spacing: 0) {
                if o.taxes.isEmpty { Text("No tax is owed.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted) }
                ForEach(Array(o.taxes.enumerated()), id: \.element.id) { n, l in
                    FlatRow(label: l.label, value: fmt.full(l.amount), sub: l.detail.tidyMoney, rule: n > 0)
                }
                Text("Corporate tax is worked out on taxable profit, after losses carried forward. VAT is collected for the state and is not income. Tax leaves the account on its due date.")
                    .font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }
        }
    }

    @ViewBuilder private func rulesCard(_ o: FinanceOverview) -> some View {
        let estimate: Bool = o.basis.hasPrefix("Estimate")
        BankCard(title: "Rules in \(o.countryName)", trailing: estimate ? "Estimate" : "Checked") {
            VStack(alignment: .leading, spacing: 0) {
                Button { showRules.toggle(); Haptics.choose() } label: {
                    HStack {
                        Text(showRules ? "Hide the tax rules and licences" : "Show the tax rules and licences").font(.system(size: 13)).foregroundStyle(Theme.gold)
                        Spacer()
                        Image(systemName: showRules ? "chevron.up" : "chevron.down").font(.system(size: 11)).foregroundStyle(Theme.gold)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                if showRules {
                    ForEach(Array(o.rules.enumerated()), id: \.element.id) { n, r in FlatRow(label: r.label, value: r.value, rule: true) }
                    Text(o.basis).font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 6)
                    if !o.licences.isEmpty {
                        Text("Licences and registrations").capsLabel().padding(.top, 12)
                        ForEach(Array(o.licences.enumerated()), id: \.element.id) { n, l in
                            FlatRow(label: l.label, value: l.amount > 0 ? store.money(l.amount) : "free", sub: l.detail.tidyMoney, rule: n > 0)
                        }
                        Text("Fees are the game's estimate of typical official fees. Game estimates, not legal advice.").font(.caption2).foregroundStyle(Theme.ivoryFaint).padding(.top, 6)
                    }
                }
            }
        }
    }
}
